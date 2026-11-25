import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
import { homeHtml } from './flicx-home.fixture.mjs';

const require = createRequire(import.meta.url);
const { FlicxHome, rowTitle, decodeEntities } = require(path.join(process.env.CV_OUT, 'flicx/FlicxHome.js'));

test('home rails keep page order, Chinese titles, and only cards with an IMDb poster and a film/show link', () => {
  const rows = FlicxHome.parse(homeHtml);
  assert.deepEqual(rows.map(r => r.title), ['本周热门电影', '本周热门剧集', '历史上的今天', '高分喜剧', 'Midnight picks']);
  assert.deepEqual(rows.map(r => r.style), ['poster', 'poster', 'poster', 'poster', 'poster']);
  assert.equal(new Set(rows.map(r => r.key)).size, rows.length);
  const [matrix, minions] = rows[0].items;
  assert.equal(rows[0].items.length, 2);
  assert.deepEqual([matrix.id, matrix.type, matrix.sourceId, matrix.imdbId, matrix.slug],
    ['flicx-movie-tt0133093', 'movie', 'flicx', 'tt0133093', 'the-matrix-1999']);
  assert.deepEqual([matrix.title, matrix.year, matrix.rating, matrix.genres], ['The Matrix', 1999, 8.2, ['Action']]);
  assert.equal(matrix.images.poster, 'https://s.fli.cx/a/poster/medium/tt0133093/img');
  assert.equal(matrix.images.backdrop, 'https://s.fli.cx/t/original/matrix.jpg');
  assert.deepEqual([minions.title, minions.rating, minions.images.backdrop, minions.genres], ['Minions & Monsters', 0, '', ['Comedy']]);
  const bodies = rows[1].items[0];
  assert.deepEqual([bodies.id, bodies.type, bodies.slug, bodies.year], ['flicx-tv-tt18347622', 'series', 'bodies-2023', 2023]);
});

test('unrecognised or empty pages give no rows instead of throwing', () => {
  assert.deepEqual(FlicxHome.parse(''), []);
  assert.deepEqual(FlicxHome.parse('<html>Just a moment...</html>'), []);
  assert.deepEqual(FlicxHome.parse(undefined), []);
  assert.equal(rowTitle(' In 4K '), '4K 专区');
  assert.equal(rowTitle('Top Drama'), '高分剧情片');
  assert.equal(decodeEntities('A &amp; B &#39;C&#x27; &bogus;'), "A & B 'C' &bogus;");
});

test('title page cast/crew rails give photos, translated key-crew roles first, then cast', () => {
  const { parseTitlePage } = require(path.join(process.env.CV_OUT, 'flicx/FlicxHome.js'));
  const person = (name, role, img) => '<div role="listitem"><a class="person" aria-label="' + name + ', ' + role +
    '" href="/person/1"><div class="person-photo">' +
    (img ? '<span class="person-pic"><img data-fade="true" src="' + img + '" alt=""/></span>' :
      '<span class="person-initial">' + name[0] + '</span>') +
    '</div><div class="person-name">' + name + '</div><div class="person-role">' + role + '</div></a></div>';
  const html = '<script type="application/ld+json">{"@type":"Movie","description":"x"}</script>' +
    '<section><div role="list" aria-label="Cast">' + person('Matt Damon', 'Odysseus', 'https://s.fli.cx/t/w185/a.jpg') +
    person('Tom Holland', 'Telemachus', '/t/w185/b.jpg') + '</div></section>' +
    '<section><div role="list" aria-label="Crew">' + person('Christopher Nolan', 'Director · Writer · Producer', '/t/w185/c.jpg') +
    person('Emma Thomas', 'Producer', '/t/w185/d.jpg') + person('Callum Armstrong', 'Music', '') + '</div></section>';
  const page = parseTitlePage(html);
  assert.deepEqual(page.people.map(p => [p.name, p.role, p.image]), [
    ['Christopher Nolan', '导演 / 编剧 / 制片', 'https://fli.cx/t/w185/c.jpg'],
    ['Matt Damon', 'Odysseus', 'https://s.fli.cx/t/w185/a.jpg'],
    ['Tom Holland', 'Telemachus', 'https://fli.cx/t/w185/b.jpg']]);
});
