import SwiftUI
import AppKit

struct ShortcutRecorder: NSViewRepresentable {
    typealias NSViewType = ShortcutCaptureView
    @Binding var shortcut: String
    init(shortcut: Binding<String>) { _shortcut = shortcut }
    func makeNSView(context: Context) -> ShortcutCaptureView {
        let v = ShortcutCaptureView()
        v.onShortcut = { s in shortcut = s }
        v.stringValue = shortcut
        v.isEditable = false
        v.isBordered = true
        v.alignment = .center
        v.font = .systemFont(ofSize: 13)
        return v
    }
    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) { nsView.stringValue = shortcut }
}

final class ShortcutCaptureView: NSTextField {
    var onShortcut: ((String) -> Void)?
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        let s = ShortcutCaptureView.stringify(event)
        onShortcut?(s)
        stringValue = s
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    static func stringify(_ event: NSEvent) -> String {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.command) { parts.append("cmd") }
        let key = keyName(for: event.keyCode)
        if !key.isEmpty { parts.append(key) }
        return parts.joined(separator: "+")
    }
    static func keyName(for code: UInt16) -> String {
        switch code {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 36: return "return"
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        default: return ""
        }
    }
}