# ClipCat（macOS）技术设计文档（Swift + SwiftUI）

## 1. 技术栈与目标
- 客户端：Swift 5.9+、SwiftUI、Combine/Swift Concurrency。
- 桥接：AppKit（`NSPasteboard`、`NSStatusBar`、`QLPreviewPanel`、`NSApplication`）、Carbon（`RegisterEventHotKey`）。
- 存储：Core Data（SQLite）本地索引，文件型内容落盘；CloudKit 私有数据库做账户内多设备同步。
- 权限：辅助功能（直接粘贴与栈投递）、iCloud、文件沙盒、屏幕录制/共享隐私控制。
- 目标：满足 PRD 的 MVP 十项核心功能与性能指标。

## 2. 总体架构
- 应用形态：菜单栏应用 + 可唤起的主面板窗口，前台聚焦最小化打扰。
- 模块划分：
  - ClipboardMonitor：轮询 `NSPasteboard.general.changeCount` 捕获复制事件，解析类型并产出 `ClipItem`。
  - IndexStore：Core Data 读写与查询、缩略图缓存、数据清理（保留期）。
  - PreviewService：Quick Look 与富预览桥接；文本编辑、纯文本转换。
  - PinboardService：Pinboard 的 CRUD 与排序、跨设备同步。
  - PasteService：直接粘贴到前台应用、栈式投递；可选粘贴为纯文本。
  - SearchService：本地索引搜索与过滤（类型/来源/关键词）。
  - SyncService：CloudKit 私有库增量同步；断网合并与冲突解决。
  - PrivacyRules：忽略敏感应用、屏幕共享时隐藏、历史保留周期。
  - HotkeyService：注册全局快捷键与路由到对应操作。
  - Settings：偏好项、快捷键映射、规则与同步开关。
- 数据流：
  - 复制事件 → ClipboardMonitor → IndexStore 写入 → UI 刷新 → 可选 SyncService → 多端一致。
  - 用户操作（粘贴/编辑/Pin）→ IndexStore 更新 → PasteService 执行 → SyncService 分发。

## 3. 数据模型
- ClipItem
  - `id: UUID`
  - `type: ClipType`（`text|link|image|file|color`）
  - `contentRef: ContentRef`（文本内容、文件路径、二进制引用）
  - `sourceApp: String`
  - `copiedAt: Date`
  - `metadata: Metadata`（如 `url/title/thumbnailPath/uti`）
  - `tags: [String]`
  - `isPinned: Bool`
- Pinboard
  - `id: UUID`、`name: String`、`color: String`、`order: Int`
- Stack
  - `items: [UUID]`、`direction: asc|desc`、`active: Bool`
- Settings
  - `historyRetentionDays: Int`
  - `ignoredApps: [BundleID]`
  - `syncEnabled: Bool`
  - `privacy: { hideOnScreenShare: Bool }`
  - `shortcuts: { showPanel, quickPaste1…9, stackToggle, pastePlainText }`

## 4. 存储与同步
- 本地存储：
  - Core Data 作为主索引与查询；大内容（图像/文件）落盘 `Application Support/Paste/Store`，记录路径引用。
  - 缩略图缓存：`Caches/Paste/Thumbnails`，异步生成；图像生成失败时降级为类型图标。
  - 清理策略：每日定时任务按保留期（默认 30 天）清理历史与孤立缩略图。
- 云同步（CloudKit 私有库）：
  - Record 类型：`ClipItemRecord`、`PinboardRecord`、`SettingsRecord`；内容大于阈值使用 `CKAsset`。
  - 同步策略：本地写入触发上传；远端变更订阅推送；冲突以 `copiedAt` 与 `updatedAt` 合并，保留两版时附加 `conflict` 标记。
  - 开关：`syncEnabled` 控制；离线累积增量，恢复时批量合并。

## 5. 权限与沙盒
- 辅助功能：用于发送 `⌘+V/⌘+C` 到前台应用以及会话级事件投递。
- iCloud：CloudKit 私有库，启用 `com.apple.developer.icloud-services` 与容器标识。
- 文件沙盒：读写 `Application Support`、`Caches`；拖拽到外部时通过 `NSItemProvider`/临时文件。
- 屏幕共享隐私：检测 `CGWindowListCopyWindowInfo` 与系统广播，面板在共享时隐藏或遮蔽敏感缩略图。

## 6. 关键流程
### 6.1 复制事件采集
1. 设定 `DispatchSourceTimer` 每 300–500ms 轮询 `NSPasteboard.general.changeCount`。
2. 变更时读取 `types` 并按优先级解析：`stringForType`、`URL`、`tiff/png`、`fileURL`、`color`。
3. 生成 `ClipItem`，写入 `IndexStore`，异步生成缩略图并更新 UI。
4. 触发 `SyncService` 上传与推送订阅。

### 6.2 直接粘贴
1. 将目标项写入系统剪贴板（按目标类型组装 `NSPasteboardItem`）。
2. 使用辅助权限发送 `⌘+V` 到前台进程。
3. 粘贴为纯文本时只写入 `public.utf8-plain-text`。

### 6.3 Paste Stack
1. `stackActive = true` 后，ClipboardMonitor 将新复制项依序加入 Stack。
2. 触发投递：为每个项依次写入剪贴板并发送 `⌘+V`，用后从栈移除；方向由设置或 UI 切换。

### 6.4 搜索
- 输入即搜，索引在 Core Data；支持 `type`、`sourceApp`、关键词组合；分页返回；UI 使用 `@Query` 或 `NSFetchedResultsController` 桥接到 SwiftUI。

## 7. UI 结构（SwiftUI）
- StatusBarEntry：菜单栏入口、授权状态、快捷操作。
- PanelWindow（可无边框浮层）：
  - Toolbar：Clipboard/Pinboards 标签、搜索输入、`+` 创建、设置入口。
  - HistoryTimelineView：`ScrollView(.horizontal)` + `LazyHStack` 卡片；支持多选、拖拽、快捷键导航。
  - PinboardListView：Pinboard tabs 与列表；拖拽排序、右键上下文菜单。
  - PreviewSheet：文本与链接、图像预览；编辑与重命名；纯文本粘贴按钮。
  - StackBanner：栈激活提示与方向切换控件。
- SettingsView：General/Privacy/Rules/Sync/Shortcuts 分页。

## 8. 快捷键实现
- Carbon `RegisterEventHotKey` 注册全局热键；通过事件路由到 `HotkeyService`。
- 冲突处理：若注册失败（被系统占用）弹出提示并建议修改。

## 9. 代码骨架
```swift
import SwiftUI
import AppKit

enum ClipType { case text, link, image, file, color }

struct ClipItem: Identifiable {
    let id: UUID
    let type: ClipType
    let contentRef: URL?
    let text: String?
    let sourceApp: String
    let copiedAt: Date
}

final class ClipboardMonitor: ObservableObject {
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    func start() {
        timer = DispatchSource.makeTimerSource()
        timer?.schedule(deadline: .now(), repeating: .milliseconds(400))
        timer?.setEventHandler { [weak self] in self?.poll() }
        timer?.resume()
    }
    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        handlePasteboard(pb)
    }
    private func handlePasteboard(_ pb: NSPasteboard) {
        let types = pb.types ?? []
        if types.contains(.string) {
            let text = pb.string(forType: .string) ?? ""
            let item = ClipItem(id: UUID(), type: .text, contentRef: nil, text: text, sourceApp: currentAppName(), copiedAt: Date())
            DispatchQueue.main.async { NotificationCenter.default.post(name: .didCaptureItem, object: item) }
        }
    }
    private func currentAppName() -> String { NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown" }
}

extension Notification.Name { static let didCaptureItem = Notification.Name("didCaptureItem") }
```

```swift
import Carbon.HIToolbox

final class HotkeyService {
    private var showPanelRef: EventHotKeyRef?
    func register() {
        let id = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x50415354)), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &showPanelRef)
    }
}
```

```swift
import SwiftUI

struct HistoryTimelineView: View {
    let items: [ClipItem]
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    VStack { Text(title(for: item)).lineLimit(2) }
                        .frame(width: 220, height: 140)
                        .background(.thinMaterial)
                        .cornerRadius(12)
                }
            }.padding(16)
        }
    }
    private func title(for item: ClipItem) -> String { item.text ?? item.contentRef?.lastPathComponent ?? "Item" }
}
```

## 10. 性能与稳定性
- 面板唤起目标 ≤ 150ms：预渲染与状态缓存；在后台维护数据快照。
- 滚动流畅：`LazyHStack` 与缩略图异步生成；按需加载。
- 索引与搜索：后台队列与轻量 FTS；避免主线程阻塞。
- 写入原子性：大内容先落盘再提交事务；崩溃恢复时进行一致性修复。

## 11. 测试与验证
- 单元测试：`ClipboardMonitor` 解析、`IndexStore` 查询、`PrivacyRules` 生效逻辑。
- 集成测试：栈式复制粘贴、直接粘贴权限流、Pinboard 操作与同步一致性。
- 性能基准：面板唤起、搜索响应、同步延迟。

## 12. 交付与配置
- Entitlements：iCloud、App Sandbox、com.apple.security.files.user-selected.read-write。
- 签名与公证：Xcode 自动化；构建后提交公证。
- 本地化：中文/英文；SwiftGen 可选资源生成。

## 13. 路线图对齐
- MVP：本技术文档覆盖范围对应 PRD 的 10 项核心功能。
- V1+：共享 Pinboards、图像与 OCR、AI 写作辅助与更强搜索语法。

---

该技术文档用于指导 Swift + SwiftUI 的实现与评审，后续可在评审后细化到模块级接口与数据表结构。

## 14. 接口说明（Protocols）

```swift
import Foundation

protocol ClipboardMonitorProtocol {
    func start()
    func stop()
    var onItemCaptured: (ClipItem) -> Void { get set }
    func setIgnoredApps(_ bundleIDs: [String])
}

protocol IndexStoreProtocol {
    func save(_ item: ClipItem) throws
    func delete(_ id: UUID) throws
    func item(_ id: UUID) -> ClipItem?
    func query(_ filters: SearchFilters, limit: Int, offset: Int) -> [ClipItem]
    func pin(_ id: UUID, to boardID: UUID) throws
    func unpin(_ id: UUID, from boardID: UUID) throws
    func createPinboard(name: String, color: String?) -> UUID
    func deletePinboard(_ id: UUID) throws
    func listPinboards() -> [Pinboard]
    func listItems(in boardID: UUID) -> [ClipItem]
}

protocol PasteServiceProtocol {
    func paste(_ item: ClipItem, plainText: Bool)
    func activateStack(directionAsc: Bool)
    func deactivateStack()
    func pushToStack(_ item: ClipItem)
    func deliverStack()
}

protocol SearchServiceProtocol {
    func search(_ query: String, filters: SearchFilters, limit: Int) -> [ClipItem]
}

protocol SyncServiceProtocol {
    func enable()
    func disable()
    func push(items: [ClipItem])
    func pullLatest(completion: @escaping ([ClipItem]) -> Void)
}

protocol PrivacyRulesProtocol {
    func shouldCapture(bundleID: String) -> Bool
    var hideOnScreenShare: Bool { get set }
}

protocol HotkeyServiceProtocol {
    func registerShowPanel()
    func registerQuickPasteSlots()
    func registerStackToggle()
    func unregisterAll()
}

protocol SettingsStoreProtocol {
    func load() -> Settings
    func save(_ settings: Settings) throws
}

struct SearchFilters {
    var types: [ClipType]
    var sourceApps: [String]
}
```

示例调用流程：

```swift
let monitor: ClipboardMonitorProtocol = ClipboardMonitor()
let store: IndexStoreProtocol = IndexStore()

monitor.onItemCaptured = { item in
    try? store.save(item)
}
monitor.start()
```

## 15. 开发任务清单与步骤（按优先级）

### P0 关键路径（先做）
- 初始化工程与代码脚手架：App Target、Entitlements、目录结构、依赖管理。
- 菜单栏入口与面板窗口：`NSStatusBar` + SwiftUI `PanelWindow`。
- 数据模型与本地存储：`ClipItem/Pinboard/Settings`、Core Data 堆栈与迁移。
- ClipboardMonitor 集成：监听 `NSPasteboard` 并入库，忽略规则生效。
- 时间线 UI：`HistoryTimelineView` 横向卡片、基本选择与拖拽。
- 直接粘贴能力：写入系统剪贴板并发送 `⌘+V`，权限引导流。
- 快速粘贴：`⌘+1…9` 与 `⇧+⌘+1…9` 纯文本粘贴。
- Paste Stack：激活、入栈、方向切换、顺序投递、用后出栈。
- 基础搜索：关键词 + 类型/来源过滤；结果分页与导航。
- 设置页与快捷键映射：General/Privacy/Rules/Shortcuts。

### P1 次要但重要（后做）
- Pinboards 完整能力：颜色、排序、拖拽管理与跨设备一致性。
- 预览与轻编辑：Quick Look、文本编辑、链接富预览最小实现。
- 屏幕共享隐私：共享场景时隐藏面板或遮蔽缩略图。

### P2 进阶能力（排后）
- iCloud 同步：CloudKit 私有库的增量同步与冲突合并。
- 空格键预览增强：媒体播放、内置浏览器、图片工具与 OCR。
- 高级搜索语法与保存的过滤器。
- Apple Intelligence 写作辅助。

## 16. 里程碑与验收

- 里程碑 A（2 周）：脚手架、菜单栏与面板、模型与存储、ClipboardMonitor、时间线最小 UI。
  - 验收：面板唤起 ≤ 150ms；100 项历史滚动流畅；复制事件完整入库。
- 里程碑 B（2–3 周）：直接粘贴、快速粘贴、Paste Stack、基础搜索、设置与隐私规则。
  - 验收：常见应用直接粘贴成功率 ≥ 95%；栈粘贴 10 项顺序正确；搜索响应 ≤ 200ms。
- 里程碑 C（2 周）：Pinboards 完整、预览与轻编辑、屏幕共享隐私。
  - 验收：Pinboards 跨场景稳定；预览 ≤ 200ms；共享时不泄露。
- 里程碑 D（3–4 周）：CloudKit 同步与增强预览、OCR、进阶搜索与 AI。
  - 验收：两设备同步延迟 ≤ 3 秒；冲突合并正确；OCR 与富预览稳定。

## 17. 测试任务清单
- 单测：ClipboardMonitor 解析、IndexStore 查询与清理、PrivacyRules 过滤、PasteService 投递。
- 集成：权限引导与失败回退、Paste Stack 多应用序列、Pinboards CRUD 与拖拽排序。
- 性能：面板唤起、滚动流畅度、搜索耗时、缩略图异步生成迭代。
- 同步（P2）：断网合并、冲突双版保留、增量订阅推送。

## 18. 风险与回退策略
- 辅助权限被拒：回退为复制到剪贴板，由用户手动 `⌘+V`。
- 受限目标应用：检测失败后提示并回退复制策略。
- 大内容与缩略图失败：异步重试与类型图标降级。
- CloudKit 不稳定：提供本地模式与后台重试队列。
