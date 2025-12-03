import AppKit
import SwiftUI

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class DragHandleView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}