import AppKit
import SwiftUI
import ApplicationServices
import Carbon
import Carbon.HIToolbox

// 面板窗口控制器：创建半透明浮层窗口并处理显示/隐藏与定位
public final class PanelWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var window: NSWindow?
    private var rootView: AnyView?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var effectView: NSVisualEffectView?
    private var toastWindow: NSWindow?
    private var imeField: NSTextField?
    private var previousFrontApp: NSRunningApplication?
    private var searchOverlayWindow: NSPanel?
    private var searchOverlayField: NSTextField?
    private var searchOverlayRect: CGRect?
    private var inputBuffer: String = ""
    public var previewService: PreviewService?
    private var previewAnchorRect: NSRect?
    public var onQueryUpdate: ((String) -> Void)?
    public var onSearchOverlayVisibleChanged: ((Bool) -> Void)?
    public var onShowSearchPopover: ((String?) -> Void)?
    public var onHideSearchPopover: (() -> Void)?
    public var onArrowLeft: (() -> Void)?
    public var onArrowRight: (() -> Void)?
    public var onArrowUp: (() -> Void)?
    public var onArrowDown: (() -> Void)?
    public var onEnter: (() -> Void)?
    public var onSpace: (() -> Void)?
    public var onShown: (() -> Void)?
    private var isSearchActive: Bool = false
    public func setSearchActive(_ active: Bool) {
        isSearchActive = active
        if !active {
            clearIMEFocus()
            window?.makeFirstResponder(nil)
        }
    }
    public func updateSearchOverlayRect(_ rect: CGRect) { searchOverlayRect = rect }
    public func updatePreviewAnchorRect(_ rect: NSRect?) { previewAnchorRect = rect }
    public override init() { super.init() }
    private func targetWidth() -> CGFloat {
        let s = activeScreen() ?? NSScreen.main
        guard let screen = s else { return 960 }
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        let style = HistoryLayoutStyle(rawValue: raw) ?? .horizontal
        switch style {
        case .horizontal:
            return min(screen.visibleFrame.width * 0.9, 2048)
        case .vertical:
            return 460
        case .grid:
            return min(screen.visibleFrame.width * 0.8, 2048)
        }
    }
    private func targetHeight() -> CGFloat {
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        let style = HistoryLayoutStyle(rawValue: raw) ?? .horizontal
        switch style {
        case .horizontal:
            return 260
        case .grid:
            let s = activeScreen() ?? NSScreen.main
            let h = s?.visibleFrame.height ?? 720
            return min(h * 0.8, 2048)
        case .vertical:
            let s = activeScreen() ?? NSScreen.main
            let h = s?.visibleFrame.height ?? 720
            return min(h * 0.9, 2048)
        }
    }
    private func targetOrigin(for size: NSSize) -> NSPoint {
        let s = activeScreen() ?? NSScreen.main
        guard let screen = s else { return NSPoint(x: 0, y: 0) }
        let f = screen.visibleFrame
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        let style = HistoryLayoutStyle(rawValue: raw) ?? .horizontal
        let vPercent = UserDefaults.standard.object(forKey: "panelPositionVertical") as? Double ?? 0
        let hPercent = UserDefaults.standard.object(forKey: "panelPositionHorizontal") as? Double ?? 0
        let vNorm = max(-100, min(100, vPercent)) / 100.0
        let hNorm = max(-100, min(100, hPercent)) / 100.0
        switch style {
        case .horizontal:
            let x = f.midX - (size.width / 2)
            let baseY = f.midY - (size.height / 2)
            let travelY = (f.height - size.height) / 2
            let y = baseY + (travelY * vNorm)
            return NSPoint(x: x, y: y)
        case .vertical:
            let y = f.midY - (size.height / 2)
            let baseX = f.midX - (size.width / 2)
            let travelX = (f.width - size.width) / 2
            let x = baseX + (travelX * hNorm)
            return NSPoint(x: x, y: y)
        case .grid:
            let x = f.midX - (size.width / 2)
            let y = f.midY - (size.height / 2)
            return NSPoint(x: x, y: y)
        }
    }
    // 设置 SwiftUI 根视图
    public func setRoot<V: View>(_ view: V) { rootView = AnyView(view) }
    public func show() {
        guard let rootView = rootView else { return }
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: targetWidth(), height: targetHeight()), styleMask: [.utilityWindow], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.level = .statusBar
            w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            w.isMovableByWindowBackground = false
            w.isFloatingPanel = true
            w.becomesKeyOnlyIfNeeded = true
            // HUD 材质效果与圆角
            let ev = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: targetWidth(), height: targetHeight()))
            ev.material = .popover
            ev.blendingMode = .behindWindow
            ev.state = .active
            ev.wantsLayer = true
            ev.layer?.cornerRadius = 16
            ev.layer?.masksToBounds = true
            // 使用 NSHostingView 承载 SwiftUI 内容
            let hosting = NSHostingView(rootView: rootView)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            ev.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: ev.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: ev.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: ev.bottomAnchor)
            ])
            w.contentView = ev
            effectView = ev
            w.backgroundColor = .clear
            w.hasShadow = false
            w.delegate = self
            window = w
        } else {
            let width = targetWidth()
            window?.setContentSize(NSSize(width: width, height: targetHeight()))
        }
        let size = NSSize(width: targetWidth(), height: targetHeight())
        let origin = targetOrigin(for: size)
        if let w = window {
            previousFrontApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            let finalFrame = NSRect(origin: origin, size: size)
            let scale: CGFloat = 0.96
            let initSize = NSSize(width: finalFrame.size.width * scale, height: finalFrame.size.height * scale)
            var initOrigin = finalFrame.origin
            initOrigin.x += (finalFrame.size.width - initSize.width) / 2
            initOrigin.y += (finalFrame.size.height - initSize.height) / 2
            effectView?.alphaValue = 0
            w.setFrame(NSRect(origin: initOrigin, size: initSize), display: false)
            w.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                (w.animator()).setFrame(finalFrame, display: true)
                effectView?.animator().alphaValue = 1
            }
            if let ev = effectView { w.invalidateCursorRects(for: ev) }
            NSCursor.arrow.set()
            DispatchQueue.main.async { NSCursor.arrow.set() }
        } else {
            previousFrontApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            if let w = window, let ev = effectView { w.invalidateCursorRects(for: ev) }
            NSCursor.arrow.set()
            DispatchQueue.main.async { NSCursor.arrow.set() }
        }
        inputBuffer = ""
        onQueryUpdate?("")
        // 安装失焦与外部点击自动隐藏行为
        installHidingBehavior()
        installKeyMonitor()
        imeField?.stringValue = ""
        onShown?()
    }
    public func hide(animated: Bool = true) {
        previewService?.close()
        guard let w = window else { return }
        if !animated {
            w.orderOut(nil)
            return
        }
        let finalFrame = w.frame
        let scale: CGFloat = 0.96
        let targetSize = NSSize(width: finalFrame.size.width * scale, height: finalFrame.size.height * scale)
        var targetOrigin = finalFrame.origin
        targetOrigin.x += (finalFrame.size.width - targetSize.width) / 2
        targetOrigin.y += (finalFrame.size.height - targetSize.height) / 2
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            (w.animator()).setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
            effectView?.animator().alphaValue = 0
        } completionHandler: {
            w.orderOut(nil)
            let prev = self.previousFrontApp
            self.previousFrontApp = nil
            if let app = prev, app.processIdentifier != NSRunningApplication.current.processIdentifier {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
        inputBuffer = ""
        onQueryUpdate?("")
        uninstallKeyMonitor()
        imeField?.stringValue = ""
        clearIMEFocus()
        searchOverlayWindow?.orderOut(nil)
        searchOverlayWindow = nil
        onSearchOverlayVisibleChanged?(false)
    }
    public func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }
    public func updateLayoutHeight(animated: Bool = true) {
        guard let w = window else { return }
        let newW = targetWidth()
        let newH = targetHeight()
        let newSize = NSSize(width: newW, height: newH)
        let newOrigin = targetOrigin(for: newSize)
        var f = NSRect(origin: newOrigin, size: newSize)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                (w.animator()).setFrame(f, display: true)
                effectView?.animator().setFrameSize(NSSize(width: f.size.width, height: newH))
            }
        } else {
            w.setFrame(f, display: true, animate: false)
            effectView?.setFrameSize(NSSize(width: f.size.width, height: newH))
        }
    }
    
    private func positionCenter() {
        guard let w = window else { return }
        let s = activeScreen() ?? NSScreen.main
        guard let screen = s else { return }
        let f = screen.visibleFrame
        let x = f.midX - (w.frame.width / 2)
        let y = f.midY - (w.frame.height / 2)
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activeScreen() -> NSScreen? {
        let p = NSEvent.mouseLocation
        for s in NSScreen.screens {
            if s.frame.contains(p) { return s }
        }
        return nil
    }
    private func installHidingBehavior() {
        if outsideClickMonitor == nil {
            // 全局监听鼠标点击以便面板自动隐藏
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self else { return }
                let p = NSEvent.mouseLocation
                if let w = self.window, w.isVisible, w.frame.contains(p) { return }
                if let pf = self.previewService?.windowFrame(), pf.contains(p) { return }
                if self.window?.isVisible == true { self.hide() }
            }
        }
        // 键盘事件通过本地监控处理
        // 应用失活时隐藏面板
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }
    private func installKeyMonitor() {
        uninstallKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self = self else { return ev }
            if self.window?.isVisible != true { return ev }
            if ev.type == .keyDown {
                let keycode = ev.keyCode
                if keycode == 57 || keycode == 102 || keycode == 104 { return ev }
                if keycode == 49 {
                    if self.isFirstResponderTextInput() || self.isAnyTextInputActive() || self.isSearchActive { return ev }
                    self.onSpace?()
                    return nil
                }
                if keycode == 53 {
                    if self.isSearchActive { self.onHideSearchPopover?(); self.clearIMEFocus(); return nil }
                    if self.previewService?.isVisible() == true { self.previewService?.close(); return nil }
                    self.hide();
                    return nil
                }
                let flags = ev.modifierFlags
                if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) { return ev }
                if !self.isFirstResponderTextInput() && !self.isAnyTextInputActive() {
                    if keycode == 123 { self.onArrowLeft?(); return nil }
                    if keycode == 124 { self.onArrowRight?(); return nil }
                    if keycode == 126 { self.onArrowUp?(); return nil }
                    if keycode == 125 { self.onArrowDown?(); return nil }
                    if keycode == 36 || keycode == 76 { self.onEnter?(); return nil }
                }
                if self.isFirstResponderTextInput() { return ev }
                if self.isAnyTextInputActive() { return ev }
                if let s = ev.charactersIgnoringModifiers, !s.isEmpty {
                    if self.isSearchActive {
                        return ev
                    } else {
                        self.onShowSearchPopover?(nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                            NSApp.postEvent(ev, atStart: false)
                        }
                        return nil
                    }
                }
                return ev
            }
            return ev
        }
    }
    public func contentWidth() -> CGFloat {
        if let w = window { return w.frame.size.width }
        return targetWidth()
    }
    private func showSearchOverlay() {
        guard let rect = searchOverlayRect else { return }
        let size = NSSize(width: rect.size.width, height: 32)
        let w = NSPanel(contentRect: NSRect(x: rect.origin.x, y: rect.origin.y - (32 - rect.size.height)/2, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.level = .statusBar
        w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        w.backgroundColor = .clear
        w.hasShadow = false
        let ev = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        ev.material = .hudWindow
        ev.blendingMode = .withinWindow
        ev.state = .active
        ev.wantsLayer = true
        ev.layer?.cornerRadius = 16
        ev.layer?.masksToBounds = true
        let tf = NSTextField(frame: NSRect(x: 28, y: 6, width: size.width - 40, height: 20))
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.delegate = self
        ev.addSubview(tf)
        let icon = NSImageView(frame: NSRect(x: 10, y: 8, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        ev.addSubview(icon)
        w.contentView = ev
        searchOverlayField = tf
        searchOverlayWindow?.orderOut(nil)
        searchOverlayWindow = w
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        w.makeFirstResponder(tf)
        onSearchOverlayVisibleChanged?(true)
    }
    private func isFirstResponderTextInput() -> Bool {
        guard let w = window else { return false }
        if let r = w.firstResponder {
            if r is NSTextView || r is NSTextField { return true }
            if let clz = object_getClass(r) {
                let name = NSStringFromClass(clz)
                if name.contains("NSTextView") || name.contains("NSTextField") { return true }
            }
        }
        return false
    }
    private func isAnyTextInputActive() -> Bool {
        for w in NSApp.windows {
            if !w.isVisible { continue }
            if !w.isKeyWindow { continue }
            if let r = w.firstResponder {
                if r is NSTextView || r is NSTextField { return true }
                let name = NSStringFromClass(type(of: r))
                if name.contains("NSTextView") || name.contains("NSTextField") { return true }
            }
        }
        return false
    }
    private func uninstallKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
    private func prepareIMEField() {
        guard let ev = effectView else { return }
        if imeField == nil {
            let tf = NSTextField(frame: NSRect(x: 4, y: 4, width: 1, height: 22))
            tf.isBordered = false
            tf.isBezeled = false
            tf.drawsBackground = false
            tf.font = NSFont.systemFont(ofSize: 13)
            tf.delegate = self
            tf.alphaValue = 0.01
            ev.addSubview(tf)
            imeField = tf
        }
    }
    private func clearIMEFocus() {
        guard let w = window else { return }
        if let tf = imeField, w.firstResponder === tf {
            w.makeFirstResponder(nil)
        }
    }
    public func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf == imeField {
            inputBuffer = tf.stringValue
            onQueryUpdate?(inputBuffer)
        }
    }
    private static func isIMEActive() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        if let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
            let id = unsafeBitCast(idPtr, to: CFString.self) as String
            return id.contains(".inputmethod.")
        }
        return false
    }
    @objc private func appDidResignActive() { hide() }
    public func windowDidResignKey(_ notification: Notification) { hide() }
    public func showToast(_ text: String, duration: TimeInterval = 1.6) {
        toastWindow?.orderOut(nil)
        toastWindow = nil
        let size = NSSize(width: 180, height: 180)
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isOpaque = false
        w.level = .statusBar
        w.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.hasShadow = false
        let ev = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        ev.material = .popover
        ev.blendingMode = .withinWindow
        ev.state = .active
        ev.wantsLayer = true
        ev.layer?.cornerRadius = 18
        ev.layer?.masksToBounds = true
        let v = AnyView(
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let hosting = NSHostingView(rootView: v)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        ev.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: ev.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: ev.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: ev.bottomAnchor)
        ])
        w.contentView = ev
        if let s = activeScreen() ?? NSScreen.main {
            let f = s.visibleFrame
            let x = f.midX - (size.width / 2)
            let y = f.midY - (size.height / 2)
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }
        toastWindow = w
        w.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.toastWindow?.orderOut(nil)
            self.toastWindow = nil
        }
    }
    public func showPreview(_ item: ClipItem) {
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        let style = HistoryLayoutStyle(rawValue: raw) ?? .horizontal
        switch style {
        case .horizontal:
            if let wf = window?.frame {
                let s = activeScreen() ?? NSScreen.main
                if let screen = s {
                    let f = screen.visibleFrame
                    let placement: PreviewService.PreviewPlacement = (wf.midY < f.midY) ? .topCenter : .bottomCenter
                    previewService?.show(item, anchorRect: wf, placement: placement)
                } else {
                    previewService?.show(item, anchorRect: wf, placement: .bottomCenter)
                }
            } else {
                previewService?.show(item, placement: .centerOnScreen)
            }
        case .vertical:
            if let wf = window?.frame {
                let s = activeScreen() ?? NSScreen.main
                if let screen = s {
                    let f = screen.visibleFrame
                    let placement: PreviewService.PreviewPlacement = (wf.midX < f.midX) ? .rightCenter : .leftCenter
                    previewService?.show(item, anchorRect: wf, placement: placement)
                } else {
                    previewService?.show(item, anchorRect: wf, placement: .rightCenter)
                }
            } else {
                previewService?.show(item, placement: .centerOnScreen)
            }
        case .grid:
            previewService?.show(item, placement: .centerOnScreen)
        }
    }
}
