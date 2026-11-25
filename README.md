# 影库 (CineVault) for HarmonyOS

Native ArkTS video player for HarmonyOS 7 (API 26): Emby, Jellyfin and Quark drive sources,
TMDB scraping for drive files, big-screen home view, and a built-in Flicx source for films and TV series.

在首页点右上角的搜索，直接输入英文片名，如 `Bodies`。在 **设置 › 刮削** 填写自己的 TMDB API Key 或读访问令牌后，也可以用中文片名搜索。选择剧集的季和集即可播放，在播放器的 **线路** 和 **字幕** 菜单切换线路或字幕。

搜索仅列出 Flicx 报告有 HLS 线路的 IMDb 条目。线路和 WebVTT 字幕按电影或具体集数重新获取。英文搜索支持使用站内分集资料，TMDB 提供本地化详情。打开应用即进入首页，不需要先添加服务器：首页各栏目（本周热门、4K、影史经典等）解析自 fli.cx 首页，未添加个人媒体源时「电影」「剧集」页也列出这些影片。Flicx 没有账号，收藏、已看和播放进度保存在本机，首页显示「继续观看」和「我的收藏」。演职人员照片和简介没有 TMDB 密钥时取自 Flicx 影片页。此源依赖 Flicx 网页使用的接口和首页结构，收录情况可能变动。

播放器：选集面板可切换季、显示每集剧照和简介；多码率 HLS 可固定分辨率；「设置 › 运行日志」可复制日志用于排查。

Build: `tools/build.sh debug` → `entry/build/default/outputs/default/entry-default-unsigned.hap` (sign it yourself).
Parallel compile check without touching entry/build: `tools/iso-build.sh <name>`.
Unit tests: list UI-free modules (path under entry/src/main/ets, no extension) in `tools/test-modules.txt`;
tests in `tools/tests/*.test.mjs` import them from `process.env.CV_OUT`.
