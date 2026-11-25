# 影库 (CineVault) for HarmonyOS

Native ArkTS video player for HarmonyOS 7 (API 26): Emby, Jellyfin and Quark drive sources,
TMDB scraping for drive files, big-screen home view, and a built-in Flicx source for films and TV series.

在首页点 **搜索电影和剧集**，直接输入英文片名，如 `Bodies`。在 **设置 › 刮削** 填写自己的 TMDB API Key 或读访问令牌后，也可以用中文片名搜索。选择剧集的季和集即可播放，在播放器的 **线路** 和 **字幕** 菜单切换线路或字幕。

搜索仅列出 Flicx 报告有 HLS 线路的 IMDb 条目。线路和 WebVTT 字幕按电影或具体集数重新获取。英文搜索支持使用站内分集资料，TMDB 提供本地化详情。此源依赖 Flicx 网页使用的接口，收录情况可能变动。

Build: `tools/build.sh debug` → `entry/build/default/outputs/default/entry-default-unsigned.hap` (sign it yourself).
Parallel compile check without touching entry/build: `tools/iso-build.sh <name>`.
Unit tests: list UI-free modules (path under entry/src/main/ets, no extension) in `tools/test-modules.txt`;
tests in `tools/tests/*.test.mjs` import them from `process.env.CV_OUT`.
