import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const L = require(path.join(process.env.CV_OUT, 'components/MediaLogic.js'));

function item(o) {
  return Object.assign({ sourceId: 's', id: '1', type: 'movie', title: 't', year: 0, rating: 0, premiereDate: '',
    runtimeMs: 0, seriesTitle: '', seasonNumber: -1, episodeNumber: -1, childCount: 0,
    images: { poster: '', backdrop: '', logo: '', thumb: '' },
    state: { played: false, favorite: false, positionMs: 0, playCount: 0, lastPlayed: 0 } }, o);
}

test('settleAll keeps order and errors', async () => {
  const r = await L.settleAll([Promise.resolve(1), Promise.reject(new Error('boom')), Promise.resolve(3)]);
  assert.deepEqual(r.map((x) => x.ok), [true, false, true]);
  assert.equal(r[1].error, 'boom');
  assert.equal(r[2].value, 3);
  assert.deepEqual(await L.settleAll([]), []);
});

test('roundRobin and dedupe', () => {
  assert.deepEqual(L.roundRobin([[1, 2, 3], [4], [5, 6]], 5), [1, 4, 5, 2, 6]);
  const a = item({ id: 'a' });
  assert.equal(L.dedupe([a, item({ id: 'a' }), item({ id: 'b' })]).length, 2);
});

test('shuffle deterministic and a permutation', () => {
  const x = [1, 2, 3, 4, 5, 6];
  assert.deepEqual(L.shuffle(x, 42), L.shuffle(x, 42));
  assert.deepEqual(L.shuffle(x, 7).sort(), x);
});

test('progress / labels', () => {
  assert.equal(L.progressOf(item({ runtimeMs: 1000, state: { positionMs: 250, lastPlayed: 0 } })), 0.25);
  assert.equal(L.progressOf(item({})), 0);
  assert.equal(L.ratingText(7.456), '7.5');
  assert.equal(L.ratingText(0), '');
  assert.equal(L.epCode(1, 3), 'S01E03');
  const ep = item({ type: 'episode', title: 'Pilot', seriesTitle: 'Show', seasonNumber: 1, episodeNumber: 12 });
  assert.equal(L.cardTitle(ep), 'Show');
  assert.equal(L.cardSubtitle(ep), 'S01E12 · Pilot');
  assert.equal(L.remainingText(item({ runtimeMs: 90 * 60000, state: { positionMs: 0 } })), '剩余 1 小时 30 分钟');
});

test('groupSearch', () => {
  const g = L.groupSearch([item({ id: '1' }), item({ id: '2', type: 'series' }), item({ id: '3', type: 'episode' }),
    item({ id: '4', type: 'season' })]);
  assert.deepEqual(g.map((x) => x.title), ['电影', '剧集', '剧集单集']);
});

test('recent searches', () => {
  assert.deepEqual(L.pushRecent(['a', 'B', 'c'], ' b ', 3), ['b', 'a', 'c']);
  assert.deepEqual(L.pushRecent(['a'], '  ', 3), ['a']);
  assert.deepEqual(L.parseRecent('["x",1,"y"]'), ['x', 'y']);
  assert.deepEqual(L.parseRecent('{bad'), []);
});

test('grid columns, sorting, featured', () => {
  assert.equal(L.gridColumns(1000, 140, 12), 6);
  assert.equal(L.gridColumns(100, 140, 12), 2);
  const m = L.mergeSorted([[item({ id: 'a', title: 'b', rating: 5 })], [item({ id: 'b', title: 'a', rating: 9 })]],
    'CommunityRating', true);
  assert.deepEqual(m.map((x) => x.id), ['b', 'a']);
  assert.equal(L.sortLabel('Random'), '随机');
  const pool = [item({ id: '1', images: { backdrop: 'x' } }), item({ id: '2' }), item({ id: '3', type: 'episode', images: { backdrop: 'x' } })];
  assert.deepEqual(L.pickFeatured(pool, 8, 1).map((x) => x.id), ['1']);
});
