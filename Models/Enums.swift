import Foundation

// 剪贴类型枚举
public enum ClipType: String, Codable, CaseIterable {
    case text
    case link
    case image
    case file
    case color
}

public enum HistoryLayoutStyle: String, Codable, CaseIterable {
    case horizontal
    case grid
    case vertical
}

// 搜索过滤条件：按类型与来源应用过滤
public struct SearchFilters: Codable, Equatable {
    public var types: [ClipType]
    public var sourceApps: [String]
    public init(types: [ClipType] = [], sourceApps: [String] = []) {
        self.types = types
        self.sourceApps = sourceApps
    }
}
