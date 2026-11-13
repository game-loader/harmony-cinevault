// TMDB v3 JSON shapes (only the fields we use). All optional because TMDB omits fields freely.

export interface TmdbGenre {
  id?: number;
  name?: string;
}

export interface TmdbSearchResult {
  id?: number;
  title?: string;
  original_title?: string;
  name?: string;
  original_name?: string;
  release_date?: string;
  first_air_date?: string;
  popularity?: number;
  vote_average?: number;
  vote_count?: number;
  overview?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  genre_ids?: number[];
  original_language?: string;
}

export interface TmdbSearchResponse {
  page?: number;
  total_results?: number;
  results?: TmdbSearchResult[];
}

export interface TmdbCast {
  name?: string;
  character?: string;
  profile_path?: string | null;
  order?: number;
}

export interface TmdbCrew {
  name?: string;
  job?: string;
  department?: string;
  profile_path?: string | null;
}

export interface TmdbCredits {
  cast?: TmdbCast[];
  crew?: TmdbCrew[];
}

export interface TmdbImage {
  file_path?: string;
  iso_639_1?: string | null;
  vote_average?: number;
  width?: number;
  height?: number;
}

export interface TmdbImages {
  logos?: TmdbImage[];
  posters?: TmdbImage[];
  backdrops?: TmdbImage[];
}

export interface TmdbReleaseDate {
  certification?: string;
  type?: number;
}

export interface TmdbReleaseCountry {
  iso_3166_1?: string;
  release_dates?: TmdbReleaseDate[];
}

export interface TmdbReleaseDates {
  results?: TmdbReleaseCountry[];
}

export interface TmdbExternalIds {
  imdb_id?: string | null;
}

export interface TmdbCompany {
  name?: string;
}

export interface TmdbSeasonSummary {
  id?: number;
  season_number?: number;
  name?: string;
  overview?: string;
  poster_path?: string | null;
  air_date?: string | null;
  episode_count?: number;
}

export interface TmdbContentRating {
  iso_3166_1?: string;
  rating?: string;
}

export interface TmdbContentRatings {
  results?: TmdbContentRating[];
}

export interface TmdbDetail {
  id?: number;
  title?: string;
  original_title?: string;
  name?: string;
  original_name?: string;
  overview?: string;
  tagline?: string;
  release_date?: string;
  first_air_date?: string;
  runtime?: number;
  episode_run_time?: number[];
  vote_average?: number;
  popularity?: number;
  genres?: TmdbGenre[];
  production_companies?: TmdbCompany[];
  networks?: TmdbCompany[];
  poster_path?: string | null;
  backdrop_path?: string | null;
  imdb_id?: string | null;
  credits?: TmdbCredits;
  images?: TmdbImages;
  release_dates?: TmdbReleaseDates;
  content_ratings?: TmdbContentRatings;
  external_ids?: TmdbExternalIds;
  seasons?: TmdbSeasonSummary[];
  number_of_seasons?: number;
  number_of_episodes?: number;
}

export interface TmdbEpisode {
  id?: number;
  name?: string;
  overview?: string;
  air_date?: string | null;
  episode_number?: number;
  season_number?: number;
  still_path?: string | null;
  vote_average?: number;
  runtime?: number | null;
  guest_stars?: TmdbCast[];
  crew?: TmdbCrew[];
}

export interface TmdbSeason {
  id?: number;
  name?: string;
  overview?: string;
  air_date?: string | null;
  season_number?: number;
  poster_path?: string | null;
  episodes?: TmdbEpisode[];
}

export interface TmdbErrorBody {
  status_message?: string;
  status_code?: number;
}
