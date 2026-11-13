import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const L = require(path.join(process.env.CV_OUT, 'components/detail/DetailLogic.js'));

function item(o = {}) {
  return { type: 'movie', title: '', seriesTitle: '', year: 0, premiereDate: '', childCount: 0, runtimeMs: 0,
    officialRating: '', width: 0, height: 0, container: '', tags: [], id: '', seasonNumber: -1, seasonId: '',
    state: { played: false, positionMs: 0 }, ...o };
}

test('formatClock', () => {
  assert.equal(L.formatClock(65000), '01:05');
  assert.equal(L.formatClock(5025000), '1:23:45');
  assert.equal(L.formatClock(-5), '00:00');
});
test('formatRuntime', () => {
  assert.equal(L.formatRuntime(0), '');
  assert.equal(L.formatRuntime(45 * 60000), '45分钟');
  assert.equal(L.formatRuntime(123 * 60000), '2小时3分钟');
  assert.equal(L.formatRuntime(120 * 60000), '2小时');
});
test('formatSize', () => {
  assert.equal(L.formatSize(0), '0 B');
  assert.equal(L.formatSize(1536), '1.5 KB');
  assert.equal(L.formatSize(4.2 * 1024 ** 3), '4.2 GB');
});
test('formatRating / episodeCode', () => {
  assert.equal(L.formatRating(0), '');
  assert.equal(L.formatRating(7.86), '7.9');
  assert.equal(L.episodeCode(1, 2), 'S01E02');
  assert.equal(L.episodeCode(-1, 12), 'E12');
});
test('mediaBadges', () => {
  assert.deepEqual(L.mediaBadges(item({ width: 3840, height: 2160, container: 'mkv', tags: ['HDR', 'HEVC'] })),
    ['4K', 'HDR', 'HEVC', 'MKV']);
  assert.deepEqual(L.mediaBadges(item({ width: 1920, height: 800, container: 'mp4' })), ['1080P', 'MP4']);
  assert.deepEqual(L.mediaBadges(item()), []);
});
test('metaParts', () => {
  assert.deepEqual(L.metaParts(item({ year: 2023, runtimeMs: 7200000, officialRating: 'PG-13' })), ['2023', '2小时', 'PG-13']);
  assert.deepEqual(L.metaParts(item({ premiereDate: '2019-05-01' })), ['2019']);
});
test('pickNextEpisode', () => {
  const ep = (played, pos = 0) => item({ state: { played, positionMs: pos } });
  assert.equal(L.pickNextEpisode([]), -1);
  assert.equal(L.pickNextEpisode([ep(true), ep(false), ep(false)]), 1);
  assert.equal(L.pickNextEpisode([ep(true), ep(false), ep(false, 5000)]), 2);
  assert.equal(L.pickNextEpisode([ep(false), ep(true), ep(false)]), 2);
  assert.equal(L.pickNextEpisode([ep(true), ep(true)]), 0);
});
test('queueAfter / pickSeasonIndex', () => {
  const eps = [item({ id: 'a' }), item({ id: 'b' }), item({ id: 'c' })];
  assert.deepEqual(L.queueAfter(eps, 0), ['b', 'c']);
  const ss = [item({ id: 's0', seasonNumber: 0 }), item({ id: 's1', seasonNumber: 1 }), item({ id: 's2', seasonNumber: 2 })];
  assert.equal(L.pickSeasonIndex(ss, '', -1), 1);
  assert.equal(L.pickSeasonIndex(ss, 's2', -1), 2);
  assert.equal(L.pickSeasonIndex(ss, '', 0), 0);
  assert.equal(L.pickSeasonIndex([], '', -1), -1);
});
test('guessQuery / tmdbTypeFor', () => {
  assert.equal(L.guessQuery(item({ title: 'The.Matrix.1999.1080p.BluRay.x264.mkv' })), 'The Matrix');
  assert.equal(L.guessQuery(item({ title: '[字幕组] 流浪地球 2160p.mp4' })), '流浪地球');
  assert.equal(L.tmdbTypeFor(item({ type: 'episode' })), 'tv');
  assert.equal(L.tmdbTypeFor(item({ type: 'video' })), 'movie');
});
test('withPlayed', () => {
  const a = item({ id: 'x', state: { played: false, positionMs: 500, favorite: true, playCount: 1, lastPlayed: 2 }, images: {}, genres: [] });
  const b = L.withPlayed(a, true);
  assert.equal(b.id, 'x');
  assert.equal(b.state.played, true);
  assert.equal(b.state.positionMs, 0);
  assert.equal(b.state.favorite, true);
  assert.equal(a.state.played, false);
});
