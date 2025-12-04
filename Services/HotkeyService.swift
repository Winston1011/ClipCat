import Carbon.HIToolbox
import AppKit

// 快捷键服务：注册并处理全局热键事件（打开面板/快速粘贴/栈切换）
public final class HotkeyService: HotkeyServiceProtocol {
    private var showPanelRef: EventHotKeyRef?
    private var quickRefs: [EventHotKeyRef?] = []
    private var stackToggleRef: EventHotKeyRef?
    public var onShowPanel: (() -> Void)?
    public var onQuickPaste: ((Int, Bool) -> Void)?
    public var onStackToggle: (() -> Void)?
    public init() {
        // 安装事件处理器，依据 HotKeyID 分派回调
        InstallEventHandler(GetApplicationEventTarget(), { handlerCallRef, eventRef, userData in
            let kind = GetEventKind(eventRef)
            if kind == UInt32(kEventHotKeyPressed) {
                var hotKeyID = EventHotKeyID()
                GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = Int(hotKeyID.id)
                if id == 1000 { HotkeyService.shared?.onShowPanel?() }
                if id >= 2000 && id < 2010 { HotkeyService.shared?.onQuickPaste?(id - 1999, false) }
                if id >= 3000 && id < 3010 { HotkeyService.shared?.onQuickPaste?(id - 2999, true) }
                if id == 4000 { HotkeyService.shared?.onStackToggle?() }
            }
            return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))], nil, nil)
        HotkeyService.shared = self
    }
    public static var shared: HotkeyService?
    public func registerShowPanel() {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x50415354)), id: 1000)
        let store = SettingsStore()
        let s = store.load().shortcuts.showPanel
        if let parsed = parseShortcut(s) {
            RegisterEventHotKey(parsed.key, parsed.mods, id, GetApplicationEventTarget(), 0, &ref)
        } else {
            RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref)
        }
        showPanelRef = ref
    }
    public func registerQuickPasteSlots() {
        quickRefs.removeAll()
        for n in 1...9 {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x50415354)), id: UInt32(2000 + n - 1))
            RegisterEventHotKey(UInt32(kVK_ANSI_1 + n - 1), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &ref)
            quickRefs.append(ref)
            var sref: EventHotKeyRef?
            let sid = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x50415354)), id: UInt32(3000 + n - 1))
            RegisterEventHotKey(UInt32(kVK_ANSI_1 + n - 1), UInt32(cmdKey | shiftKey), sid, GetApplicationEventTarget(), 0, &sref)
            quickRefs.append(sref)
        }
    }
    public func registerStackToggle() {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x50415354)), id: 4000)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref)
        stackToggleRef = ref
    }
    public func unregisterAll() {
        if let r = showPanelRef { UnregisterEventHotKey(r) }
        for r in quickRefs { if let r = r { UnregisterEventHotKey(r) } }
        if let r = stackToggleRef { UnregisterEventHotKey(r) }
    }
    private func parseShortcut(_ s: String) -> (key: UInt32, mods: UInt32)? {
        let parts = s.lowercased().split(separator: "+").map { String($0) }
        var mods: UInt32 = 0
        var key: UInt32 = 0
        for p in parts {
            if p == "shift" { mods |= UInt32(shiftKey) }
            else if p == "cmd" || p == "command" { mods |= UInt32(cmdKey) }
            else if p == "ctrl" || p == "control" { mods |= UInt32(controlKey) }
            else if p == "alt" || p == "option" { mods |= UInt32(optionKey) }
            else if let kc = keyCode(for: p) { key = UInt32(kc) }
        }
        if key == 0 { return nil }
        return (key, mods)
    }
    private func keyCode(for name: String) -> UInt16? {
        switch name {
        case "a": return UInt16(kVK_ANSI_A)
        case "b": return UInt16(kVK_ANSI_B)
        case "c": return UInt16(kVK_ANSI_C)
        case "d": return UInt16(kVK_ANSI_D)
        case "e": return UInt16(kVK_ANSI_E)
        case "f": return UInt16(kVK_ANSI_F)
        case "g": return UInt16(kVK_ANSI_G)
        case "h": return UInt16(kVK_ANSI_H)
        case "i": return UInt16(kVK_ANSI_I)
        case "j": return UInt16(kVK_ANSI_J)
        case "k": return UInt16(kVK_ANSI_K)
        case "l": return UInt16(kVK_ANSI_L)
        case "m": return UInt16(kVK_ANSI_M)
        case "n": return UInt16(kVK_ANSI_N)
        case "o": return UInt16(kVK_ANSI_O)
        case "p": return UInt16(kVK_ANSI_P)
        case "q": return UInt16(kVK_ANSI_Q)
        case "r": return UInt16(kVK_ANSI_R)
        case "s": return UInt16(kVK_ANSI_S)
        case "t": return UInt16(kVK_ANSI_T)
        case "u": return UInt16(kVK_ANSI_U)
        case "v": return UInt16(kVK_ANSI_V)
        case "w": return UInt16(kVK_ANSI_W)
        case "x": return UInt16(kVK_ANSI_X)
        case "y": return UInt16(kVK_ANSI_Y)
        case "z": return UInt16(kVK_ANSI_Z)
        case "0": return UInt16(kVK_ANSI_0)
        case "1": return UInt16(kVK_ANSI_1)
        case "2": return UInt16(kVK_ANSI_2)
        case "3": return UInt16(kVK_ANSI_3)
        case "4": return UInt16(kVK_ANSI_4)
        case "5": return UInt16(kVK_ANSI_5)
        case "6": return UInt16(kVK_ANSI_6)
        case "7": return UInt16(kVK_ANSI_7)
        case "8": return UInt16(kVK_ANSI_8)
        case "9": return UInt16(kVK_ANSI_9)
        case "return": return UInt16(kVK_Return)
        default: return nil
        }
    }
}
