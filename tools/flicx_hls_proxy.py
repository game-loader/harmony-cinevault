#!/usr/bin/env python3
"""Serve a remote HLS presentation through curl_cffi for a local media player."""

import argparse
import re
import sys
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urljoin, urlsplit

from curl_cffi import requests

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade",
}
URI_ATTRIBUTE = re.compile(r'URI="([^"]+)"')


def allowed_upstream(url):
    parts = urlsplit(url)
    return parts.scheme == "https" and parts.hostname in {"fli.cx", "s.fli.cx"} and not parts.username


def local_url(handler, upstream):
    return "http://{}:{}/hls?{}".format(
        handler.server.server_name, handler.server.server_port, urlencode({"url": upstream}))


def rewrite_playlist(body, base_url, handler):
    lines = []
    for line in body.decode("utf-8-sig").splitlines():
        if line.startswith("#"):
            line = URI_ATTRIBUTE.sub(lambda match: 'URI="{}"'.format(
                local_url(handler, urljoin(base_url, match.group(1)))), line)
        elif line.strip():
            line = local_url(handler, urljoin(base_url, line.strip()))
        lines.append(line)
    return ("\n".join(lines) + "\n").encode("utf-8")


@lru_cache(maxsize=1)
def session(profile):
    return requests.Session(impersonate=profile)


class HlsHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_HEAD(self):
        self.proxy(head=True)

    def do_GET(self):
        self.proxy(head=False)

    def proxy(self, head=False):
        query = parse_qs(urlsplit(self.path).query)
        upstream = query.get("url", [""])[0]
        if urlsplit(self.path).path != "/hls" or not allowed_upstream(upstream):
            self.send_error(400, "Only Flicx HTTPS HLS URLs are accepted")
            return

        headers = {"Referer": "https://fli.cx/"}
        if self.headers.get("Range"):
            headers["Range"] = self.headers["Range"]
        try:
            response = session(self.server.profile).get(
                upstream, headers=headers, timeout=(10, 30), allow_redirects=True)
        except requests.RequestsError as error:
            self.send_error(502, "Flicx request failed: {}".format(error))
            return

        if response.status_code >= 400:
            print("upstream", response.status_code, upstream, file=sys.stderr)
        body = b"" if head else response.content
        content_type = response.headers.get("Content-Type", "application/octet-stream")
        playlist = ".m3u8" in urlsplit(response.url).path.lower() or "mpegurl" in content_type.lower()
        if playlist and response.status_code == 200:
            body = b"" if head else rewrite_playlist(response.content, response.url, self)
            content_type = "application/vnd.apple.mpegurl"

        self.send_response(response.status_code)
        for name, value in response.headers.items():
            if name.lower() not in HOP_BY_HOP and name.lower() not in {
                    "content-length", "content-type", "content-encoding"}:
                self.send_header(name, value)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="Flicx master or media playlist URL")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--impersonate", default="chrome", help="curl_cffi browser profile")
    args = parser.parse_args()
    if not allowed_upstream(args.url):
        parser.error("url must use https and belong to fli.cx or s.fli.cx")

    server = ThreadingHTTPServer((args.host, args.port), HlsHandler)
    server.profile = args.impersonate
    server.server_name = args.host
    local = local_url(type("Handler", (), {"server": server})(), args.url)
    print(local, flush=True)
    print("Play this URL with your client; press Ctrl-C to stop.", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        session.cache_clear()


if __name__ == "__main__":
    main()
