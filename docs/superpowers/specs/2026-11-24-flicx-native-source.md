# Flicx 原生在线媒体源

## 目标

在 Harmony CineVault 中加入内置 Flicx 媒体源。用户可以用中文标题搜索电影和 IMDb 标识的剧集，打开详情、选择剧集，并用现有 HarmonyOS 原生播放器播放 Flicx 的 HLS 源和外挂字幕。

## 行为

- 复用现有 `MediaProvider`、TMDB 客户端、`PlaybackInfo`、`SubtitleTrack`、AVPlayer 控制器和字幕解析器，不使用 WebView。
- 英文搜索走 Flicx `/api/search?q=...`；含中文字符的搜索走现有 TMDB 搜索，使用设置中的元数据语言（默认 `zh-CN`）。Flicx 直接搜索对部分中文片名匹配不准。
- 两种搜索都只保留 IMDb `tt...` 条目，并通过 Flicx `/api/sources` 确认至少有一个可用 HLS 源；中文 TMDB 结果先从 TMDB 详情取得 IMDb ID。
- 电影和剧集详情、季、集由现有 TMDB 客户端提供；播放源按 IMDb ID 以及可选的季/集参数从 Flicx 获取。
- 播放器默认选 Flicx 的 dedicated 源，并把其他可用 HLS 源作为画质/服务器选项；外挂字幕从 Flicx subtitles API 获取，沿用原生播放器的字幕解析与显示。
- Flicx 是内置搜索源，不需要用户添加服务器配置。TMDB API Key 沿用应用现有设置。
- Anime 使用 Anilist ID 和另一组播放接口，不属于本次首版范围；不要把不兼容的 Anilist ID 传给 IMDb 播放接口。

## 约束

- 只通过公开 HTTPS API 取搜索、播放源和字幕元数据；不复制网站实现代码，不持久化签名播放 URL。
- Flicx 接口没有稳定公开契约，所有站点路径、响应映射和 URL 规范化集中在 `flicx/` 模块。
- 保持 ArkTS、API 26 和现有无新增运行时依赖的构建方式。
- HLS/字幕可用性取决于 Flicx 当前返回的源；错误要在应用内转成可读信息。

## 验收

- 中文标题能通过 `zh-CN` 搜索，并且结果仅包含 Flicx 有可用播放源的电影/剧集。
- 英文搜索可通过 Flicx 自身搜索接口查找 IMDb 条目；中文搜索由 TMDB 本地化检索并筛选 Flicx 可播放条目。
- 电影能取得 HLS 播放地址；剧集能按 TMDB 季/集号取得对应播放地址。
- 可用字幕轨被映射为原生外挂字幕；相对路径正确解析为 `https://fli.cx/...`。
- 既有测试通过，新增 API 映射测试通过，ArkTS/HAP 构建通过。
