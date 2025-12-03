import Foundation

public struct ClipItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let type: ClipType
    public var name: String
    public let contentRef: URL?
    public let text: String?
    public let sourceApp: String
    public let copiedAt: Date
    public var metadata: [String: String]
    public var tags: [String]
    public var isPinned: Bool
    public init(id: UUID = UUID(), type: ClipType, contentRef: URL? = nil, text: String? = nil, sourceApp: String, copiedAt: Date = Date(), metadata: [String: String] = [:], tags: [String] = [], isPinned: Bool = false, name: String? = nil) {
        self.id = id
        self.type = type
        self.name = name ?? type.rawValue
        self.contentRef = contentRef
        self.text = text
        self.sourceApp = sourceApp
        self.copiedAt = copiedAt
        self.metadata = metadata
        self.tags = tags
        self.isPinned = isPinned
    }
}