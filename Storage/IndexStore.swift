import Foundation

// 本地索引存储：维护剪贴历史、看板与关联关系，提供查询与置顶能力
public final class IndexStore: IndexStoreProtocol {
    public static let shared = IndexStore()
    public static let changeNotification = Notification.Name("IndexStoreDidChange")
    private var items: [ClipItem] = []
    private var pinboards: [Pinboard] = []
    private var boardItems: [UUID: Set<UUID>] = [:]
    private var contentCache: [UUID: String] = [:]
    private let queue = DispatchQueue(label: "store.queue", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<String>()
    public private(set) var defaultBoardID: UUID
    private let indexURL: URL
    private let contentDir: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let settingsStore = SettingsStore()
    private struct Snapshot: Codable {
        var items: [ClipItem]
        var pinboards: [Pinboard]
        var boardItems: [UUID: [UUID]]
    }
    public init() {
        let appDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("ClipCat")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.contentDir = appDir.appendingPathComponent("Store")
        try? FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        self.indexURL = appDir.appendingPathComponent("index.json")
        self.pinboards = []
        self.defaultBoardID = UUID()
        queue.setSpecific(key: queueKey, value: "store.queue")
        loadSnapshot()
        let s = settingsStore.load()
        queue.sync {
            cleanupExpiredItems(days: s.historyRetentionDays)
            cleanupExceededItems(limit: s.historyMaxItems)
        }
    }
    public func save(_ item: ClipItem) throws {
        queue.sync {
            let persisted = ensurePermanentContent(item)
            items.removeAll { isDuplicate($0, persisted) }
            if let i = items.firstIndex(where: { $0.id == persisted.id }) { items[i] = persisted } else { items.insert(persisted, at: 0) }
            contentCache[persisted.id] = nil
            persist()
            let s = settingsStore.load()
            cleanupExpiredItems(days: s.historyRetentionDays)
            cleanupExceededItems(limit: s.historyMaxItems)
        }
    }
    public func delete(_ id: UUID) throws {
        queue.sync {
            items.removeAll { $0.id == id }
            for (bid, set) in boardItems { var s = set; s.remove(id); boardItems[bid] = s }
            contentCache[id] = nil
            persist()
        }
    }
    public func item(_ id: UUID) -> ClipItem? {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return items.first { $0.id == id } }
        return queue.sync { items.first { $0.id == id } }
    }
    public func query(_ filters: SearchFilters, query: String?, limit: Int, offset: Int) -> [ClipItem] {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            var r = items
            // 类型过滤
            if !filters.types.isEmpty { r = r.filter { filters.types.contains($0.type) } }
            // 来源应用过滤
            if !filters.sourceApps.isEmpty { r = r.filter { filters.sourceApps.contains($0.sourceApp) } }
            if let q = query, !q.isEmpty {
                let qs = q.lowercased()
                r = r.filter { itemMatches($0, qs: qs) }
            }
            let s = offset
            let e = min(r.count, s + max(0, limit))
            if s >= e { return [] }
            return Array(r[s..<e])
        }
        return queue.sync {
            var r = items
            if !filters.types.isEmpty { r = r.filter { filters.types.contains($0.type) } }
            if !filters.sourceApps.isEmpty { r = r.filter { filters.sourceApps.contains($0.sourceApp) } }
            if let q = query, !q.isEmpty {
                let qs = q.lowercased()
                r = r.filter { itemMatches($0, qs: qs) }
            }
            let s = offset
            let e = min(r.count, s + max(0, limit))
            if s >= e { return [] }
            return Array(r[s..<e])
        }
    }
    private func itemMatches(_ item: ClipItem, qs: String) -> Bool {
        if let agg = aggregatedText(item) { return matches(hay: agg, needle: qs) }
        return false
    }

    private func matches(hay: String?, needle: String) -> Bool {
        guard let h = hay, !h.isEmpty else { return false }
        return h.contains(needle)
    }
    private func aggregatedText(_ item: ClipItem) -> String? {
        if let cached = contentCache[item.id] { return cached }
        var parts: [String] = []
        if let t = item.text, !t.isEmpty { parts.append(t) }
        if let url = item.metadata["url"], !url.isEmpty { parts.append(url) }
        if item.type == .text, let u = item.contentRef {
            let ext = u.pathExtension.lowercased()
            if ext == "txt" {
                if let s = try? String(contentsOf: u) { parts.append(s) }
            } else if let a = try? NSAttributedString(url: u, options: [:], documentAttributes: nil) {
                parts.append(a.string)
            }
        }
        guard !parts.isEmpty else { return nil }
        let agg = parts.joined(separator: " ").lowercased()
        contentCache[item.id] = agg
        return agg
    }
    public func pin(_ id: UUID, to boardID: UUID) throws {
        queue.sync {
            var set = boardItems[boardID] ?? []
            set.insert(id)
            boardItems[boardID] = set
            persist()
        }
    }
    public func unpin(_ id: UUID, from boardID: UUID) throws {
        queue.sync {
            var set = boardItems[boardID] ?? []
            set.remove(id)
            boardItems[boardID] = set
            persist()
        }
    }
    public func createPinboard(name: String, color: String?) -> UUID {
        let b = Pinboard(name: name, color: color, order: pinboards.count)
        pinboards.append(b)
        persist()
        return b.id
    }
    public func updatePinboardName(_ id: UUID, name: String) {
        guard id != defaultBoardID else { return }
        queue.sync {
            if let i = pinboards.firstIndex(where: { $0.id == id }) {
                pinboards[i].name = name
                persist()
            }
        }
    }
    public func updatePinboardColor(_ id: UUID, color: String?) {
        guard id != defaultBoardID else { return }
        queue.sync {
            if let i = pinboards.firstIndex(where: { $0.id == id }) {
                pinboards[i].color = color
                persist()
            }
        }
    }
    public func deletePinboard(_ id: UUID) throws {
        guard id != defaultBoardID else { return }
        pinboards.removeAll { $0.id == id }
        boardItems[id] = nil
        persist()
    }
    public func listPinboards() -> [Pinboard] { pinboards.sorted { $0.order < $1.order } }
    public func listItems(in boardID: UUID) -> [ClipItem] {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            if boardID == defaultBoardID { return items }
            let ids = boardItems[boardID] ?? []
            return items.filter { ids.contains($0.id) }
        }
        return queue.sync {
            if boardID == defaultBoardID { return items }
            let ids = boardItems[boardID] ?? []
            return items.filter { ids.contains($0.id) }
        }
    }
    public func moveToFront(_ id: UUID) {
        queue.sync {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                let i = items.remove(at: idx)
                items.insert(i, at: 0)
                persist()
            }
        }
    }

    public func reorder(_ id: UUID, before targetID: UUID) {
        queue.sync {
            guard id != targetID else { return }
            guard let fromIdx = items.firstIndex(where: { $0.id == id }), let toIdx = items.firstIndex(where: { $0.id == targetID }) else { return }
            let it = items.remove(at: fromIdx)
            let insertIdx = (fromIdx < toIdx) ? toIdx - 1 : toIdx
            items.insert(it, at: insertIdx)
            persist()
        }
    }

    public func setBoardExclusive(_ id: UUID, to boardID: UUID) {
        queue.sync {
            for b in pinboards.map({ $0.id }) where b != defaultBoardID {
                var set = boardItems[b] ?? []
                set.remove(id)
                boardItems[b] = set
            }
            if boardID != defaultBoardID {
                var targetSet = boardItems[boardID] ?? []
                targetSet.insert(id)
                boardItems[boardID] = targetSet
            }
            persist()
        }
    }
    private func isDuplicate(_ a: ClipItem, _ b: ClipItem) -> Bool {
        if a.type != b.type { return false }
        switch a.type {
        case .text:
            let ta = (a.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tb = (b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !ta.isEmpty && ta == tb
        case .link:
            let ua = a.metadata["url"] ?? a.contentRef?.absoluteString ?? (a.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ub = b.metadata["url"] ?? b.contentRef?.absoluteString ?? (b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !ua.isEmpty && ua == ub
        case .file, .image:
            let pa = a.contentRef?.absoluteString ?? ""
            let pb = b.contentRef?.absoluteString ?? ""
            return !pa.isEmpty && pa == pb
        case .color:
            return false
        }
    }

    private func loadSnapshot() {
        if let d = try? Data(contentsOf: indexURL), let snap = try? decoder.decode(Snapshot.self, from: d) {
            self.items = snap.items
            self.pinboards = snap.pinboards
            var m: [UUID: Set<UUID>] = [:]
            for (k, v) in snap.boardItems { m[k] = Set(v) }
            self.boardItems = m
            if let def = pinboards.first(where: { $0.name == "剪贴板" }) {
                self.defaultBoardID = def.id
            } else {
                let def = Pinboard(name: "剪贴板", color: nil, order: 0)
                self.defaultBoardID = def.id
                pinboards.insert(def, at: 0)
                persist()
            }
        } else {
            self.items = []
            let def = Pinboard(name: "剪贴板", color: nil, order: 0)
            self.defaultBoardID = def.id
            self.pinboards = [def]
            self.boardItems = [:]
            persist()
        }
    }

    private func persist() {
        let mapped = boardItems.mapValues { Array($0) }
        let snap = Snapshot(items: items, pinboards: pinboards, boardItems: mapped)
        if let d = try? encoder.encode(snap) { try? d.write(to: indexURL) }
        NotificationCenter.default.post(name: IndexStore.changeNotification, object: nil)
    }

    private func ensurePermanentContent(_ item: ClipItem) -> ClipItem {
        guard let ref = item.contentRef else { return item }
        let isTemp = ref.path.hasPrefix(FileManager.default.temporaryDirectory.path)
        if isTemp {
            var ext = ref.pathExtension
            if ext.isEmpty {
                switch item.type { case .image: ext = "png"; case .text: ext = "rtf"; default: ext = "dat" }
            }
            let dst = contentDir.appendingPathComponent(item.id.uuidString).appendingPathExtension(ext)
            if (try? FileManager.default.copyItem(at: ref, to: dst)) != nil {
                var updated = item
                updated = ClipItem(id: item.id, type: item.type, contentRef: dst, text: item.text, sourceApp: item.sourceApp, copiedAt: item.copiedAt, metadata: item.metadata, tags: item.tags, isPinned: item.isPinned, name: item.name)
                return updated
            }
        }
        return item
    }

    private func cleanupExpiredItems(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let pinned = Set(boardItems.values.flatMap { $0 })
        let beforeCount = items.count
        items.removeAll { !pinned.contains($0.id) && $0.copiedAt < cutoff }
        let existing = Set(items.map { $0.id })
        contentCache = contentCache.filter { existing.contains($0.key) }
        if items.count != beforeCount { persist() }
    }

    private func cleanupExceededItems(limit: Int) {
        let pinned = Set(boardItems.values.flatMap { $0 })
        if limit <= 0 {
            let beforeCount = items.count
            items.removeAll { !pinned.contains($0.id) }
            let existing = Set(items.map { $0.id })
            contentCache = contentCache.filter { existing.contains($0.key) }
            if items.count != beforeCount { persist() }
            return
        }
        let nonPinned = items.filter { !pinned.contains($0.id) }
        let excess = max(0, nonPinned.count - limit)
        if excess <= 0 { return }
        let sorted = nonPinned.sorted { $0.copiedAt < $1.copiedAt }
        let idsToRemove = Set(sorted.prefix(excess).map { $0.id })
        let beforeCount = items.count
        items.removeAll { idsToRemove.contains($0.id) }
        let existing = Set(items.map { $0.id })
        contentCache = contentCache.filter { existing.contains($0.key) }
        if items.count != beforeCount { persist() }
    }

    public func exportBackup(to url: URL) throws {
        let mapped = boardItems.mapValues { Array($0) }
        struct ClipItemDTO: Codable {
            var id: UUID
            var type: ClipType
            var name: String
            var text: String?
            var sourceApp: String
            var copiedAt: Date
            var metadata: [String: String]
            var tags: [String]
            var isPinned: Bool
            var contentExt: String?
            var contentData: Data?
        }
        struct BackupDTO: Codable {
            var items: [ClipItemDTO]
            var pinboards: [Pinboard]
            var boardItems: [UUID: [UUID]]
        }
        var dtos: [ClipItemDTO] = []
        for it in items {
            var dto = ClipItemDTO(id: it.id, type: it.type, name: it.name, text: it.text, sourceApp: it.sourceApp, copiedAt: it.copiedAt, metadata: it.metadata, tags: it.tags, isPinned: it.isPinned, contentExt: nil, contentData: nil)
            if let u = it.contentRef, let d = try? Data(contentsOf: u) {
                dto.contentExt = u.pathExtension.isEmpty ? nil : u.pathExtension
                dto.contentData = d
            }
            dtos.append(dto)
        }
        let backup = BackupDTO(items: dtos, pinboards: pinboards, boardItems: mapped)
        let d = try encoder.encode(backup)
        try d.write(to: url)
    }

    public func importBackup(from url: URL) throws {
        struct ClipItemDTO: Codable {
            var id: UUID
            var type: ClipType
            var name: String
            var text: String?
            var sourceApp: String
            var copiedAt: Date
            var metadata: [String: String]
            var tags: [String]
            var isPinned: Bool
            var contentExt: String?
            var contentData: Data?
        }
        struct BackupDTO: Codable {
            var items: [ClipItemDTO]
            var pinboards: [Pinboard]
            var boardItems: [UUID: [UUID]]
        }
        let d = try Data(contentsOf: url)
        let backup = try decoder.decode(BackupDTO.self, from: d)
        var newItems: [ClipItem] = []
        for dto in backup.items {
            var contentURL: URL? = nil
            if let ext = dto.contentExt, let data = dto.contentData {
                let dst = contentDir.appendingPathComponent(dto.id.uuidString).appendingPathExtension(ext)
                try? data.write(to: dst)
                contentURL = dst
            }
            let it = ClipItem(id: dto.id, type: dto.type, contentRef: contentURL, text: dto.text, sourceApp: dto.sourceApp, copiedAt: dto.copiedAt, metadata: dto.metadata, tags: dto.tags, isPinned: dto.isPinned, name: dto.name)
            newItems.append(it)
        }
        var newBoards: [Pinboard] = backup.pinboards
        var newBoardItems: [UUID: Set<UUID>] = [:]
        for (k, v) in backup.boardItems { newBoardItems[k] = Set(v) }
        queue.sync {
            items = newItems
            pinboards = newBoards
            boardItems = newBoardItems
            contentCache.removeAll()
            if let def = pinboards.first(where: { $0.name == "剪贴板" }) { defaultBoardID = def.id }
            persist()
        }
    }
}
