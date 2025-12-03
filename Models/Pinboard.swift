import Foundation

// 看板模型：用于收藏与分组管理
public struct Pinboard: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var color: String?
    public var order: Int
    public init(id: UUID = UUID(), name: String, color: String? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.order = order
    }
}