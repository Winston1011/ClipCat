## 概述
- 目标：按 P0 清单实现 MVP 关键路径，覆盖剪贴板采集、菜单栏与面板、时间线 UI、直接/快速粘贴、Paste Stack、基础搜索、设置与快捷键映射。
- 技术栈：Swift 5.9+、SwiftUI、AppKit、Carbon 热键、Core Data、CloudKit（同步在 P2）。
- 验收对齐：面板唤起 ≤ 150ms；100 项历史滚动流畅；搜索响应 ≤ 200ms；常见应用直接粘贴成功率 ≥ 95%。

## 项目初始化
- 创建 `App` Target 与 `Menubar` 辅助入口；配置 Bundle ID、签名、Team。
- 启用 Entitlements：`App Sandbox`、`com.apple.security.files.user-selected.read-write`、`Accessibility`（使用说明）、后续 `iCloud` 预留但默认关闭。
- 目录结构：
  - `App/`（入口与窗口管理）
  - `Services/`（ClipboardMonitor、PasteService、HotkeyService、PrivacyRules）
  - `Storage/`（CoreDataStack、IndexStore、Thumbnails）
  - `UI/`（StatusBarEntry、PanelWindow、HistoryTimelineView、PinboardListView、PreviewSheet、SettingsView）
  - `Models/`（ClipItem、Pinboard、Settings、SearchFilters、Enums/UTI）
  - `Tests/`（单元与集成）
- 依赖管理：纯系统框架，无第三方；SwiftGen 可选，暂不引入。

## 菜单栏入口与面板窗口
- 创建 `NSStatusBar` 项：显示授权状态与快捷操作（打开面板、设置）。
- `PanelWindow`（SwiftUI）：无边框浮层、暗/亮模式、失焦隐藏；默认隐藏，`⇧+⌘+V` 唤起。
- 性能：预创建窗口实例与数据快照，确保唤起 ≤ 150ms。

## 数据模型与本地存储（Core Data）
- 模型：`ClipItem(id,type,contentRef,text,sourceApp,copiedAt,metadata,tags,isPinned)`；`Pinboard(id,name,color,order)`；`Settings(historyRetentionDays,ignoredApps,syncEnabled,privacy,shortcuts)`。
- Core Data 堆栈：持久容器、轻量迁移；大内容落盘 `Application Support/Paste/Store`，缩略图至 `Caches/Paste/Thumbnails`。
- 清理任务：每日定时按保留期清理历史与孤立缩略图。

## 剪贴板监听（ClipboardMonitor）
- 轮询 `NSPasteboard.general.changeCount` 每 300–500ms；解析类型优先级：字符串、URL、图像（tiff/png）、文件 URL、颜色。
- 生成 `ClipItem` 写入 `IndexStore`；异步缩略图生成后更新 UI。
- 隐私规则：忽略敏感应用（`ignoredApps` BundleID 列表）；屏幕共享时隐藏面板。

## 时间线 UI（HistoryTimelineView）
- `ScrollView(.horizontal)` + `LazyHStack` 卡片；显示缩略图/类型/来源/时间戳；多选、删除、拖拽到 Pinboard 或外部应用。
- 导航：方向键左右、`⌘+↑/↓` 跳至首尾；`Space` 预览。

## 直接粘贴能力（PasteService）
- 将目标项组装为 `NSPasteboardItem` 写入系统剪贴板；使用辅助权限向前台应用发送 `⌘+V`。
- 纯文本粘贴：仅写入 `public.utf8-plain-text`。
- 权限引导：检测无辅助权限时展示引导并回退为“复制到系统剪贴板”。

## 快速粘贴（数字快捷键）
- 注册 `⌘+1…9` 与 `⇧+⌘+1…9`；按当前列表索引选中并粘贴；带 `⇧` 时执行纯文本粘贴。
- 冲突处理：注册失败时提示并引导修改快捷键。

## Paste Stack（顺序粘贴栈）
- `stackActive` 切换（`⇧+⌘+C`）；ClipboardMonitor 将新项依序入栈。
- 投递：依次写入剪贴板并发送 `⌘+V`；用后移除；支持方向切换与反转。

## 基础搜索（SearchService + UI）
- 本地索引查询：关键词 + 类型/来源过滤；分页返回。
- UI：输入即搜；结果列表支持回车/Tab 顺序浏览；组合过滤正确命中。

## 设置页与快捷键映射
- `SettingsView` 分页：General/Privacy/Rules/Shortcuts。
- 映射：允许用户修改常用快捷；写入持久化并实时生效；检测冲突提示。

## 权限与隐私
- 辅助功能：粘贴与 Stack 投递所需；引导开启并说明用途。
- 屏幕共享隐私：检测系统广播或 `CGWindowListCopyWindowInfo`，共享时隐藏面板或遮蔽缩略图。
- 历史保留：默认 30 天，可配置；按期清理。

## 性能与稳定性
- 预渲染与状态缓存；索引与缩略图在后台队列；避免主线程阻塞。
- 写入原子性：大内容先落盘再提交事务；崩溃恢复进行一致性修复。

## 测试与验收
- 单测：ClipboardMonitor 解析、IndexStore 查询/清理、PrivacyRules 生效、PasteService 投递、SearchService 过滤。
- 集成：权限引导与失败回退、Stack 多应用序列、Pinboards 基本拖拽排序、面板唤起性能、搜索响应。
- 验收：
  - 面板唤起 ≤ 150ms；历史 100 项滚动流畅（60fps 目标）。
  - 复制事件完整入库；直接粘贴成功率 ≥ 95%。
  - 搜索输入到结果 ≤ 200ms；组合过滤正确命中。

## 交付物
- 可运行的菜单栏应用与面板窗口；P0 功能完整贯通。
- 基础数据模型与 Core Data 持久化；隐私与清理策略可用。
- 单元与集成测试覆盖关键路径；构建与签名配置完整。