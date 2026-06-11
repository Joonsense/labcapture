import AppKit
import SwiftUI

@main
struct LabCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    init() {
        // 디버그용 CLI 모드: LabCapture --ocr-test <video.mp4> → 감지 결과 출력 후 종료
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--ocr-test"), args.count > i + 1 {
            let path = args[i + 1]
            let sem = DispatchSemaphore(value: 0)
            // App.init은 메인 스레드 — Task {}는 MainActor에 잡혀 sem.wait()와 데드락이므로 detached 필수
            Task.detached {
                let hits = await OCRGuard.scan(videoPath: path)
                print(hits.isEmpty ? "CLEAN" : "DETECTED: \(hits.joined(separator: ", "))")
                sem.signal()
            }
            sem.wait()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(nsImage: model.statusIcon)
        }
        .menuBarExtraStyle(.menu)

        SwiftUI.Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 상주 앱 — Dock 아이콘 없음 (Info.plist LSUIElement와 이중 안전장치)
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppModel.shared.bootstrap()
        }
    }
}
