import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const M = require(path.join(process.env.CV_OUT, 'providers/EmbyMapper.js'));
const D = require(path.join(process.env.CV_OUT, 'providers/DeviceProfile.js'));
const Models = require(path.join(process.env.CV_OUT, 'common/Models.js'));

const ctx = M.makeContext('src1', 'http://nas:8096', 'TOK', 'u1', 'dev1');

const movie = {
  Id: 'm1', Name: '盗梦空间', OriginalTitle: 'Inception', Type: 'Movie', Overview: '梦中梦', ProductionYear: 2010,
  PremiereDate: '2010-07-16T00:00:00.0000000Z', CommunityRating: 8.36, OfficialRating: 'PG-13',
  RunTimeTicks: 88800000000, Genres: ['科幻', '动作'], Studios: [{ Name: 'Warner Bros.', Id: 's' }],
  People: [{ Name: 'Leonardo DiCaprio', Id: 'p1', Role: 'Cobb', Type: 'Actor', PrimaryImageTag: 'pt' },
    { Name: 'Christopher Nolan', Id: 'p2', Type: 'Director' }],
  ProviderIds: { Tmdb: '27205', Imdb: 'tt1375666' },
  ImageTags: { Primary: 'ptag', Logo: 'ltag' }, BackdropImageTags: ['btag'],
  UserData: { Played: false, IsFavorite: true, PlaybackPositionTicks: 600000000, PlayCount: 2,
    LastPlayedDate: '2026-01-02T03:04:05.000Z' },
  MediaStreams: [{ Type: 'Video', Width: 1920, Height: 800, Index: 0 }], Container: 'mkv'
};

const series = {
  Id: 's1', Name: '绝命毒师', Type: 'Series', IsFolder: true, ProductionYear: 2008, ChildCount: 5,
  ImageTags: { Primary: 'sp', Thumb: 'st' }, BackdropImageTags: ['sb'], ProviderIds: { tmdb: '1396' },
  UserData: { Played: false, UnplayedItemCount: 62 }
};

const episode = {
  Id: 'e1', Name: '试播集', Type: 'Episode', SeriesId: 's1', SeriesName: '绝命毒师', SeasonId: 'se1',
  ParentIndexNumber: 1, IndexNumber: 1, RunTimeTicks: 34800000000, ImageTags: { Primary: 'ep' },
  BackdropImageTags: [], ParentBackdropItemId: 's1', ParentBackdropImageTags: ['sb'],
  ParentLogoItemId: 's1', ParentLogoImageTag: 'sl', ParentThumbItemId: 's1', ParentThumbImageTag: 'st',
  SeriesPrimaryImageTag: 'sp', UserData: { Played: true, PlaybackPositionTicks: 0 }
};

test('emby: movie mapping', () => {
  const m = M.mapItem(ctx, movie);
  assert.equal(m.sourceId, 'src1');
  assert.equal(m.type, 'movie');
  assert.equal(m.title, '盗梦空间');
  assert.equal(m.originalTitle, 'Inception');
  assert.equal(m.year, 2010);
  assert.equal(m.rating, 8.4);
  assert.equal(m.runtimeMs, 8880000);
  assert.deepEqual(m.studios, ['Warner Bros.']);
  assert.equal(m.people[0].role, 'Cobb');
  assert.equal(m.people[1].role, '导演');
  assert.match(m.people[0].image, /\/Items\/p1\/Images\/Primary\?maxWidth=300&quality=90&tag=pt$/);
  assert.equal(m.people[1].image, '');
  assert.equal(m.tmdbId, '27205');
  assert.equal(m.imdbId, 'tt1375666');
  assert.equal(m.width, 1920);
  assert.equal(m.state.favorite, true);
  assert.equal(m.state.positionMs, 60000);
  assert.equal(m.state.playCount, 2);
  assert.equal(m.state.lastPlayed, Date.parse('2026-01-02T03:04:05.000Z'));
  assert.equal(m.images.poster, 'http://nas:8096/Items/m1/Images/Primary?maxWidth=400&quality=90&tag=ptag');
  assert.equal(m.images.backdrop, 'http://nas:8096/Items/m1/Images/Backdrop/0?maxWidth=1280&quality=90&tag=btag');
  assert.match(m.images.logo, /Images\/Logo\?maxWidth=500/);
  assert.match(m.images.thumb, /Backdrop\/0\?maxWidth=640/);
});

test('emby: series + episode mapping with image fallbacks', () => {
  const s = M.mapItem(ctx, series);
  assert.equal(s.type, 'series');
  assert.equal(s.childCount, 5);
  assert.equal(s.tmdbId, '1396');
  assert.match(s.images.thumb, /Items\/s1\/Images\/Thumb/);
  const e = M.mapItem(ctx, episode);
  assert.equal(e.type, 'episode');
  assert.equal(e.seasonNumber, 1);
  assert.equal(e.episodeNumber, 1);
  assert.equal(e.seriesId, 's1');
  assert.equal(e.seriesTitle, '绝命毒师');
  assert.equal(e.state.played, true);
  assert.match(e.images.poster, /Items\/s1\/Images\/Primary\?maxWidth=400.*tag=sp/);
  assert.match(e.images.thumb, /Items\/e1\/Images\/Primary\?maxWidth=640.*tag=ep/);
  assert.match(e.images.backdrop, /Items\/s1\/Images\/Backdrop\/0.*tag=sb/);
  assert.match(e.images.logo, /Items\/s1\/Images\/Logo.*tag=sl/);
  const season = M.mapItem(ctx, { Id: 'se1', Type: 'Season', IndexNumber: 2, SeriesId: 's1', SeriesPrimaryImageTag: 'sp' });
  assert.equal(season.seasonNumber, 2);
  assert.match(season.images.poster, /Items\/s1\/Images\/Primary/);
});

test('emby: types, views, urls, auth', () => {
  assert.equal(M.mapType({ Type: 'BoxSet' }), 'collection');
  assert.equal(M.mapType({ Type: 'CollectionFolder' }), 'folder');
  assert.equal(M.mapType({ Type: 'Video' }), 'video');
  assert.equal(M.mapType({ Type: 'Weird', IsFolder: true }), 'folder');
  const v = M.mapView(ctx, { Id: 'v1', Name: '电影', CollectionType: 'movies', ImageTags: { Primary: 'x' } });
  assert.equal(M.isVideoView(v), true);
  assert.equal(M.isVideoView(M.mapView(ctx, { Id: 'v2', CollectionType: 'music' })), false);
  assert.equal(M.normaliseUrl('nas.local:8096/'), 'http://nas.local:8096');
  assert.equal(M.normaliseUrl('https://a.b/web/index.html#!/home'), 'https://a.b');
  assert.deepEqual(M.candidateBaseUrls('a:8096'), ['http://a:8096', 'http://a:8096/emby']);
  assert.deepEqual(M.candidateBaseUrls('http://a/emby/'), ['http://a/emby', 'http://a']);
  assert.equal(M.detectKind({ ProductName: 'Jellyfin Server' }), 'jellyfin');
  assert.equal(M.detectKind({ ProductName: 'Emby Server' }), 'emby');
  const h = M.authHeaders('dev1', 'TOK');
  assert.equal(h['X-Emby-Token'], 'TOK');
  assert.equal(h['Authorization'], h['X-Emby-Authorization']);
  assert.match(h['Authorization'], /^MediaBrowser Client="CineVault", Device="HarmonyOS", DeviceId="dev1", Version="1.0.0", Token="TOK"$/);
  assert.equal(M.authHeaders('d', '')['X-Emby-Token'], undefined);
  assert.equal(M.resizeImageUrl('x?maxWidth=400&q', 200), 'x?maxWidth=200&q');
});

test('emby: items query', () => {
  const q = new Models.QueryOptions();
  q.parentId = 'v1'; q.types = ['movie', 'series']; q.sortBy = 'DateCreated'; q.sortDesc = true;
  q.startIndex = 60; q.limit = 30; q.searchTerm = '星际'; q.genres = ['科幻', '剧情']; q.years = [2014, 2015];
  q.favoritesOnly = true; q.unplayedOnly = true;
  const p = M.buildItemsQuery(q);
  assert.equal(p.ParentId, 'v1');
  assert.equal(p.IncludeItemTypes, 'Movie,Series');
  assert.equal(p.SortBy, 'DateCreated,SortName');
  assert.equal(p.SortOrder, 'Descending');
  assert.equal(p.StartIndex, '60');
  assert.equal(p.Limit, '30');
  assert.equal(p.SearchTerm, '星际');
  assert.equal(p.Genres, '科幻|剧情');
  assert.equal(p.Years, '2014,2015');
  assert.equal(p.Filters, 'IsFavorite,IsUnplayed');
  assert.equal(p.Recursive, 'true');
  assert.ok(p.Fields.includes('ProviderIds'));
});

const streams = [
  { Index: 0, Type: 'Video', Codec: 'hevc' },
  { Index: 1, Type: 'Audio', Codec: 'aac', Language: 'chi', Channels: 6, IsDefault: true },
  { Index: 2, Type: 'Audio', Codec: 'truehd', Language: 'eng', DisplayTitle: 'English TrueHD 7.1' },
  { Index: 3, Type: 'Subtitle', Codec: 'subrip', Language: 'chi', IsTextSubtitleStream: true, IsDefault: true },
  { Index: 4, Type: 'Subtitle', Codec: 'PGSSUB', Language: 'eng', IsTextSubtitleStream: false },
  { Index: 5, Type: 'Subtitle', Codec: 'ass', IsExternal: true, IsTextSubtitleStream: true, IsForced: true }
];

test('emby: playback direct stream', () => {
  const res = { PlaySessionId: 'ps1', MediaSources: [{ Id: 'ms1', Container: 'mkv,webm', RunTimeTicks: 72000000000,
    SupportsDirectPlay: true, SupportsDirectStream: true, MediaStreams: streams }] };
  const info = M.mapPlayback(ctx, 'm1', res, '', 0);
  assert.equal(info.isTranscode, false);
  assert.equal(info.container, 'mkv');
  assert.equal(info.url, 'http://nas:8096/Videos/m1/stream.mkv?Static=true&MediaSourceId=ms1&DeviceId=dev1&PlaySessionId=ps1&api_key=TOK');
  assert.equal(info.durationMs, 7200000);
  assert.equal(info.playSessionId, 'ps1');
  assert.equal(info.audioTracks.length, 2);
  assert.equal(info.audioTracks[0].title, '中文 AAC');
  assert.equal(info.audioTracks[1].title, 'English TrueHD 7.1');
  assert.equal(info.subtitles.length, 3);
  assert.equal(info.subtitles[0].url, 'http://nas:8096/Videos/m1/ms1/Subtitles/3/Stream.srt?api_key=TOK');
  assert.equal(info.subtitles[0].isDefault, true);
  assert.equal(info.subtitles[1].url, '');
  assert.equal(info.subtitles[1].isExternal, false);
  assert.match(info.subtitles[2].title, /强制/);
});

test('emby: playback transcode + errors', () => {
  const res = { PlaySessionId: 'ps2', MediaSources: [{ Id: 'ms2', SupportsDirectPlay: false, SupportsDirectStream: false,
    TranscodingUrl: '/videos/m1/master.m3u8?DeviceId=dev1&MediaSourceId=ms2', TranscodingSubProtocol: 'hls' }] };
  const info = M.mapPlayback(ctx, 'm1', res, '', 5000);
  assert.equal(info.isTranscode, true);
  assert.equal(info.container, 'hls');
  assert.equal(info.url, 'http://nas:8096/videos/m1/master.m3u8?DeviceId=dev1&MediaSourceId=ms2&api_key=TOK');
  assert.equal(info.durationMs, 5000);
  assert.throws(() => M.mapPlayback(ctx, 'm1', { ErrorCode: 'NotAllowed' }, '', 0), /不允许/);
  assert.throws(() => M.mapPlayback(ctx, 'm1', { MediaSources: [] }, '', 0), /媒体源/);
  const r = new Models.PlaybackRequest();
  r.startMs = 1500; r.audioIndex = 2; r.subtitleIndex = -1;
  const b = M.buildPlaybackBody('u1', r, 1000, '');
  assert.equal(b.StartTimeTicks, 15000000);
  assert.equal(b.AudioStreamIndex, 2);
  assert.equal(b.SubtitleStreamIndex, undefined);
  const rep = M.buildReport('m1', info, 2000, true);
  assert.equal(rep.PositionTicks, 20000000);
  assert.equal(rep.PlayMethod, 'Transcode');
  assert.equal(rep.IsPaused, true);
});

test('emby: device profile', () => {
  const p = D.buildDeviceProfile(0);
  assert.equal(p.MaxStreamingBitrate, 200000000);
  assert.equal(D.buildDeviceProfile(8000000).MaxStreamingBitrate, 8000000);
  const containers = p.DirectPlayProfiles.filter((x) => x.Type === 'Video').map((x) => x.Container);
  for (const c of ['mp4', 'mkv', 'ts', 'webm', 'hls']) assert.ok(containers.includes(c), c);
  assert.ok(!p.DirectPlayProfiles[0].VideoCodec.includes('av1'));
  assert.ok(!p.DirectPlayProfiles[0].AudioCodec.includes('ac3'));
  const t = p.TranscodingProfiles[0];
  assert.deepEqual([t.Container, t.VideoCodec, t.AudioCodec, t.Protocol], ['ts', 'h264', 'aac', 'hls']);
  assert.ok(p.SubtitleProfiles.some((s) => s.Format === 'srt' && s.Method === 'External'));
  assert.ok(p.SubtitleProfiles.some((s) => s.Format === 'ass' && s.Method === 'External'));
});
