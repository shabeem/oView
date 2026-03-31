import AppKit

final class SelectionOverlayWindow: NSWindow {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    private let selectionView: SelectionOverlayView

    init(screen: NSScreen) {
        selectionView = SelectionOverlayView(frame: screen.frame)

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView

        selectionView.onSelectionComplete = { [weak self] rect in
            self?.handleSelection(rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.handleCancel()
        }
    }

    func show() {
        makeKeyAndOrderFront(nil)
        // Use CGAssociateMouseAndMouseCursorPosition to ensure proper tracking
        NSCursor.crosshair.push()
    }

    private func handleSelection(_ rect: CGRect) {
        NSCursor.pop()
        orderOut(nil)

        guard let screen = screen else { return }
        let screenFrame = screen.frame

        // The view uses flipped coords (top-left origin) which matches Quartz display coords.
        // Convert view-local coords to global Quartz coords (top-left origin system).
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let quartzScreenY = mainScreenHeight - (screenFrame.origin.y + screenFrame.height)

        let quartzRect = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: quartzScreenY + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        onRegionSelected?(quartzRect)
    }

    private func handleCancel() {
        NSCursor.pop()
        orderOut(nil)
        onCancelled?()
    }
}

// MARK: - Selection View

private final class SelectionOverlayView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var selectionStart: NSPoint?
    private var selectionRect: CGRect?
    private let overlayColor = NSColor.black.withAlphaComponent(0.35)
    private let selectionBorderColor = NSColor.white.withAlphaComponent(0.8)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        // Draw semi-transparent overlay
        overlayColor.setFill()
        bounds.fill()

        // Cut out the selection rectangle
        if let rect = selectionRect, rect.width > 5, rect.height > 5 {
            // Clear the selection area
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            // Draw selection border
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2
            selectionBorderColor.setStroke()
            borderPath.stroke()

            // Draw dashed inner border
            let dashPath = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            dashPath.lineWidth = 1
            dashPath.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.5).setStroke()
            dashPath.stroke()

            // Draw size label
            let sizeText = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.6)
            ]
            let textSize = sizeText.size(withAttributes: attrs)
            let textPoint = NSPoint(
                x: rect.maxX - textSize.width - 6,
                y: rect.maxY + 4
            )
            sizeText.draw(at: textPoint, withAttributes: attrs)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionStart = point
        selectionRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = selectionStart else { return }
        let current = convert(event.locationInWindow, from: nil)

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)

        selectionRect = CGRect(x: x, y: y, width: w, height: h)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect, rect.width > 10, rect.height > 10 else {
            selectionStart = nil
            selectionRect = nil
            needsDisplay = true
            return
        }
        onSelectionComplete?(rect)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
