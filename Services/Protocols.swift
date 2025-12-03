import Foundation

// 剪贴板监听协议
public protocol ClipboardMonitorProtocol {
    func start()
    func stop()
    var onItemCaptured: ((ClipItem) -> Void)? { get set }
    func setIgnoredApps(_ bundleIDs: [String])
}

// 本地索引存储协议
public protocol IndexStoreProtocol {
    func save(_ item: ClipItem) throws
    func delete(_ id: UUID) throws
    func item(_ id: UUID) -> ClipItem?
    func query(_ filters: SearchFilters, query: String?, limit: Int, offset: Int) -> [ClipItem]
    func pin(_ id: UUID, to boardID: UUID) throws
    func unpin(_ id: UUID, from boardID: UUID) throws
    func createPinboard(name: String, color: String?) -> UUID
    func deletePinboard(_ id: UUID) throws
    func updatePinboardName(_ id: UUID, name: String)
    func updatePinboardColor(_ id: UUID, color: String?)
    func listPinboards() -> [Pinboard]
    func listItems(in boardID: UUID) -> [ClipItem]
}

// 粘贴服务协议
public protocol PasteServiceProtocol {
    func paste(_ item: ClipItem, plainText: Bool)
    func activateStack(directionAsc: Bool)
    func deactivateStack()
    func pushToStack(_ item: ClipItem)
    func deliverStack()
}

// 搜索服务协议
public protocol SearchServiceProtocol {
    func search(_ query: String, filters: SearchFilters, limit: Int) -> [ClipItem]
}

// 隐私规则协议
public protocol PrivacyRulesProtocol {
    func shouldCapture(bundleID: String) -> Bool
    var hideOnScreenShare: Bool { get set }
}

// 快捷键服务协议
public protocol HotkeyServiceProtocol {
    func registerShowPanel()
    func registerQuickPasteSlots()
    func registerStackToggle()
    func unregisterAll()
}

// 设置存储协议
public protocol SettingsStoreProtocol {
    func load() -> AppSettings
    func save(_ settings: AppSettings) throws
}