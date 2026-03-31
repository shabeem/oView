import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AppKit

protocol ScreenCaptureDelegate: AnyObject {
    func screenCaptureEngine(_ engine: ScreenCaptureEngine, didCaptureFrame frame: CGImage)
    func screenCaptureEngine(_ engine: ScreenCaptureEngine, didFailWithError error: Error)
}

struct CaptureableWindow {
    let window: SCWindow
    let title: String
    let appName: String
    let windowID: CGWindowID
}

final class ScreenCaptureEngine: NSObject {
    weak var delegate: ScreenCaptureDelegate?

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private(set) var isCapturing = false

    // MARK: - Window Discovery

    static func getAvailableWindows(completion: @escaping ([CaptureableWindow]) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            guard let content else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let ownPID = ProcessInfo.processInfo.processIdentifier
            let windows = content.windows
                .filter { window in
                    // Exclude our own app and windows without titles
                    window.owningApplication?.processID != ownPID &&
                    window.frame.width > 100 &&
                    window.frame.height > 100
                }
                .map { window in
                    let appName = window.owningApplication?.applicationName ?? "Unknown"
                    let title = window.title ?? ""
                    let displayName = title.isEmpty ? appName : "\(appName) — \(title)"
                    return CaptureableWindow(
                        window: window,
                        title: displayName,
                        appName: appName,
                        windowID: window.windowID
                    )
                }

            DispatchQueue.main.async { completion(windows) }
        }
    }

    // MARK: - Window Capture

    func startCapture(of window: SCWindow) {
        isCapturing = false

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)   // Retina
        config.height = Int(window.frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let output = CaptureStreamOutput()
        output.onFrame = { [weak self] frame in
            guard let self else { return }
            self.delegate?.screenCaptureEngine(self, didCaptureFrame: frame)
        }
        self.streamOutput = output

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = newStream

        do {
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.oview.capture", qos: .userInteractive))
            newStream.startCapture { [weak self] error in
                DispatchQueue.main.async {
                    if let error {
                        self?.delegate?.screenCaptureEngine(self!, didFailWithError: error)
                    } else {
                        self?.isCapturing = true
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.delegate?.screenCaptureEngine(self, didFailWithError: error)
            }
        }
    }

    func stopCapture() {
        guard let stream else { return }
        stream.stopCapture { [weak self] error in
            if let error {
                print("Error stopping capture: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.isCapturing = false
            }
        }
        self.stream = nil
        self.streamOutput = nil
    }

    enum CaptureError: LocalizedError {
        case noWindowFound
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noWindowFound: return "Не удалось найти окно для захвата."
            case .permissionDenied: return "Требуется разрешение на запись экрана."
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCapturing = false
            self.delegate?.screenCaptureEngine(self, didFailWithError: error)
        }
    }
}

// MARK: - Stream Output

private final class CaptureStreamOutput: NSObject, SCStreamOutput {
    var onFrame: ((CGImage) -> Void)?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))

        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else { return }
        onFrame?(cgImage)
    }
}
