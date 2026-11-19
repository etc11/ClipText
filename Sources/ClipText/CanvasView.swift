import AppKit
import SwiftUI

struct DropSurface: NSViewRepresentable {
    let receive: (NSPasteboard) -> Bool
    func makeNSView(context: Context) -> ImageDropView {
        let view = ImageDropView()
        view.receive = receive
        return view
    }
    func updateNSView(_ nsView: ImageDropView, context: Context) { nsView.receive = receive }
}

final class ImageDropView: NSView {
    var receive: ((NSPasteboard) -> Bool)?
    var clicked: (() -> Void)?
    private var hovering = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .tiff, .png])
        setAccessibilityLabel("Drop an image to extract text")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { clicked?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovering = true
        needsDisplay = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false
        needsDisplay = true
        return receive?(sender.draggingPasteboard) ?? false
    }
    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
    }
}
