import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const L = require(path.join(process.env.CV_OUT, 'components/settings/SettingsLogic.js'));

test('normalizeServerUrl', () => {
  assert.equal(L.normalizeServerUrl(' 192.168.1.10:8096 '), 'http://192.168.1.10:8096');
  assert.equal(L.normalizeServerUrl('https://emby.example.com/'), 'https://emby.example.com');
  assert.equal(L.normalizeServerUrl('http://h:8096/web/index.html'), 'http://h:8096');
  assert.equal(L.normalizeServerUrl('http://h:8096/emby/web/'), 'http://h:8096/emby');
  assert.equal(L.normalizeServerUrl('HTTPS://H/jf#/home'), 'https://H/jf');
  assert.equal(L.normalizeServerUrl(''), '');
  assert.equal(L.normalizeServerUrl('ftp://x'), '');
  assert.equal(L.normalizeServerUrl('http://'), '');
});
test('bitrate + index helpers', () => {
  assert.equal(L.bitrateLabel(0), '原画');
  assert.equal(L.bitrateLabel(20000000), '20 Mbps');
  assert.equal(L.bitrateLabel(15000000), '15 Mbps');
  assert.equal(L.indexOfNumber(L.SPEED_OPTIONS, 1.25), 3);
  assert.equal(L.indexOfString(L.TMDB_LANG_OPTIONS, 'en-US'), 3);
  assert.equal(L.indexOfString(L.TMDB_LANG_OPTIONS, 'xx'), -1);
});
test('status + kind + tmdb key', () => {
  assert.equal(L.sourceStatusText('emby', true, 'tok', ''), '已登录');
  assert.equal(L.sourceStatusText('quark', true, '', ''), '未登录');
  assert.equal(L.sourceStatusText('emby', false, 'tok', ''), '已停用');
  assert.equal(L.kindLabel('jellyfin'), 'Jellyfin');
  assert.equal(L.tmdbKeyLooksValid('0123456789abcdef0123456789abcdef'), true);
  assert.equal(L.tmdbKeyLooksValid('abc'), false);
  assert.equal(L.tmdbKeyLooksValid('eyJ' + 'a'.repeat(60)), true);
});
