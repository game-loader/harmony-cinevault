import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { FlicxLibraryState, toItem } = require(path.join(process.env.CV_OUT, 'flicx/FlicxLibrary.js'));
const { MediaItem } = require(path.join(process.env.CV_OUT, 'common/Models.js'));

const item = (id, type, extra = {}) => Object.assign(new MediaItem(), { id, type, sourceId: 'flicx', title: id }, extra);

test('favourites survive a save/load round trip, newest first, and re-apply onto fresh items', () => {
  const lib = new FlicxLibraryState();
  const odyssey = item('flicx-movie-tt33764258', 'movie', { year: 2026, imdbId: 'tt33764258' });
  odyssey.images.poster = 'https://s.fli.cx/a/poster/medium/tt33764258/img';
  lib.setFavorite(odyssey, 'the-odyssey-2026', true, 100);
  lib.setFavorite(item('flicx-tv-tt18347622', 'series'), 'bodies-2023', true, 200);
  const copy = new FlicxLibraryState();
  copy.load(JSON.parse(JSON.stringify(lib.dump())));
  assert.deepEqual(copy.favorites().map(s => s.id), ['flicx-tv-tt18347622', 'flicx-movie-tt33764258']);
  const back = toItem(copy.get('flicx-movie-tt33764258'), 'flicx');
  assert.deepEqual([back.type, back.year, back.images.poster, back.state.favorite], ['movie', 2026, odyssey.images.poster, true]);
  assert.equal(copy.get('flicx-tv-tt18347622').slug, 'bodies-2023');
  const fresh = copy.apply(item('flicx-movie-tt33764258', 'movie'));
  assert.equal(fresh.state.favorite, true);
  copy.setFavorite(fresh, '', false, 300);
  assert.deepEqual(copy.favorites().map(s => s.id), ['flicx-tv-tt18347622']);
  assert.equal(copy.get('flicx-movie-tt33764258').slug, 'the-odyssey-2026');
});

test('progress: resume list is one entry per series, near-end counts as watched, short starts are ignored', () => {
  const lib = new FlicxLibraryState();
  const ep = n => item('flicx-tv-tt18347622-s1e' + n, 'episode', { seriesId: 'flicx-tv-tt18347622', episodeNumber: n });
  lib.setProgress(ep(1), '', 20 * 60000, 55 * 60000, 10);
  lib.setProgress(ep(2), '', 5 * 60000, 55 * 60000, 20);
  lib.setProgress(item('flicx-movie-tt1', 'movie'), '', 10000, 0, 30);
  assert.deepEqual(lib.resume().map(s => s.id), ['flicx-tv-tt18347622-s1e2']);
  lib.setProgress(ep(2), '', 54 * 60000, 55 * 60000, 40);
  assert.equal(lib.get('flicx-tv-tt18347622-s1e2').played, true);
  assert.deepEqual(lib.resume().map(s => s.id), ['flicx-tv-tt18347622-s1e1']);
  lib.setPlayed(item('flicx-tv-tt18347622', 'series'), '', true, 50);
  assert.equal(lib.get('flicx-tv-tt18347622-s1e1').played, true);
  assert.deepEqual(lib.resume(), []);
});

test('corrupt or foreign stored data is ignored', () => {
  const lib = new FlicxLibraryState();
  lib.load({ items: [null, { id: 'emby-1', favorite: true }, { id: 'flicx-movie-tt2', favorite: 'yes', year: '1999', positionMs: 5 }] });
  assert.deepEqual(lib.favorites(), []);
  assert.equal(lib.get('flicx-movie-tt2').year, 0);
  lib.load(undefined);
  assert.equal(lib.get('flicx-movie-tt2'), undefined);
});
