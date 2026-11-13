import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const N = require(path.join(process.env.CV_OUT, 'scraper/NameParser.js'));

function check(input, exp) {
  test('parse ' + input, () => {
    const p = N.parseName(input);
    for (const k of Object.keys(exp)) {
      assert.deepEqual(p[k], exp[k], `${input}: ${k} = ${JSON.stringify(p[k])}, want ${JSON.stringify(exp[k])}`);
    }
  });
}

check('The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv', { title: 'The Matrix', year: 1999, isTv: false, season: -1, episode: -1 });
check('权力的游戏.S01E02.mkv', { title: '权力的游戏', season: 1, episode: 2, isTv: true });
check('[字幕组] 进击的巨人 第二季 第05话 [1080P].mp4', { title: '进击的巨人', season: 2, episode: 5, isTv: true });
check('Breaking Bad/Season 2/Breaking.Bad.S02E03.720p.mkv', { title: 'Breaking Bad', season: 2, episode: 3 });
check('Breaking Bad/Season 2/E03.mkv', { title: 'Breaking Bad', season: 2, episode: 3, isTv: true });
check('Breaking Bad (2008)/Season 2/E03.mkv', { title: 'Breaking Bad', season: 2, episode: 3, year: 2008 });
check('三体/第3集.mp4', { title: '三体', season: 1, episode: 3, isTv: true });
check('三体/03.mp4', { title: '三体', season: 1, episode: 3, isTv: true });
check('电视剧/漫长的季节/第二季/第十二集.mp4', { title: '漫长的季节', season: 2, episode: 12 });
check('流浪地球2 (2023).mp4', { title: '流浪地球2', year: 2023, isTv: false });
check('Friends.S01E01-E02.1080p.mkv', { title: 'Friends', season: 1, episode: 1, episodeEnd: 2 });
check('Friends.S01E01E02.mkv', { title: 'Friends', season: 1, episode: 1, episodeEnd: 2 });
check('狂飙 EP05 4K.mp4', { title: '狂飙', episode: 5, season: 1, isTv: true });
check('Lost.EP05.mkv', { title: 'Lost', episode: 5, isTv: true });
check('甄嬛传 第1季 第10集.mkv', { title: '甄嬛传', season: 1, episode: 10 });
check('庆余年 第十二集.mp4', { title: '庆余年', episode: 12, isTv: true });
check('[2019] 寄生虫.mkv', { title: '寄生虫', year: 2019 });
check('寄生虫 [2019].mkv', { title: '寄生虫', year: 2019 });
check('Inception (2010) [1080p] [BluRay].mkv', { title: 'Inception', year: 2010 });
check('Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX.mkv', { title: 'Dune Part Two', year: 2024 });
check('Blade.Runner.2049.2017.1080p.mkv', { title: 'Blade Runner 2049', year: 2017 });
check('2012.2009.BluRay.mkv', { title: '2012', year: 2009 });
check('1917.mkv', { title: '1917', year: 0, isTv: false });
check('The.Office.US.S05E10.HDTV.x264.mkv', { title: 'The Office US', season: 5, episode: 10 });
check('the.mandalorian.s02e08.web.h264.mkv', { title: 'the mandalorian', season: 2, episode: 8 });
check('流浪地球2.The.Wandering.Earth.II.2023.2160p.WEB-DL.H265.mkv', { title: '流浪地球2', altTitle: 'The Wandering Earth II', year: 2023 });
check('肖申克的救赎 The Shawshank Redemption (1994) 中英字幕.mp4', { title: '肖申克的救赎', altTitle: 'The Shawshank Redemption', year: 1994 });
check('[Nekomoe kissaten] Frieren - 05 [1080p].mkv', { title: 'Frieren', episode: 5, isTv: true });
check('[SweetSub][葬送的芙莉莲][Sousou no Frieren][12][1080P].mp4', { episode: 12, isTv: true, title: '葬送的芙莉莲' });
check('Movies/Interstellar.2014.IMAX.1080p.mkv', { title: 'Interstellar', year: 2014 });
check('The.Matrix.1999.sample.mkv', { excluded: true });
check('Avatar.2009.Trailer.mp4', { excluded: true });
check('阿凡达 预告片.mp4', { excluded: true });
check('Show/Samples/clip.mkv', { excluded: true });
check('The.Matrix.1999.1080p.mkv', { excluded: false });
check('Sherlock.3x02.mkv', { title: 'Sherlock', season: 3, episode: 2 });
check('Game of Thrones/S03/Game.of.Thrones.S03E09.mkv', { title: 'Game of Thrones', season: 3, episode: 9 });
check('Game of Thrones/S03/09.mkv', { title: 'Game of Thrones', season: 3, episode: 9 });
check('黑暗荣耀 第二季/黑暗荣耀.E03.mp4', { title: '黑暗荣耀', season: 2, episode: 3 });
check('Westworld Season 1/Episode 4.mkv', { title: 'Westworld', season: 1, episode: 4 });
check('【高清影视之家发布 www.HDBTHD.com】奥本海默[中英字幕].Oppenheimer.2023.BluRay.1080p.mkv', { title: '奥本海默', year: 2023 });

test('chineseToNumber', () => {
  assert.equal(N.chineseToNumber('十二'), 12);
  assert.equal(N.chineseToNumber('二十'), 20);
  assert.equal(N.chineseToNumber('二十三'), 23);
  assert.equal(N.chineseToNumber('一百零五'), 105);
  assert.equal(N.chineseToNumber('两'), 2);
  assert.equal(N.chineseToNumber('7'), 7);
  assert.equal(N.chineseToNumber('abc'), -1);
});

test('file kinds', () => {
  assert.ok(N.isVideoFile('a.MKV'));
  assert.ok(!N.isVideoFile('a.srt'));
  assert.ok(N.isSubtitleFile('a.chs.ass'));
});

test('titleSimilarity', () => {
  assert.equal(N.titleSimilarity('The Matrix', 'Matrix'), 1);
  assert.ok(N.titleSimilarity('权力的游戏', '权力的游戏 第一季') > 0.6);
  assert.ok(N.titleSimilarity('Inception', 'Interstellar') < 0.5);
});

test('displayName', () => {
  assert.equal(N.displayName(N.parseName('Lost.S01E05.mkv')), 'Lost S01E05');
  assert.equal(N.displayName(N.parseName('Inception.2010.mkv')), 'Inception (2010)');
});
