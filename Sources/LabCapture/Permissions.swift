import AppKit
import AVFoundation
import CoreGraphics

enum Permissions {
    static var screenGranted: Bool { CGPreflightScreenCaptureAccess() }

    static var cameraGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static func requestScreen() {
        CGRequestScreenCaptureAccess()
    }

    static func requestCamera(_ completion: @escaping (Bool) -> Void = { _ in }) {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    static func openScreenSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    static func openNotificationSettings() {
        open("x-apple.systempreferences:com.apple.preference.notifications")
    }

    private static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
