# Flicx Native Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Flicx as a built-in native media source so CineVault can search Chinese titles and play Flicx HLS sources with external subtitles.

**Architecture:** Add a focused Flicx API/mapper/provider layer behind the existing `MediaProvider` contract. English queries use Flicx search; CJK queries use the configured TMDB locale and verify availability through Flicx source lookup by IMDb ID. Reuse TMDB for details and episode metadata, and reuse the current native AVPlayer/subtitle path for playback.

**Tech Stack:** ArkTS, HarmonyOS API 26, `@kit.NetworkKit`, existing TMDB client, existing AVPlayer and subtitle parser, Node `node:test` harness.

**Spec:** `docs/superpowers/specs/2026-11-24-flicx-native-source.md`

## Global Constraints

- Do not add a WebView or runtime dependency.
- Do not copy Flicx or GPL/AGPL implementation code; implement from the observed API contract.
- Keep signed source URLs in memory only; do not store them in settings or the library database.
- Pass only IMDb IDs to `/api/sources/{id}`; skip Anilist IDs in this first implementation.
- Reuse the existing TMDB API Key setting and configured metadata language.

## Review Focus

- Search results without an IMDb ID or without an available HLS source must be excluded.
- Relative Flicx source and subtitle URLs must resolve against `https://fli.cx`.
- TV specials (`season 0`) and episode numbers must remain 1-based as returned by TMDB/Flicx.
- Missing subtitles, malformed tracks, and absent quality labels must not break playback.
- Missing TMDB credentials, network errors, and Flicx API changes must surface as readable failures.

---

### Task 1: Flicx response models and pure mapping

**Files:**
- Create: `entry/src/main/ets/flicx/FlicxModels.ets`
- Create: `entry/src/main/ets/flicx/FlicxMapper.ets`
- Modify: `tools/test-modules.txt`
- Create: `tools/tests/flicx.test.mjs`

**Interfaces:**
- `FlicxMapper.searchItems(response, sourceId)` returns normalized movie/series `MediaItem` candidates with IMDb IDs.
- `FlicxMapper.isCjkQuery(term)` routes Chinese-title searches to the TMDB `zh-CN` path because Flicx fuzzy search returned unrelated results for a tested Chinese title.
- `FlicxMapper.mediaId(kind, imdbId)` produces `flicx-movie-tt...` / `flicx-tv-tt...`; `FlicxMapper.parseMediaId(id)` recovers kind, IMDb ID, and optional season/episode from `-sNeN` suffixes.
- `FlicxMapper.sources(response, baseUrl)` returns valid HLS `QualityOption` entries in dedicated-first order.
- `FlicxMapper.subtitles(response, baseUrl)` returns external `SubtitleTrack` entries with stable indices and normalized URLs.
- `FlicxMapper.absoluteUrl(path, baseUrl)` preserves absolute HTTPS URLs and resolves site-relative paths.

- [ ] **Step 1: Add failing mapper tests** for direct film/show search records, unsupported Anilist IDs, missing IMDb IDs, CJK routing, relative/absolute URLs, HLS source ordering, unavailable sources, and `zh`/`zh-Hans` subtitle tracks.
- [ ] **Step 2: Run `node tools/test.mjs`** and confirm the new Flicx cases fail while the existing suite remains unchanged.
- [ ] **Step 3: Implement the typed DTOs and pure mapper functions** in `FlicxModels.ets` and `FlicxMapper.ets`; keep all network calls out of these files.
- [ ] **Step 4: Run `node tools/test.mjs`** and confirm all Flicx mapper cases pass.

### Task 2: TMDB IMDb lookup and Flicx API client

**Files:**
- Modify: `entry/src/main/ets/scraper/TmdbTypes.ets`
- Modify: `entry/src/main/ets/scraper/TmdbClient.ets`
- Create: `entry/src/main/ets/flicx/FlicxApi.ets`
- Modify: `tools/tests/flicx.test.mjs`

**Interfaces:**
- `TmdbClient.findByImdbId(imdbId, kind)` returns the matching TMDB search-result record or `undefined`.
- `FlicxApi.search(term)` calls `/api/search?q=...`.
- `FlicxApi.sources(imdbId, season, episode)` calls `/api/sources/{imdbId}` with optional `s`/`e` query parameters.
- `FlicxApi.subtitles(imdbId, season, episode)` calls the corresponding `/api/subtitles/...` route.
- `FlicxApi.hasPlayableSource(imdbId)` checks for a `has` HLS entry without returning or persisting the signed stream URL.

- [ ] **Step 1: Add tests** for IMDb external lookup response mapping and exact Flicx endpoint/query construction.
- [ ] **Step 2: Run the focused Flicx tests** and confirm they fail on the missing lookup/path helpers.
- [ ] **Step 3: Implement the TMDB IMDb lookup and Flicx HTTP client** using the shared `request`/`getJson` helpers; convert HTTP/API failures to readable errors.
- [ ] **Step 4: Run `node tools/test.mjs`** and confirm the new tests pass.

### Task 3: Built-in Flicx `MediaProvider`

**Files:**
- Modify: `entry/src/main/ets/common/Models.ets`
- Create: `entry/src/main/ets/flicx/FlicxProvider.ets`
- Modify: `entry/src/main/ets/providers/ProviderRegistry.ets`
- Modify: `entry/src/main/ets/pages/Settings.ets`

**Interfaces:**
- `FlicxProvider` implements all `MediaProvider` methods; catalog-only methods return empty results, while search/details/seasons/episodes/playback use Flicx and TMDB.
- `ProviderRegistry.all()` includes one built-in Flicx provider, and `ProviderRegistry.get('flicx')` returns that same provider for detail/player routes.

- [ ] **Step 1: Add pure mapper tests** for CJK query routing, Flicx availability filtering, custom movie/series/season/episode IDs, and playback request parameter mapping; keep platform HTTP calls outside the Node test harness.
- [ ] **Step 2: Run focused tests** and confirm the missing provider behaviors fail.
- [ ] **Step 3: Implement the provider**: English Flicx search; CJK TMDB search in configured language; bounded source-availability checks; TMDB detail/episode mapping; HLS quality alternatives; subtitle tracks; no-op unsupported library/reporting actions.
- [ ] **Step 4: Register the built-in provider** without storing it as a user server, and update settings text to explain the TMDB key and Flicx source.
- [ ] **Step 5: Run `node tools/test.mjs`** and confirm all tests pass.

### Task 4: Build and playback-path verification

**Files:**
- Modify: `README.md` only if the existing feature summary needs the built-in online source documented.

- [ ] **Step 1: Run `tools/iso-build.sh flicx`** and confirm ArkTS/HAP compilation succeeds without overwriting the existing build output.
- [ ] **Step 2: Run `hdc list targets`**; if a HarmonyOS device is connected, install the generated HAP and test Chinese search, a film, one TV episode, server switching, and subtitle selection on-device.
- [ ] **Step 3: If no device is connected, report that limitation and retain API/HLS manifest checks as the available playback evidence.**
