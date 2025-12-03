import Foundation

// 隐私设置：屏幕共享时是否隐藏
public struct PrivacySettings: Codable, Equatable {
    public var hideOnScreenShare: Bool
    public init(hideOnScreenShare: Bool = true) { self.hideOnScreenShare = hideOnScreenShare }
}

// 快捷键设置：展示面板、快速粘贴、栈切换、纯文本粘贴
public struct Shortcuts: Codable, Equatable {
    public var showPanel: String
    public var quickPaste: [String]
    public var stackToggle: String
    public var pastePlainText: String
    public init(showPanel: String = "shift+cmd+p", quickPaste: [String] = ["cmd+1","cmd+2","cmd+3","cmd+4","cmd+5","cmd+6","cmd+7","cmd+8","cmd+9"], stackToggle: String = "shift+cmd+c", pastePlainText: String = "shift+return") {
        self.showPanel = showPanel
        self.quickPaste = quickPaste
        self.stackToggle = stackToggle
        self.pastePlainText = pastePlainText
    }
}

// 应用设置：历史保留、忽略应用、同步开关、隐私与快捷键
public struct AppSettings: Codable, Equatable {
    public var historyRetentionDays: Int
    public var historyMaxItems: Int
    public var ignoredApps: [String]
    public var syncEnabled: Bool
    public var privacy: PrivacySettings
    public var shortcuts: Shortcuts
    public init(historyRetentionDays: Int = 30, historyMaxItems: Int = 100, ignoredApps: [String] = [], syncEnabled: Bool = false, privacy: PrivacySettings = PrivacySettings(), shortcuts: Shortcuts = Shortcuts()) {
        self.historyRetentionDays = historyRetentionDays
        self.historyMaxItems = historyMaxItems
        self.ignoredApps = ignoredApps
        self.syncEnabled = syncEnabled
        self.privacy = privacy
        self.shortcuts = shortcuts
    }

    private enum CodingKeys: String, CodingKey {
        case historyRetentionDays
        case historyMaxItems
        case ignoredApps
        case syncEnabled
        case privacy
        case shortcuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? 30
        historyMaxItems = try c.decodeIfPresent(Int.self, forKey: .historyMaxItems) ?? 500
        ignoredApps = try c.decodeIfPresent([String].self, forKey: .ignoredApps) ?? []
        syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        privacy = try c.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? PrivacySettings()
        shortcuts = try c.decodeIfPresent(Shortcuts.self, forKey: .shortcuts) ?? Shortcuts()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(historyRetentionDays, forKey: .historyRetentionDays)
        try c.encode(historyMaxItems, forKey: .historyMaxItems)
        try c.encode(ignoredApps, forKey: .ignoredApps)
        try c.encode(syncEnabled, forKey: .syncEnabled)
        try c.encode(privacy, forKey: .privacy)
        try c.encode(shortcuts, forKey: .shortcuts)
    }
}
