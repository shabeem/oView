import AppKit

final class OOverlayWindow: NSWindow {
    let contentViewInstance: OContentView

    init(width: CGFloat, height: CGFloat) {
        let frame = NSRect(x: 100, y: 100, width: width, height: height)
        contentViewInstance = OContentView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isReleasedWhenClosed = false

        contentView = contentViewInstance
    }

    convenience init(size: CGFloat) {
        self.init(width: size, height: size)
    }

    func resize(to newSize: CGFloat) {
        resize(toWidth: newSize, height: newSize)
    }

    func resize(toWidth newWidth: CGFloat, height newHeight: CGFloat) {
        let w = min(max(newWidth, 80), 800)
        let h = min(max(newHeight, 80), 800)
        let currentCenter = NSPoint(x: frame.midX, y: frame.midY)
        let newOrigin = NSPoint(x: currentCenter.x - w / 2, y: currentCenter.y - h / 2)
        let newFrame = NSRect(x: newOrigin.x, y: newOrigin.y, width: w, height: h)
        setFrame(newFrame, display: true, animate: true)
        contentViewInstance.frame = NSRect(origin: .zero, size: NSSize(width: w, height: h))
        contentViewInstance.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
