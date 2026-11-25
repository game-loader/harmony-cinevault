import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const out = process.env.CV_OUT;
const file = name => path.join(out, name + '.js');
const requests = [];
let respond;
const settings = { tmdbApiKey: 'test-key', tmdbApiBase: 'https://tmdb.test/3', tmdbLanguage: 'zh-CN',
  tmdbImageBase: 'https://image.test/t/p/' };
class HttpError extends Error {
  constructor(status) { super('HTTP ' + status); this.status = status; this.body = ''; }
}
// Replace only the Harmony network and preferences boundary in this process.
const stub = (name, exports) => { const id = file(name); require.cache[id] = { id, filename: id, loaded: true, exports }; };
stub('common/Settings', { Settings: { get: () => ({ ...settings }) } });
stub('common/Http', {
  HttpError, buildQuery: p => new URLSearchParams(p).toString(),
  request: async (method, url, headers) => {
    const u = new URL(url);
    assert.equal(method, 'GET');
    requests.push(u);
    if (u.host === 'fli.cx') {
      assert.equal(u.searchParams.has('api_key'), false);
      assert.equal(headers.Authorization, undefined);
    }
    const data = await respond(u);
    return { status: 200, body: JSON.stringify(data) };
  }
});
const { FlicxApi: api } = require(file('flicx/FlicxApi'));
const { TmdbClient: tmdb } = require(file('scraper/TmdbClient'));
const id = 'tt18347622';
const rows = [{ name: 'Main', kind: 'hls', group: 'dedicated', has: true, src: '/api/s/episode.m3u8' }];

test('Flicx sources/subtitles preserve the distinct movie and episode routes, including season zero', async () => {
  requests.length = 0;
  respond = u => u.pathname.includes('subtitles') ? { tracks: [] } : { sources: rows };
  assert.equal((await api.sources(id, -1, -1))[0].url, 'https://fli.cx/api/s/episode.m3u8');
  await api.sources(id, 0, 2);
  await api.subtitles(id, 0, 2);
  await api.subtitles(id, -1, -1);
  assert.deepEqual(requests.map(u => u.pathname + u.search), ['/api/sources/' + id,
    '/api/sources/' + id + '?s=0&e=2', '/api/subtitles/' + id + '/0/2', '/api/subtitles/' + id]);
  await assert.rejects(() => api.sources('anilist-114123', 1, 1));
  await assert.rejects(() => api.sources(id, 1, -1));
  assert.equal(requests.length, 4);
});

test('IMDb lookup selects the requested TMDB title type in the configured language', async () => {
  tmdb.clearCache();
  respond = u => {
    assert.equal(u.pathname, '/3/find/' + id);
    assert.equal(u.searchParams.get('external_source'), 'imdb_id');
    assert.equal(u.searchParams.get('language'), 'zh-CN');
    return { movie_results: [], tv_results: [{ id: 333, name: '尸体' }], tv_episode_results: [{ id: 2 }] };
  };
  assert.equal((await tmdb.findByImdbId(id, 'tv')).id, 333);
  assert.equal(await tmdb.findByImdbId(id, 'movie'), undefined);
});

test('bad source responses report an error, while a missing listing is ordinary unavailability', async () => {
  respond = () => { throw new HttpError(404); };
  assert.equal(await api.hasPlayableSource(id, 1, 1), false);
  respond = () => ({ error: 'changed contract' });
  await assert.rejects(() => api.sources(id, 1, 1), /Flicx/);
  respond = () => { throw new HttpError(403); };
  await assert.rejects(() => api.sources(id, 1, 1), /403/);
});

test('中文片名 → IMDb → available series → season/episode → fresh HLS and Chinese subtitle', async () => {
  const { FlicxProvider } = require(file('flicx/FlicxProvider'));
  tmdb.clearCache();
  requests.length = 0;
  const tmdbId = 333;
  let playCount = 0;
  let loseSubs = false;
  respond = u => {
    switch (u.pathname) {
      case '/3/search/movie': return { results: [{ id: 111, title: '同名电影' }] };
      case '/3/search/tv':
        assert.equal(u.searchParams.get('query'), '尸体');
        return { results: [{ id: tmdbId, name: '尸体' }, { id: 444, name: '无编号' }] };
      case '/3/movie/111/external_ids': return { imdb_id: 'tt9000000' };
      case '/3/tv/333/external_ids': return { imdb_id: id };
      case '/3/tv/444/external_ids': return { imdb_id: null };
      case '/api/sources/tt9000000': return { sources: [] };
      case '/api/sources/' + id:
        assert.equal(u.searchParams.get('s'), '1');
        if (u.searchParams.get('e') === '1') return { sources: rows };
        assert.equal(u.searchParams.get('e'), '4');
        return { sources: [{ ...rows[0], src: '/api/s/fresh-' + (++playCount) + '.m3u8' }] };
      case '/3/tv/333': return { id: tmdbId, name: '尸体', external_ids: { imdb_id: id },
        seasons: [{ season_number: 0, name: '特别篇' }, { season_number: 1, name: '第一季' }] };
      case '/3/tv/333/season/1': return { season_number: 1, episodes: [
        { episode_number: 1, name: '已撤下的集' }, { episode_number: 4, name: '第四集' }] };
      case '/api/tv/season':
        assert.equal(u.searchParams.get('show'), id);
        return { episodes: [{ n: 1, plays: false }, { n: 4, plays: true }] };
      case '/3/find/' + id: return { tv_results: [{ id: tmdbId }] };
      case '/api/subtitles/' + id + '/1/4':
        if (loseSubs) throw new HttpError(503);
        return { tracks: [{ language: 'zh', format: 'vtt', src: '/api/subtitles/file/chinese' }] };
      default: throw new Error('Unexpected route ' + u.pathname);
    }
  };
  const provider = new FlicxProvider();
  const results = await provider.search('尸体', 20);
  assert.deepEqual(results.map(m => [m.id, m.title]), [['flicx-tv-' + id, '尸体']]);
  const root = results[0].id;
  const series = await provider.getItem(root);
  assert.deepEqual([series.id, series.imdbId, series.type], [root, id, 'series']);
  const seasons = await provider.getSeasons(root);
  assert.deepEqual(seasons.map(s => s.id), [root + '-s0', root + '-s1']);
  const eps = await provider.getEpisodes(root, root + '-s1');
  assert.deepEqual(eps.map(e => [e.id, e.seriesId, e.seasonId, e.imdbId]),
    [[root + '-s1e4', root, root + '-s1', id]]);
  // Navigation passes a string ID only and must survive re-creation of the provider.
  const episode = await new FlicxProvider().getItem(eps[0].id);
  assert.equal(episode.title, '第四集');
  const play = await provider.getPlayback(episode, {});
  assert.deepEqual([play.url, play.subtitles[0].language], ['https://fli.cx/api/s/fresh-1.m3u8', 'zh']);
  loseSubs = true;
  const retry = await provider.getPlayback(episode, {});
  assert.equal(retry.url, 'https://fli.cx/api/s/fresh-2.m3u8');
  assert.deepEqual(retry.subtitles, []);
  assert.ok(!requests.some(u => u.pathname === '/api/search'));
});

test('English movie lookup needs no TMDB credentials to search or play an exact Flicx hit', async () => {
  const { FlicxProvider } = require(file('flicx/FlicxProvider'));
  const key = settings.tmdbApiKey;
  try {
    settings.tmdbApiKey = '';
    respond = u => {
      assert.equal(u.hostname, 'fli.cx');
      if (u.pathname === '/api/search') {
        assert.equal(u.searchParams.get('q'), 'A & B');
        return { results: [{ id: 'tt1375666', title: 'A & B' }] };
      }
      assert.equal(u.search, '');
      if (u.pathname === '/api/sources/tt1375666') return { sources: rows };
      if (u.pathname === '/api/subtitles/tt1375666') return { tracks: [] };
      throw new Error('Unexpected route');
    };
    const provider = new FlicxProvider();
    const [movie] = await provider.search('A & B', 5);
    const detail = await provider.getItem(movie.id);
    assert.equal(detail.title, 'A & B');
    assert.equal((await provider.getPlayback(detail, {})).url, 'https://fli.cx/api/s/episode.m3u8');
    await assert.rejects(() => provider.search('中文', 5), /TMDB/);
  } finally {
    settings.tmdbApiKey = key;
  }
});
