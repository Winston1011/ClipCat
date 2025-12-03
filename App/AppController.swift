import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

final class AppController: ObservableObject {
    let store: IndexStore
    let monitor: ClipboardMonitor
    let paste: PasteService
    let preview: PreviewService
    let hotkeys: HotkeyService
    let panel: PanelWindowController
    @Published var items: [ClipItem] = []
    @Published var query: String = ""
    @Published var filters: SearchFilters = SearchFilters()
    @Published var boards: [Pinboard] = []
    @Published var selectedBoardID: UUID?
    @Published var selectedItemID: UUID?
    @Published var selectionByKeyboard: Bool = false
    @Published var selectedIDs: Set<UUID> = []
    @Published var selectedOrder: [UUID] = []
    @Published var selectionMode: Bool = false
    private var selectionAnchorID: UUID?
    @Published var searchPopoverVisible: Bool = false
    @Published var searchBarWidth: CGFloat = 0
    @Published var sidebarWidth: CGFloat = 180
    private let search: SearchService
    private var cancellables: Set<AnyCancellable> = []
    init() {
        store = IndexStore()
        monitor = ClipboardMonitor()
        paste = PasteService()
        hotkeys = HotkeyService()
        preview = PreviewService()
        panel = PanelWindowController()
        search = SearchService(store: store)
        if let bid = Bundle.main.bundleIdentifier { monitor.setIgnoredApps([bid]) }
        monitor.onItemCaptured = { [weak self] item in
            try? self?.store.save(item)
            self?.paste.pushToStack(item)
            self?.refresh()
        }
        hotkeys.onShowPanel = { [weak self] in self?.panel.toggle() }
        hotkeys.onQuickPaste = { [weak self] idx, plain in
            guard let self = self else { return }
            let list = self.search.search(self.query, filters: self.filters, limit: 100)
            if idx-1 < list.count {
                self.monitor.suppressCaptures(for: 1.0)
                self.paste.paste(list[idx-1], plainText: plain)
                self.store.moveToFront(list[idx-1].id)
                self.refresh()
            }
        }
        hotkeys.onStackToggle = { [weak self] in
            guard let self = self else { return }
            self.paste.activateStack(directionAsc: true)
        }
        panel.setRoot(PanelRootView(controller: self))
        panel.onQueryUpdate = { [weak self] q in self?.query = q }
        panel.onSearchOverlayVisibleChanged = { [weak self] in self?.searchPopoverVisible = $0 }
        panel.onShowSearchPopover = { [weak self] _ in
            self?.searchPopoverVisible = true
        }
        panel.onHideSearchPopover = { [weak self] in self?.searchPopoverVisible = false }
        panel.onShown = { [weak self] in
            self?.selectFirstItemIfNeeded()
        }
        panel.onArrowLeft = { [weak self] in self?.moveSelectionLeft() }
        panel.onArrowRight = { [weak self] in self?.moveSelectionRight() }
        panel.onArrowUp = { [weak self] in self?.moveSelectionUp() }
        panel.onArrowDown = { [weak self] in self?.moveSelectionDown() }
        panel.onEnter = { [weak self] in self?.confirmSelectionAndPaste() }
        panel.previewService = preview
        panel.onSpace = { [weak self] in
            guard let self = self else { return }
            if self.panel.previewService?.isVisible() == true {
                self.panel.previewService?.close()
            } else {
                if let id = self.selectedItemID, let item = self.items.first(where: { $0.id == id }) {
                    self.panel.showPreview(item)
                }
            }
        }
        $searchPopoverVisible
            .sink { [weak self] v in self?.panel.setSearchActive(v) }
            .store(in: &cancellables)
        selectedBoardID = store.defaultBoardID

        $query
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        $selectedItemID
            .removeDuplicates()
            .sink { [weak self] id in
                guard let self = self else { return }
                guard self.panel.previewService?.isVisible() == true else { return }
                guard let id = id, let item = self.items.first(where: { $0.id == id }) else { return }
                self.panel.showPreview(item)
            }
            .store(in: &cancellables)
    }
    
    func start() {
        monitor.start()
        hotkeys.registerShowPanel()
        hotkeys.registerQuickPasteSlots()
        hotkeys.registerStackToggle()
        refresh()
    }
    func refresh() {
        if let bid = selectedBoardID, bid != store.defaultBoardID {
            var r = store.listItems(in: bid)
            if !filters.types.isEmpty { r = r.filter { filters.types.contains($0.type) } }
            if !filters.sourceApps.isEmpty { r = r.filter { filters.sourceApps.contains($0.sourceApp) } }
            if !query.isEmpty {
                let qs = query.lowercased()
                r = r.filter { ($0.text?.lowercased().contains(qs) ?? false) || ($0.metadata["url"]?.lowercased().contains(qs) ?? false) }
            }
            items = Array(r.prefix(200))
        } else {
            items = search.search(query, filters: filters, limit: 200)
        }
        boards = store.listPinboards()
    }
    func pasteItem(_ item: ClipItem, plain: Bool) {
        monitor.suppressCaptures(for: 1.0)
        paste.paste(item, plainText: plain)
        store.moveToFront(item.id)
        refresh()
        panel.hide()
        let msg = plain ? L("toast.copiedPlain") : L("toast.copied")
        panel.showToast(msg)
    }
    func copySelectedPlainText() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let orderedIDs = selectedOrder.filter { selectedIDs.contains($0) }
        let finalIDs = orderedIDs.isEmpty ? ids : orderedIDs
        let itemsToCopy = finalIDs.compactMap { id in items.first(where: { $0.id == id }) }
        let parts: [String] = itemsToCopy.map { plainText(of: $0) }
        let joined = parts.joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
        panel.showToast(L("toast.copied"))
        clearSelection()
    }
    func copySelectedRichText() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let orderedIDs = selectedOrder.filter { selectedIDs.contains($0) }
        let finalIDs = orderedIDs.isEmpty ? ids : orderedIDs
        let itemsToCopy = finalIDs.compactMap { id in items.first(where: { $0.id == id }) }
        let agg = NSMutableAttributedString()
        for (idx, it) in itemsToCopy.enumerated() {
            agg.append(NSAttributedString(string: plainText(of: it)))
            if idx < itemsToCopy.count - 1 { agg.append(NSAttributedString(string: "\n\n")) }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.html, .string], owner: nil)
        let html = htmlAggregate(for: itemsToCopy)
        if let d = html.data(using: .utf8) { pb.setData(d, forType: .html) }
        pb.setString(agg.string, forType: .string)
        panel.showToast(L("toast.copied"))
        clearSelection()
    }
    private func richSegment(of item: ClipItem) -> NSAttributedString {
        switch item.type {
        case .text:
            return NSAttributedString(string: plainText(of: item))
        case .link:
            let urlString = item.contentRef?.absoluteString ?? (item.metadata["url"] ?? (item.text ?? ""))
            let m = NSMutableAttributedString(string: urlString)
            if let u = URL(string: urlString) { m.addAttribute(.link, value: u, range: NSRange(location: 0, length: (m.string as NSString).length)) }
            return m
        case .image:
            if let u = item.contentRef, let d = try? Data(contentsOf: u), let img = NSImage(data: d) {
                let att = NSTextAttachment()
                att.image = img
                if let tiff = img.tiffRepresentation {
                    let fw = FileWrapper(regularFileWithContents: tiff)
                    fw.preferredFilename = "image.tiff"
                    att.fileWrapper = fw
                }
                let seg = NSMutableAttributedString(attachment: att)
                if let t = item.text, !t.isEmpty { seg.append(NSAttributedString(string: "\n")); seg.append(NSAttributedString(string: t)) }
                return seg
            }
            return NSAttributedString(string: item.text ?? "")
        case .file:
            if let u = item.contentRef {
                let extLower = u.pathExtension.lowercased()
                if !extLower.isEmpty, let t = UTType(filenameExtension: extLower), t.conforms(to: .image), let d = try? Data(contentsOf: u), let img = NSImage(data: d) {
                    let att = NSTextAttachment()
                    att.image = img
                    if let tiff = img.tiffRepresentation {
                        let fw = FileWrapper(regularFileWithContents: tiff)
                        fw.preferredFilename = "image.tiff"
                        att.fileWrapper = fw
                    }
                    let seg = NSMutableAttributedString(attachment: att)
                    if let tt = item.text, !tt.isEmpty { seg.append(NSAttributedString(string: "\n")); seg.append(NSAttributedString(string: tt)) } else { seg.append(NSAttributedString(string: "\n" + u.lastPathComponent)) }
                    return seg
                } else {
                    let m = NSMutableAttributedString(string: u.lastPathComponent)
                    m.append(NSAttributedString(string: "\n" + u.absoluteString))
                    if let url = URL(string: u.absoluteString) { m.addAttribute(.link, value: url, range: NSRange(location: (m.string as NSString).length - u.absoluteString.count, length: u.absoluteString.count)) }
                    return m
                }
            }
            return NSAttributedString(string: item.text ?? "")
        case .color:
            return NSAttributedString(string: item.metadata["colorHex"] ?? (item.text ?? ""))
        }
    }
    private func htmlAggregate(for items: [ClipItem]) -> String {
        var parts: [String] = []
        for it in items { parts.append(htmlSegment(of: it)) }
        let body = parts.joined(separator: "<br><br>")
        return "<html><body>\(body)</body></html>"
    }
    private func htmlSegment(of item: ClipItem) -> String {
        switch item.type {
        case .text:
            let s = plainText(of: item)
            return escapeHTML(s).replacingOccurrences(of: "\n", with: "<br>")
        case .link:
            let urlString = item.contentRef?.absoluteString ?? (item.metadata["url"] ?? (item.text ?? ""))
            let e = escapeHTML(urlString)
            return "<a href=\"\(e)\">\(e)</a>"
        case .image:
            if let u = item.contentRef, let d = try? Data(contentsOf: u) {
                let mime = mimeType(for: u) ?? "image/png"
                let b64 = d.base64EncodedString()
                let size = imagePixelSize(from: d)
                var dim = ""
                if let s = size { dim = " width=\"\(s.0)\" height=\"\(s.1)\" style=\"width: \(s.0)px; height: \(s.1)px; max-width: none;\"" }
                var html = "<img src=\"data:\(mime);base64,\(b64)\"\(dim)/>"
                if let t = item.text, !t.isEmpty { html += "<br>\(escapeHTML(t))" }
                return html
            }
            return escapeHTML(item.text ?? "")
        case .file:
            if let u = item.contentRef {
                if let t = UTType(filenameExtension: u.pathExtension.lowercased()), t.conforms(to: .image), let d = try? Data(contentsOf: u) {
                    let mime = mimeType(for: u) ?? "image/png"
                    let b64 = d.base64EncodedString()
                    let size = imagePixelSize(from: d)
                    var dim = ""
                    if let s = size { dim = " width=\"\(s.0)\" height=\"\(s.1)\" style=\"width: \(s.0)px; height: \(s.1)px; max-width: none;\"" }
                    var html = "<img src=\"data:\(mime);base64,\(b64)\"\(dim)/>"
                    let caption = item.text ?? u.lastPathComponent
                    if !caption.isEmpty { html += "<br>\(escapeHTML(caption))" }
                    return html
                }
                let name = escapeHTML(u.lastPathComponent)
                let href = escapeHTML(u.absoluteString)
                return "<div>\(name)</div><a href=\"\(href)\">\(href)</a>"
            }
            return escapeHTML(item.text ?? "")
        case .color:
            let s = item.metadata["colorHex"] ?? (item.text ?? "")
            return escapeHTML(s)
        }
    }
    private func escapeHTML(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "&", with: "&amp;")
        r = r.replacingOccurrences(of: "<", with: "&lt;")
        r = r.replacingOccurrences(of: ">", with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        r = r.replacingOccurrences(of: "'", with: "&#39;")
        return r
    }
    private func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, let t = UTType(filenameExtension: ext) else { return nil }
        if t.conforms(to: .png) { return "image/png" }
        if t.conforms(to: .jpeg) { return "image/jpeg" }
        if t.conforms(to: .gif) { return "image/gif" }
        if t.conforms(to: .tiff) { return "image/tiff" }
        return nil
    }
    private func imagePixelSize(from data: Data) -> (Int, Int)? {
        if let rep = NSBitmapImageRep(data: data) { return (rep.pixelsWide, rep.pixelsHigh) }
        if let img = NSImage(data: data), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { return (rep.pixelsWide, rep.pixelsHigh) }
        return nil
    }
    private func plainText(of item: ClipItem) -> String {
        switch item.type {
        case .text:
            if let rich = item.metadata["rich"] {
                if rich == "rtf" {
                    if item.metadata["plainSource"] == "pb" { return item.text ?? "" }
                    if let u = item.contentRef, let a = try? NSAttributedString(url: u, options: [:], documentAttributes: nil) { return a.string }
                    return item.text ?? ""
                } else if rich == "html" {
                    if let u = item.contentRef, let d = try? Data(contentsOf: u), let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) { return a.string }
                    return item.text ?? ""
                }
            }
            if let u = item.contentRef {
                if let a = try? NSAttributedString(url: u, options: [:], documentAttributes: nil) { return a.string }
                if let s = try? String(contentsOf: u) { return s }
            }
            return item.text ?? ""
        case .link:
            if let u = item.contentRef { return u.absoluteString }
            return item.metadata["url"] ?? (item.text ?? "")
        case .image:
            return item.text ?? ""
        case .file:
            return item.text ?? (item.contentRef?.lastPathComponent ?? "")
        case .color:
            return item.metadata["colorHex"] ?? (item.text ?? "")
        }
    }
    func deleteSelected() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        ids.forEach { id in try? store.delete(id) }
        if let sel = selectedItemID, selectedIDs.contains(sel) { selectedItemID = nil }
        selectedIDs.removeAll()
        selectionMode = false
        refresh()
        panel.showToast(L("toast.deleted"))
    }
    func addSelectedToBoard(_ boardID: UUID) {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        ids.forEach { id in try? store.pin(id, to: boardID) }
        refresh()
        panel.showToast(L("toast.addedToBoard"))
        clearSelection()
    }
    func clearSelection() {
        selectedIDs.removeAll()
        selectedOrder.removeAll()
        selectionMode = false
    }
    func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode { selectedIDs.removeAll(); selectedOrder.removeAll() }
    }
    func onItemTapped(_ item: ClipItem) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if selectionMode {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id); selectedOrder.removeAll(where: { $0 == item.id }) } else { selectedIDs.insert(item.id); if !selectedOrder.contains(item.id) { selectedOrder.append(item.id) } }
            selectionAnchorID = item.id
            return
        }
        if flags.contains(.command) {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id); selectedOrder.removeAll(where: { $0 == item.id }) } else { selectedIDs.insert(item.id); if !selectedOrder.contains(item.id) { selectedOrder.append(item.id) } }
            selectionAnchorID = item.id
            return
        }
        if flags.contains(.shift) {
            guard let anchor = selectionAnchorID ?? selectedItemID, let aIdx = items.firstIndex(where: { $0.id == anchor }), let bIdx = items.firstIndex(where: { $0.id == item.id }) else {
                selectedIDs.insert(item.id); if !selectedOrder.contains(item.id) { selectedOrder.append(item.id) }
                selectionAnchorID = item.id
                return
            }
            let step = (aIdx <= bIdx) ? 1 : -1
            var i = aIdx
            while true {
                let id = items[i].id
                if !selectedIDs.contains(id) { selectedIDs.insert(id) }
                if !selectedOrder.contains(id) { selectedOrder.append(id) }
                if i == bIdx { break }
                i += step
            }
            return
        }
        selectionByKeyboard = false
        selectedItemID = item.id
        selectedIDs.removeAll()
        selectedOrder.removeAll()
        selectionAnchorID = item.id
    }

    func confirmDeleteSelected() {
        let count = selectedIDs.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确定删除所选项？"
        alert.informativeText = "这将删除 \(count) 项，操作不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            deleteSelected()
        }
    }
    func addToBoard(_ item: ClipItem, _ boardID: UUID) {
        try? store.pin(item.id, to: boardID)
        refresh()
        panel.showToast(L("toast.addedToBoard"))
    }
    func deleteItem(_ item: ClipItem) {
        try? store.delete(item.id)
        if selectedItemID == item.id { selectedItemID = nil }
        refresh()
        panel.showToast(L("toast.deleted"))
    }
    func renameItem(_ item: ClipItem, name: String) {
        var updated = item
        updated.name = name
        try? store.save(updated)
        refresh()
    }
    func selectBoard(_ id: UUID) {
        selectedBoardID = id
        refresh()
    }
    func selectItem(_ item: ClipItem) {
        selectionByKeyboard = false
        selectedItemID = item.id
    }
    private func selectFirstItemIfNeeded() {
        if selectedItemID == nil { selectedItemID = items.first?.id }
    }
    private func currentIndex() -> Int? {
        guard let id = selectedItemID, let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        return idx
    }
    private func setIndex(_ idx: Int) {
        guard !items.isEmpty else { return }
        let clamped = max(0, min(items.count - 1, idx))
        selectedItemID = items[clamped].id
    }
    private func layoutStyle() -> HistoryLayoutStyle {
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        return HistoryLayoutStyle(rawValue: raw) ?? .horizontal
    }
    private func estimatedGridColumns() -> Int {
        let width = panel.contentWidth()
        let divider: CGFloat = 8
        let horizontalPadding: CGFloat = 24
        let cardWidth: CGFloat = 240
        let spacing: CGFloat = 12
        let contentArea = max(0, width - sidebarWidth - divider)
        let available = max(0, contentArea - horizontalPadding)
        let cols = Int(floor((available + spacing) / (cardWidth + spacing)))
        return max(1, cols)
    }
    private func moveSelectionLeft() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - 1)
        } else {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - 1)
        }
    }
    private func moveSelectionRight() {
        guard !items.isEmpty else { return }
        let idx = currentIndex() ?? 0
        selectionByKeyboard = true
        setIndex(idx + 1)
    }
    private func moveSelectionUp() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let cols = estimatedGridColumns()
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - cols)
        } else if layoutStyle() == .vertical {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - 1)
        }
    }
    private func moveSelectionDown() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let cols = estimatedGridColumns()
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx + cols)
        } else if layoutStyle() == .vertical {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx + 1)
        }
    }
    private func confirmSelectionAndPaste() {
        if let id = selectedItemID, let item = items.first(where: { $0.id == id }) {
            pasteItem(item, plain: false)
        } else if let first = items.first {
            pasteItem(first, plain: false)
        }
    }
}
