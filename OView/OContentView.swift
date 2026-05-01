import AppKit
import CoreGraphics

enum OverlayShape {
    case circle
    case rectangle
}

protocol OContentViewDelegate: AnyObject {
    func contentViewRequestsResize(delta: CGFloat, from view: OContentView)
    func contentViewRequestsResize(dx: CGFloat, dy: CGFloat, from view: OContentView)
    func contentViewRequestsContextMenu(at point: NSPoint, from view: OContentView)
}

final class OContentView: NSView {
    weak var viewDelegate: OContentViewDelegate?

    private(set) var currentFrame: CGImage?
    private var videoOffset: CGPoint = .zero
    private var videoScale: CGFloat = 1.0
    var shape: OverlayShape = .circle {
        didSet { needsDisplay = true }
    }

    private let borderWidth: CGFloat = 3.0
    private let cornerRadius: CGFloat = 16.0
    private let borderGradientColors: [NSColor] = [
        NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.6, green: 0.3, blue: 1.0, alpha: 1.0)
    ]

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false
    }

    // MARK: - Public

    func updateFrame(_ frame: CGImage) {
        currentFrame = frame
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
        }
    }

    func resetTransforms() {
        videoOffset = .zero
        videoScale = 1.0
        needsDisplay = true
    }

    // MARK: - Shape Paths

    private func contentPath(in rect: CGRect) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rectangle:
            return CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        let contentRect = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        let clipPath = contentPath(in: contentRect)

        // Clear
        context.clear(bounds)

        // Shadow
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(clipPath)
        context.fillPath()
        context.restoreGState()

        // Clip to shape for video content
        context.saveGState()
        context.addPath(clipPath)
        context.clip()

        if let frame = currentFrame {
            drawVideoFrame(frame, in: context, contentRect: contentRect)
        } else {
            drawPlaceholder(in: context, rect: contentRect)
        }

        context.restoreGState()

        // Gradient border
        drawGradientBorder(in: context, bounds: bounds)
    }

    private func drawVideoFrame(_ frame: CGImage, in context: CGContext, contentRect: CGRect) {
        let imageWidth = CGFloat(frame.width)
        let imageHeight = CGFloat(frame.height)

        let scaleX = contentRect.width / imageWidth
        let scaleY = contentRect.height / imageHeight
        let fillScale = max(scaleX, scaleY) * videoScale

        let drawWidth = imageWidth * fillScale
        let drawHeight = imageHeight * fillScale
        let drawX = contentRect.midX - drawWidth / 2 + videoOffset.x
        let drawY = contentRect.midY - drawHeight / 2 + videoOffset.y

        let drawRect = CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)
        context.draw(frame, in: drawRect)
    }

    private func drawPlaceholder(in context: CGContext, rect: CGRect) {
        context.setFillColor(NSColor(white: 0.12, alpha: 1.0).cgColor)
        context.fill(rect)

        let text = "Click menu icon\nto capture a window" as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(rect.width * 0.08, 11), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle
        ]
        let textSize = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], attributes: attrs).size
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        NSGraphicsContext.current?.saveGraphicsState()
        text.draw(in: textRect, withAttributes: attrs)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawGradientBorder(in context: CGContext, bounds: CGRect) {
        let outerPath = contentPath(in: bounds)
        let innerRect = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        let innerPath = contentPath(in: innerRect)

        context.saveGState()
        context.addPath(outerPath)
        context.addPath(innerPath)
        context.clip(using: .evenOdd)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = borderGradientColors.map { $0.cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bounds.minX, y: bounds.maxY),
                end: CGPoint(x: bounds.maxX, y: bounds.minY),
                options: []
            )
        }
        context.restoreGState()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        switch shape {
        case .circle:
            let center = NSPoint(x: bounds.width / 2, y: bounds.height / 2)
            let dx = localPoint.x - center.x
            let dy = localPoint.y - center.y
            let radius = min(bounds.width, bounds.height) / 2
            if (dx * dx + dy * dy) <= (radius * radius) {
                return super.hitTest(point)
            }
            return nil
        case .rectangle:
            if bounds.contains(localPoint) {
                return super.hitTest(point)
            }
            return nil
        }
    }

    // MARK: - Events

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            // Option + scroll → resize the window
            let delta = event.scrollingDeltaY
            viewDelegate?.contentViewRequestsResize(delta: delta, from: self)
        } else {
            // Scroll → zoom video in/out
            let delta = event.scrollingDeltaY * 0.02
            videoScale = max(0.3, min(8.0, videoScale + delta))
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        videoScale = max(0.3, min(8.0, videoScale + event.magnification))
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        viewDelegate?.contentViewRequestsContextMenu(at: event.locationInWindow, from: self)
    }

    // MARK: - Edge Resize Detection

    private let resizeEdgeThreshold: CGFloat = 20.0

    private func isNearEdge(_ point: NSPoint) -> Bool {
        let b = bounds
        let t = resizeEdgeThreshold

        switch shape {
        case .circle:
            let cx = b.width / 2
            let cy = b.height / 2
            let r = min(cx, cy)
            let dx = point.x - cx
            let dy = point.y - cy
            let dist = sqrt(dx * dx + dy * dy)
            // Near the circumference
            return dist > (r - t) && dist <= r
        case .rectangle:
            return point.x < t || point.x > b.width - t ||
                   point.y < t || point.y > b.height - t
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if isNearEdge(local) {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // Cmd + drag → pan video; Option + drag → resize; regular drag → move window
    override func mouseDown(with event: NSEvent) {
        let isPanMode = event.modifierFlags.contains(.command)
        let isResizeMode = event.modifierFlags.contains(.option)

        var lastScreenPoint = NSEvent.mouseLocation
        var keepTracking = true

        while keepTracking {
            guard let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            switch nextEvent.type {
            case .leftMouseDragged:
                let currentScreenPoint = NSEvent.mouseLocation
                let dx = currentScreenPoint.x - lastScreenPoint.x
                let dy = currentScreenPoint.y - lastScreenPoint.y

                if isPanMode {
                    // Move video inside the overlay
                    videoOffset.x += dx
                    videoOffset.y += dy
                    needsDisplay = true
                } else if isResizeMode {
                    // Option + drag → resize
                    if shape == .rectangle {
                        // Rectangle: independent width/height
                        viewDelegate?.contentViewRequestsResize(dx: dx, dy: -dy, from: self)
                    } else {
                        // Circle: uniform resize
                        let delta = abs(dx) > abs(dy) ? dx : -dy
                        viewDelegate?.contentViewRequestsResize(delta: delta, from: self)
                    }
                } else {
                    // Move the window itself
                    if let win = window {
                        var origin = win.frame.origin
                        origin.x += dx
                        origin.y += dy
                        win.setFrameOrigin(origin)
                    }
                }
                lastScreenPoint = currentScreenPoint
            case .leftMouseUp:
                keepTracking = false
            default:
                break
            }
        }
    }
}
