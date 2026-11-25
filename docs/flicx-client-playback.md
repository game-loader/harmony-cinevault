# Flicx 客户端 HLS 播放

原生 AVPlayer 会直接请求 Flicx HLS 的每个子清单和分片；`tools/flicx_hls_proxy.py` 用 `curl_cffi` 的 Chrome TLS 指纹统一转发，并将所有远端 URI 改写成客户端可访问的本地 URL。

## 运行

```sh
python3 -m pip install curl_cffi
python3 tools/flicx_hls_proxy.py 'https://fli.cx/api/s/MASTER.m3u8' --port 8765
```

第一行输出就是播放地址，例如：

```text
http://127.0.0.1:8765/hls?url=https%3A%2F%2Ffli.cx%2Fapi%2Fs%2FMASTER.m3u8
```

将它交给 mpv、VLC 或 ffmpeg：

```sh
mpv 'http://127.0.0.1:8765/hls?url=...'
ffplay 'http://127.0.0.1:8765/hls?url=...'
ffmpeg -i 'http://127.0.0.1:8765/hls?url=...' -frames:v 1 -f null -
```

主清单地址来自 Flicx `/api/sources/{imdbId}` 的 `src` 字段；以 `/` 开头的地址加上 `https://fli.cx`。签名地址会变化，应使用当次接口返回值。

代理支持主/子清单、`EXT-X-MAP`、密钥 URI、视频分片和 Range 请求。设备播放时把 `--host` 设为 `0.0.0.0`，并用运行代理的电脑局域网地址替换输出中的 `0.0.0.0`。

## 本次网络实测

以《The Matrix》（`tt0133093`）和《Breaking Bad》S01E01（`tt0903747`）验证：默认 curl、`curl_cffi`、Chrome UA、Referer、AVPlayer UA 均能取得子清单 200，初始化段与视频分片 Range 请求为 206；当前环境未复现所述 403。部分外部线路独立存在 404/503/超时，与请求头无关，应优先选择 dedicated 线路。
