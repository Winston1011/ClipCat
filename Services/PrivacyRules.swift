import Foundation

// 隐私规则：控制采集行为与屏幕共享时的显示策略
public final class PrivacyRules: PrivacyRulesProtocol {
    public var hideOnScreenShare: Bool
    private var ignored: Set<String>
    public init(hideOnScreenShare: Bool = true, ignoredApps: [String] = []) {
        self.hideOnScreenShare = hideOnScreenShare
        self.ignored = Set(ignoredApps)
    }
    public func shouldCapture(bundleID: String) -> Bool { !ignored.contains(bundleID) }
}