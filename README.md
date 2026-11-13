# 影库 (CineVault) for HarmonyOS

Native ArkTS video player for HarmonyOS 7 (API 26): Emby, Jellyfin and Quark drive sources,
TMDB scraping for drive files, big-screen home view.

Build: `tools/build.sh debug` → `entry/build/default/outputs/default/entry-default-unsigned.hap` (sign it yourself).
Parallel compile check without touching entry/build: `tools/iso-build.sh <name>`.
Unit tests: list UI-free modules (path under entry/src/main/ets, no extension) in `tools/test-modules.txt`;
tests in `tools/tests/*.test.mjs` import them from `process.env.CV_OUT`.
