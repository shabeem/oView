import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

// Global C function for Carbon hotkey callback
private func hotkeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    if hotKeyID.id == 1 {
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.hotkeyCapture()
        }
    }
    return noErr
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OOverlayWindow?
    private var captureEngine: ScreenCaptureEngine?
    private var currentWidth: CGFloat = 200
    private var currentHeight: CGFloat = 200
    private var currentShape: OverlayShape = .circle
    private var currentOpacity: CGFloat = 1.0
    private var frontPID: pid_t = 0

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerGlobalHotkey()
    }

    // MARK: - Global Hotkey (Ctrl+Shift+O) via Carbon — no Accessibility needed

    private var hotkeyRef: EventHotKeyRef?

    private func registerGlobalHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &eventType, nil, nil)

        // Ctrl+Shift+O
        var hotKeyID = EventHotKeyID(signature: OSType(0x4F565700), id: 1)
        let modifiers: UInt32 = UInt32(controlKey | shiftKey)
        let keyCode: UInt32 = 0x1F // kVK_ANSI_O

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    func hotkeyCapture() {
        // Get frontmost app at the moment of hotkey press
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            frontPID = frontApp.processIdentifier
        }
        if captureEngine?.isCapturing == true {
            stopCapture()
        } else {
            autoCaptureFrontWindow()
        }
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: "OView") {
                img.isTemplate = true
                button.image = img
                button.imagePosition = .imageOnly
            } else {
                // Fallback: plain text if SF Symbol unavailable
                button.title = "◉"
            }
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let captureItem = NSMenuItem(title: "Capture Current Window", action: #selector(captureCurrentWindow), keyEquivalent: "r")
        captureItem.target = self
        menu.addItem(captureItem)

        // Also keep option to pick manually
        let pickItem = NSMenuItem(title: "Pick Window…", action: #selector(refreshAndShowWindows), keyEquivalent: "")
        pickItem.target = self
        menu.addItem(pickItem)

        menu.addItem(NSMenuItem.separator())

        // Shape submenu
        let shapeItem = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        let shapeMenu = NSMenu()
        let circleItem = NSMenuItem(title: "⚪ Circle", action: #selector(setCircleShape), keyEquivalent: "")
        circleItem.target = self
        circleItem.state = currentShape == .circle ? .on : .off
        shapeMenu.addItem(circleItem)
        let rectItem = NSMenuItem(title: "▭ Rectangle", action: #selector(setRectShape), keyEquivalent: "")
        rectItem.target = self
        rectItem.state = currentShape == .rectangle ? .on : .off
        shapeMenu.addItem(rectItem)
        shapeItem.submenu = shapeMenu
        menu.addItem(shapeItem)

        // Size submenu
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        if currentShape == .circle {
            for size in [120, 160, 200, 250, 300, 400] {
                let item = NSMenuItem(title: "\(size) px", action: #selector(changeSize(_:)), keyEquivalent: "")
                item.tag = size
                item.target = self
                if CGFloat(size) == currentWidth { item.state = .on }
                sizeMenu.addItem(item)
            }
        } else {
            let widthItem = NSMenuItem(title: "Width", action: nil, keyEquivalent: "")
            let widthMenu = NSMenu()
            for w in [160, 200, 280, 360, 480, 600] {
                let item = NSMenuItem(title: "\(w) px", action: #selector(changeWidth(_:)), keyEquivalent: "")
                item.tag = w
                item.target = self
                if CGFloat(w) == currentWidth { item.state = .on }
                widthMenu.addItem(item)
            }
            widthItem.submenu = widthMenu
            sizeMenu.addItem(widthItem)

            let heightItem = NSMenuItem(title: "Height", action: nil, keyEquivalent: "")
            let heightMenu = NSMenu()
            for h in [120, 160, 200, 250, 300, 400] {
                let item = NSMenuItem(title: "\(h) px", action: #selector(changeHeight(_:)), keyEquivalent: "")
                item.tag = h
                item.target = self
                if CGFloat(h) == currentHeight { item.state = .on }
                heightMenu.addItem(item)
            }
            heightItem.submenu = heightMenu
            sizeMenu.addItem(heightItem)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Opacity submenu
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for pct in [100, 80, 60, 40, 20] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(changeOpacity(_:)), keyEquivalent: "")
            item.tag = pct
            item.target = self
            if Int(currentOpacity * 100) == pct { item.state = .on }
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop Capture", action: #selector(stopCapture), keyEquivalent: "s")
        stopItem.target = self
        menu.addItem(stopItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Shape

    @objc private func setCircleShape() {
        currentShape = .circle
        currentHeight = currentWidth
        overlayWindow?.contentViewInstance.shape = .circle
        overlayWindow?.resize(toWidth: currentWidth, height: currentHeight)
        rebuildMenu()
    }

    @objc private func setRectShape() {
        currentShape = .rectangle
        overlayWindow?.contentViewInstance.shape = .rectangle
        overlayWindow?.contentViewInstance.needsDisplay = true
        rebuildMenu()
    }

    // MARK: - Auto Capture Current Window

    @objc private func captureCurrentWindow() {
        autoCaptureFrontWindow()
    }

    private func autoCaptureFrontWindow() {
        ScreenCaptureEngine.getFrontmostWindow(pid: frontPID) { [weak self] window in
            guard let self else { return }
            if let window {
                self.beginCapture(of: window)
            } else {
                // Fallback: show window picker if auto-detect fails
                self.showWindowPicker()
            }
        }
    }

    // MARK: - Manual Window Picker (backup)

    @objc private func refreshAndShowWindows() {
        showWindowPicker()
    }

    private func showWindowPicker() {
        ScreenCaptureEngine.getAvailableWindows { [weak self] windows in
            guard let self else { return }
            let picker = NSMenu(title: "Select Window")

            if windows.isEmpty {
                let emptyItem = NSMenuItem(title: "No windows available", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                picker.addItem(emptyItem)
            } else {
                var appGroups: [(String, [CaptureableWindow])] = []
                var seen: Set<String> = []
                for w in windows {
                    if !seen.contains(w.appName) {
                        seen.insert(w.appName)
                        appGroups.append((w.appName, windows.filter { $0.appName == w.appName }))
                    }
                }
                for (appName, appWindows) in appGroups {
                    let headerItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
                    headerItem.isEnabled = false
                    headerItem.attributedTitle = NSAttributedString(
                        string: appName,
                        attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
                    )
                    picker.addItem(headerItem)
                    for window in appWindows {
                        let item = NSMenuItem(title: "    \(window.title)", action: #selector(self.selectWindow(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = window
                        picker.addItem(item)
                    }
                    picker.addItem(NSMenuItem.separator())
                }
            }

            if let button = self.statusItem.button {
                picker.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
        }
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let captureWindow = sender.representedObject as? CaptureableWindow else { return }
        beginCapture(of: captureWindow.window)
    }

    // MARK: - Capture

    private func beginCapture(of window: SCWindow) {
        captureEngine?.stopCapture()

        let overlay = OOverlayWindow(width: currentWidth, height: currentHeight)
        overlay.contentViewInstance.viewDelegate = self
        overlay.contentViewInstance.shape = currentShape
        overlay.alphaValue = currentOpacity
        overlayWindow = overlay

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - currentWidth - 30
            let y = screenFrame.minY + 30
            overlay.setFrameOrigin(NSPoint(x: x, y: y))
        }

        overlay.makeKeyAndOrderFront(nil)

        let engine = ScreenCaptureEngine()
        engine.delegate = self
        engine.startCapture(of: window)
        captureEngine = engine
    }

    // MARK: - Size & Opacity

    @objc private func changeSize(_ sender: NSMenuItem) {
        let newSize = CGFloat(sender.tag)
        currentWidth = newSize
        currentHeight = newSize
        if let sizeMenu = sender.menu {
            for item in sizeMenu.items { item.state = item.tag == sender.tag ? .on : .off }
        }
        overlayWindow?.resize(toWidth: newSize, height: newSize)
    }

    @objc private func changeWidth(_ sender: NSMenuItem) {
        currentWidth = CGFloat(sender.tag)
        if let menu = sender.menu {
            for item in menu.items { item.state = item.tag == sender.tag ? .on : .off }
        }
        overlayWindow?.resize(toWidth: currentWidth, height: currentHeight)
    }

    @objc private func changeHeight(_ sender: NSMenuItem) {
        currentHeight = CGFloat(sender.tag)
        if let menu = sender.menu {
            for item in menu.items { item.state = item.tag == sender.tag ? .on : .off }
        }
        overlayWindow?.resize(toWidth: currentWidth, height: currentHeight)
    }

    @objc private func changeOpacity(_ sender: NSMenuItem) {
        currentOpacity = CGFloat(sender.tag) / 100.0
        overlayWindow?.alphaValue = currentOpacity
        if let menu = sender.menu {
            for item in menu.items { item.state = item.tag == sender.tag ? .on : .off }
        }
        rebuildMenu()
    }

    @objc private func stopCapture() {
        captureEngine?.stopCapture()
        captureEngine = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    @objc private func quitApp() {
        stopCapture()
        NSApp.terminate(nil)
    }

    // MARK: - Permissions

    private func checkScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        if CGPreflightScreenCaptureAccess() {
            completion(true)
        } else {
            // Request access — this will prompt the user or return false if denied
            let granted = CGRequestScreenCaptureAccess()
            completion(granted)
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "OView needs Screen Recording access.\n\nGo to:\nSystem Settings → Privacy & Security → Screen Recording\n\nAnd enable OView.\n\nAfter enabling, you may need to quit and reopen OView."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Context Menu

    func showContextMenu(at point: NSPoint) {
        let menu = NSMenu()

        let shapeLabel = currentShape == .circle ? "Switch to ▭" : "Switch to ⚪"
        let shapeAction = currentShape == .circle ? #selector(setRectShape) : #selector(setCircleShape)
        let shapeToggle = NSMenuItem(title: shapeLabel, action: shapeAction, keyEquivalent: "")
        shapeToggle.target = self
        menu.addItem(shapeToggle)

        // Opacity in context menu
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for pct in [100, 80, 60, 40, 20] {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(changeOpacity(_:)), keyEquivalent: "")
            item.tag = pct
            item.target = self
            if Int(currentOpacity * 100) == pct { item.state = .on }
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let resetItem = NSMenuItem(title: "Reset Zoom", action: #selector(resetVideoTransform), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop Capture", action: #selector(stopCapture), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        if let window = overlayWindow, let view = window.contentView {
            NSMenu.popUpContextMenu(menu, with: NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1.0
            )!, for: view)
        }
    }

    @objc private func resetVideoTransform() {
        overlayWindow?.contentViewInstance.resetTransforms()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Remember the frontmost app before our menu steals focus
        if let frontApp = NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication {
            frontPID = frontApp.processIdentifier
        }
    }
}

// MARK: - ScreenCaptureDelegate

extension AppDelegate: ScreenCaptureDelegate {
    func screenCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frame: CGImage) {
        overlayWindow?.contentViewInstance.updateFrame(frame)
    }

    func screenCaptureEngine(_ engine: ScreenCaptureEngine, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Capture Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            self?.stopCapture()
        }
    }
}

// MARK: - OContentViewDelegate

extension AppDelegate: OContentViewDelegate {
    func contentViewRequestsResize(delta: CGFloat) {
        currentWidth = min(max(currentWidth + delta * 2, 80), 800)
        if currentShape == .circle {
            currentHeight = currentWidth
        } else {
            currentHeight = min(max(currentHeight + delta * 2, 80), 800)
        }
        overlayWindow?.resize(toWidth: currentWidth, height: currentHeight)
    }

    func contentViewRequestsContextMenu(at point: NSPoint) {
        showContextMenu(at: point)
    }
}
