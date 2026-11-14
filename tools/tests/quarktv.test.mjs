import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const S = require(path.join(process.env.CV_OUT, 'quark/QuarkTvSign.js'));
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex');
const DEV = '0123456789abcdef0123456789abcdef';
const TM = '1731650000000';

test('signRequest matches fixed vectors', () => {
  const s = S.signRequest('get', '/file', TM, DEV, S.QuarkTvConst.SIGN_KEY, sha, md5);
  assert.equal(s.tm, TM);
  assert.equal(s.token, 'a89a4de8763ef08abce48e29bce90fd0ae180b6ca22e14de2fcc50012e53a656');
  assert.equal(s.reqId, 'c6dd51bec90947d42bb95c2099c3afa0');
});

test('apiQuery carries device fields and call params win', () => {
  const sig = S.signRequest('GET', '/file', TM, DEV, 'k', sha, md5);
  const q = S.apiQuery(sig, 'AT', DEV, { method: 'list', parent_fid: '0', category: '', channel: 'X' });
  assert.equal(q.req_id, sig.reqId);
  assert.equal(q.access_token, 'AT');
  assert.equal(q.device_id, DEV);
  assert.equal(q.platform, 'tv');
  assert.equal(q.app_ver, '1.5.6');
  assert.equal(q.activity_rect, '{}');
  assert.equal(q.method, 'list');
  assert.equal(q.channel, 'X');
  assert.equal(q.category, '');
  // empty values are kept and encoded
  const enc = S.encodeQuery({ a: '', b: '{}', c: 'Adreno (TM) 550' });
  assert.equal(enc, 'a=&b=%7B%7D&c=Adreno%20(TM)%20550');
});

test('tokenBody uses code or refresh_token', () => {
  const a = S.tokenBody('r', DEV, 'C1', false);
  assert.equal(a.code, 'C1');
  assert.equal(a.refresh_token, undefined);
  assert.equal(a.device_model, 'M2004J7AC');
  const b = S.tokenBody('r', DEV, 'RT', true);
  assert.equal(b.refresh_token, 'RT');
  assert.equal(b.code, undefined);
  assert.equal(b.access_token, undefined);
});

test('token-invalid and pending classification', () => {
  assert.equal(S.isTokenInvalid(-1, 11001, 'Access Token无效'), true);
  assert.equal(S.isTokenInvalid(-1, 10001, ''), true);
  assert.equal(S.isTokenInvalid(400, 0, 'access_token expired'), true);
  assert.equal(S.isTokenInvalid(-1, 11000, 'Refresh Token无效'), false);
  assert.equal(S.isTokenInvalid(-1, 11003, '用户未确认授权'), false);
  assert.equal(S.isLoginPending(11003, ''), true);
  assert.equal(S.isLoginPending(0, '用户未确认授权'), true);
  assert.equal(S.isLoginPending(11001, 'Access Token无效'), false);
});

test('qrDataUri detects image type', () => {
  assert.equal(S.qrDataUri('iVBORw0KGgo'), 'data:image/png;base64,iVBORw0KGgo');
  assert.equal(S.qrDataUri('/9j/4AAQ'), 'data:image/jpeg;base64,/9j/4AAQ');
  assert.equal(S.qrDataUri('data:image/png;base64,x'), 'data:image/png;base64,x');
});

test('tvToFile and paging', () => {
  const f = S.tvToFile({ fid: 'f1', filename: 'A &amp; B.mkv', isdir: 0, category: 1, size: 9, updated_at: 1700000000000,
    file_type: 'video', thumbnail_url: 't' }, 'p0');
  assert.equal(f.fid, 'f1');
  assert.equal(f.name, 'A & B.mkv');
  assert.equal(f.parentFid, 'p0');
  assert.equal(f.isDir, false);
  assert.equal(f.category, 1);
  assert.equal(f.updatedAt, 1700000000000);
  assert.equal(f.thumbnail, 't');
  assert.equal(S.tvToFile({ fid: 'd', isdir: 1, parent_fid: 'x' }, 'p').isDir, true);
  assert.equal(S.tvToFile({ fid: 'd', isdir: 1, parent_fid: 'x' }, 'p').parentFid, 'x');
  assert.equal(S.hasMorePages(0, 100, 100, 250), true);
  assert.equal(S.hasMorePages(2, 100, 50, 250), false);
  assert.equal(S.hasMorePages(0, 100, 100, 100), false);
  assert.equal(S.hasMorePages(0, 100, 0, 500), false);
});

test('tvQualities sorts best first and drops unusable entries', () => {
  const q = S.tvQualities([
    { resolution: 'normal', url: 'n', width: 960 },
    { resolution: '4k', url: '' },
    { resolution: 'super', url: 's', accessable: 1, duration: 60 },
    { resolution: 'high', url: 'h', accessable: 0 }
  ]);
  assert.deepEqual(q.map((x) => x.resolution), ['super', 'normal']);
  assert.equal(q[0].label, '超清 1080P');
  assert.equal(q[0].durationSec, 60);
});

test('tvNickname and device id', () => {
  assert.equal(S.tvNickname({ nickname: 'n' }), 'n');
  assert.equal(S.tvNickname({ user_name: 'u' }), 'u');
  assert.equal(S.tvNickname(undefined), '');
  assert.match(S.newDeviceId('seed', md5), /^[0-9a-f]{32}$/);
});
