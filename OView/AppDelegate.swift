import AppKit
import ScreenCaptureKit

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
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: "OView")
            button.image?.isTemplate = true
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let captureItem = NSMenuItem(title: "Захватить текущее окно", action: #selector(captureCurrentWindow), keyEquivalent: "r")
        captureItem.target = self
        menu.addItem(captureItem)

        // Also keep option to pick manually
        let pickItem = NSMenuItem(title: "Выбрать окно…", action: #selector(refreshAndShowWindows), keyEquivalent: "")
        pickItem.target = self
        menu.addItem(pickItem)

        menu.addItem(NSMenuItem.separator())

        // Shape submenu
        let shapeItem = NSMenuItem(title: "Форма", action: nil, keyEquivalent: "")
        let shapeMenu = NSMenu()
        let circleItem = NSMenuItem(title: "⚪ Круг", action: #selector(setCircleShape), keyEquivalent: "")
        circleItem.target = self
        circleItem.state = currentShape == .circle ? .on : .off
        shapeMenu.addItem(circleItem)
        let rectItem = NSMenuItem(title: "▭ Прямоугольник", action: #selector(setRectShape), keyEquivalent: "")
        rectItem.target = self
        rectItem.state = currentShape == .rectangle ? .on : .off
        shapeMenu.addItem(rectItem)
        shapeItem.submenu = shapeMenu
        menu.addItem(shapeItem)

        // Size submenu
        let sizeItem = NSMenuItem(title: "Размер", action: nil, keyEquivalent: "")
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
            let widthItem = NSMenuItem(title: "Ширина", action: nil, keyEquivalent: "")
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

            let heightItem = NSMenuItem(title: "Высота", action: nil, keyEquivalent: "")
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
        let opacityItem = NSMenuItem(title: "Прозрачность", action: nil, keyEquivalent: "")
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

        let stopItem = NSMenuItem(title: "Остановить захват", action: #selector(stopCapture), keyEquivalent: "s")
        stopItem.target = self
        menu.addItem(stopItem)

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quitApp), keyEquivalent: "q")
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
        checkScreenRecordingPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.autoCaptureFrontWindow()
            } else {
                self.showPermissionAlert()
            }
        }
    }

    private func autoCaptureFrontWindow() {
        ScreenCaptureEngine.getFrontmostWindow(pid: frontPID) { [weak self] window in
            guard let self else { return }
            if let window {
                self.beginCapture(of: window)
            } else {
                let alert = NSAlert()
                alert.messageText = "Не удалось найти активное окно"
                alert.informativeText = "Переключитесь на нужное окно перед захватом."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - Manual Window Picker (backup)

    @objc private func refreshAndShowWindows() {
        checkScreenRecordingPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.showWindowPicker()
            } else {
                self.showPermissionAlert()
            }
        }
    }

    private func showWindowPicker() {
        ScreenCaptureEngine.getAvailableWindows { [weak self] windows in
            guard let self else { return }
            let picker = NSMenu(title: "Выберите окно")

            if windows.isEmpty {
                let emptyItem = NSMenuItem(title: "Нет доступных окон", action: nil, keyEquivalent: "")
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
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            DispatchQueue.main.async {
                completion(error == nil && content != nil)
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Требуется разрешение на запись экрана"
        alert.informativeText = "OView необходим доступ к записи экрана.\n\nОткройте:\nНастройки системы → Конфиденциальность и безопасность → Запись экрана\n\nИ включите OView в списке."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")

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

        let shapeLabel = currentShape == .circle ? "Переключить на ▭" : "Переключить на ⚪"
        let shapeAction = currentShape == .circle ? #selector(setRectShape) : #selector(setCircleShape)
        let shapeToggle = NSMenuItem(title: shapeLabel, action: shapeAction, keyEquivalent: "")
        shapeToggle.target = self
        menu.addItem(shapeToggle)

        // Opacity in context menu
        let opacityItem = NSMenuItem(title: "Прозрачность", action: nil, keyEquivalent: "")
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

        let resetItem = NSMenuItem(title: "Сбросить масштаб", action: #selector(resetVideoTransform), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Остановить захват", action: #selector(stopCapture), keyEquivalent: "")
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
            alert.messageText = "Ошибка захвата"
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
