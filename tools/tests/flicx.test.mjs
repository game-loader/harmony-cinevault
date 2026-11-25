import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { FlicxMapper: M } = require(path.join(process.env.CV_OUT, 'flicx/FlicxMapper.js'));
const root = 'https://fli.cx';

test('online search distinguishes films, TV, anime and people; IDs round trip even for specials', () => {
  const film = { id: 'tt1375666', title: 'Inception', runtime: 148, year: 2010 };
  const show = { id: 'tt18347622', kind: 'show', title: 'Bodies', still: '/poster.jpg' };
  const items = M.searchItems({ results: [null, show, film, film,
    { ...show, id: 'anilist-114123' }, { ...film, kind: 'person' }, { title: 'No ID' }] }, 'flicx');
  assert.deepEqual(items.map(i => [i.id, i.sourceId, i.type]), [
    ['flicx-tv-tt18347622', 'flicx', 'series'], ['flicx-movie-tt1375666', 'flicx', 'movie']]);
  assert.equal(items[1].runtimeMs, 148 * 60000);
  assert.equal(M.isCjkQuery('3 Body 三体'), true);
  assert.equal(M.isCjkQuery('Bodies'), false);
  const ep = M.parseMediaId(items[0].id + '-s0e12');
  assert.deepEqual([ep.kind, ep.imdbId, ep.season, ep.episode], ['tv','tt18347622',0,12]);
  assert.equal(M.parseMediaId(items[1].id + '-s1e1'), undefined);
  assert.equal(M.parseMediaId(items[0].id + '-s1e0'), undefined);
});

test('only confirmed HTTPS HLS sources reach AVPlayer; dedicated first, alternatives stable and unique', () => {
  const signed = 'https://s.fli.cx/s/asset.m3u8?sig=a%2Fb';
  const source = { kind: 'hls', name: 'Vega', src: signed, has: true };
  const opts = M.sources({ sources: [null, source, { ...source, name: 'Duplicate' },
    { ...source, src: '/api/s/d.m3u8', name: 'Main', group: 'dedicated', quality: '1080p' },
    { ...source, src: '/bad', has: false }, { ...source, src: '/unknown', has: undefined },
    { ...source, kind: 'embed', src: '/embed' }, { ...source, src: '//outside.test' },
    { ...source, src: 'http://invalid.test/s' }] }, root);
  assert.deepEqual(opts.map(o => o.url), [root + '/api/s/d.m3u8', signed]);
  assert.match(opts[0].label, /Main.*1080p/);
  assert.match(opts[1].label, /Vega/);
});

test('subtitle menu shows language as well as release and keeps the remote track index', () => {
  const tracks = M.subtitles({ tracks: [null, { language: 'en', src: '/sub/1', format: 'vtt' },
    { language: 'zh', src: '/sub/2', format: 'vtt', label: 'Bodies.S01.COMPLETE' },
    { language: 'zh-Hans', src: 'https://s.fli.cx/sub/3', format: 'vtt' },
    { language: 'zh', src: '', format: 'vtt' }] }, root);
  assert.equal(tracks.length, 3);
  const cn = tracks.find(t => t.language === 'zh');
  assert.deepEqual([cn.index, cn.codec, cn.isExternal, cn.url], [2, 'vtt', true, root + '/sub/2']);
  assert.match(cn.title, /中文.*Bodies/);
  assert.equal(tracks[0].language, 'zh-Hans');
});

test('website handoff opens the requested film or episode on Flicx', () => {
  assert.equal(M.watchPage('flicx-movie-tt1375666'), root + '/watch/tt1375666');
  assert.equal(M.watchPage('flicx-tv-tt18347622-s0e4'), root + '/watch/tt18347622/s0e4');
  assert.equal(M.watchPage('flicx-tv-tt18347622-s2'), '');
  assert.equal(M.watchPage('https://unrelated.test'), '');
});
