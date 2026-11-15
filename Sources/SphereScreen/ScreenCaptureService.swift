import Foundation
import SphereCore
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import AppKit

public struct WindowInfo: Identifiable, Sendable {
    public var id: UInt32
    public var appName: String
    public var bundleId: String?
    public var title: String
    public var frame: CGRect
    public var isOnScreen: Bool

    public init(id: UInt32, appName: String, bundleId: String?, title: String, frame: CGRect, isOnScreen: Bool) {
        self.id = id
        self.appName = appName
        self.bundleId = bundleId
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
    }
}

public struct DisplayInfo: Identifiable, Sendable {
    public var id: UInt32
    public var width: Int
    public var height: Int

    public init(id: UInt32, width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }
}

/// Enumerates shareable windows/displays and captures PNG snapshots with
/// ScreenCaptureKit. The OS-level Screen Recording permission is app-wide;
/// per-window consent is enforced by `ScreenAllowlist` before capturing.
public final class ScreenCaptureService: @unchecked Sendable {
    private let audit: AuditLog

    public init(audit: AuditLog = AuditLog()) {
        self.audit = audit
    }

    public func preflightPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func availableWindows() async throws -> [WindowInfo] {
        let content = try await shareableContent()
        return content.windows.compactMap { window in
            guard window.windowLayer == 0 else { return nil }
            let app = window.owningApplication
            return WindowInfo(
                id: window.windowID,
                appName: app?.applicationName ?? "Unknown",
                bundleId: app?.bundleIdentifier,
                title: window.title ?? "",
                frame: window.frame,
                isOnScreen: window.isOnScreen
            )
        }
        .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    public func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await shareableContent()
        return content.displays.map { DisplayInfo(id: $0.displayID, width: $0.width, height: $0.height) }
    }

    public func captureWindow(_ window: WindowInfo, scale: CGFloat = 2) async throws -> Data {
        let content = try await shareableContent()
        guard let shareable = content.windows.first(where: { $0.windowID == window.id }) else {
            throw SphereError.processFailed("window \(window.id) is no longer available")
        }
        let filter = SCContentFilter(desktopIndependentWindow: shareable)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image = try await capture(filter: filter, configuration: configuration)
        audit.write("screen", "capture window \(window.appName) '\(window.title)' (#\(window.id))")
        return try pngData(from: image)
    }

    public func captureDisplay(_ display: DisplayInfo, scale: CGFloat = 1) async throws -> Data {
        let content = try await shareableContent()
        guard let shareable = content.displays.first(where: { $0.displayID == display.id }) else {
            throw SphereError.processFailed("display \(display.id) is no longer available")
        }
        let filter = SCContentFilter(display: shareable, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(Double(display.width) * Double(scale))
        configuration.height = Int(Double(display.height) * Double(scale))
        configuration.showsCursor = false
        let image = try await capture(filter: filter, configuration: configuration)
        audit.write("screen", "capture display #\(display.id)")
        return try pngData(from: image)
    }

    // MARK: - Internals

    private func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let grabber = FrameGrabber()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: grabber)
        try stream.addStreamOutput(grabber, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.sphere.screen.frames"))
        try await start(stream)

        var captured: CGImage?
        do {
            for try await frame in grabber.frames {
                captured = frame
                break
            }
        } catch {
            grabber.finish()
            try? await stop(stream)
            throw error
        }
        grabber.finish()
        try? await stop(stream)

        guard let captured else {
            throw SphereError.processFailed("no frame received from ScreenCaptureKit")
        }
        return captured
    }

    private func start(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stop(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func pngData(from image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SphereError.processFailed("could not encode PNG")
        }
        return data
    }
}

private final class FrameGrabber: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames: AsyncThrowingStream<CGImage, Error>
    private let continuation: AsyncThrowingStream<CGImage, Error>.Continuation
    private let lock = NSLock()
    private var finished = false

    override init() {
        var captured: AsyncThrowingStream<CGImage, Error>.Continuation!
        self.frames = AsyncThrowingStream { captured = $0 }
        self.continuation = captured
        super.init()
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        continuation.finish()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        continuation.yield(cgImage)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        continuation.finish(throwing: error)
    }
}
