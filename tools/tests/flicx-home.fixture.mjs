// Hand-written markup with the same structure as the fli.cx home page rails (2026-11-25).
const card = ({ tt, kind = 'movie', slug, label, genre = 'Action', year = '2026', score, still }) =>
  '<div role="listitem"><div class="card" style="--tone:#5d341e"><div class="card-art card-poster">' +
  '<span class="card-pic"><img data-fade="true" src="https://s.fli.cx/a/poster/medium/' + tt + '/img" ' +
  'srcSet="https://s.fli.cx/a/poster/small/' + tt + '/img 300w" alt="" width="500" height="750"/></span>' +
  '<span class="card-over"><span class="card-over-cap"><span class="card-over-title" aria-hidden="true">x</span>' +
  '<span class="card-over-meta"><a tabindex="-1" class="card-over-genre" href="/genres/a">' + genre + '</a>' +
  '<span class="card-over-year">' + year + '</span>' +
  (score ? '<span class="card-over-score" aria-label="Rated ' + score + ' out of 10">' + score + '</span>' : '') +
  '</span></span></span><a class="card-link" data-film="' + slug + '"' +
  (kind === 'tv' ? ' data-kind="show"' : '') +
  (still ? ' data-still="' + still + '"' : '') +
  ' aria-label="' + label + '" href="/' + kind + '/' + slug + '"></a></div></div></div>';

const rail = (label, cards) =>
  '<section class="section"><header><h2>' + label + '</h2></header><div class="shell"><div class="rail">' +
  '<div role="list" aria-label="' + label + '" class="rail-track">' + cards.join('') + '</div></div></div></section>';

export const homeHtml = '<html><body><section><div class="hero"><a href="/movie/hero-2026">Hero</a></div></section>' +
  rail('Trending this week', [
    card({ tt: 'tt0133093', slug: 'the-matrix-1999', label: 'The Matrix (1999)', year: '1999', score: '8.2',
      still: 'https://s.fli.cx/t/original/matrix.jpg' }),
    card({ tt: 'tt1375666', slug: 'inception-2010', label: 'Minions &amp; Monsters (2026)', genre: 'Comedy' }),
    card({ tt: 'tt0133093', slug: 'the-matrix-1999', label: 'The Matrix (1999)' }),
    '<div role="listitem"><div class="card"><a class="card-link" href="/movie/no-poster"></a></div></div>',
    card({ tt: 'tt0000001', slug: 'person', label: 'Someone', kind: 'person' })
  ]) +
  rail('Trending TV this week', [
    card({ tt: 'tt18347622', kind: 'tv', slug: 'bodies-2023', label: 'Bodies (2023)', genre: 'Crime',
      year: '2023', score: '7.1' })
  ]) +
  rail('Browse by genre', []) +
  rail('Released on November 25', [
    card({ tt: 'tt0103639', slug: 'aladdin-1992', label: 'Aladdin (1992)', year: '1992', genre: 'Animation' })
  ]) +
  rail('Top Comedy', [card({ tt: 'tt0107048', slug: 'groundhog-day-1993', label: 'Groundhog Day (1993)' })]) +
  rail('Midnight picks', [card({ tt: 'tt0110912', slug: 'pulp-fiction-1994', label: 'Pulp Fiction (1994)' })]) +
  '</body></html>';
