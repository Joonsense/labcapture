import AppKit
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.statusLine)

        Button("Capture Now") {
            model.requestCapture(trigger: .manual)
        }

        Divider()

        // 소스 빠른 토글 — 끄면 메뉴바 아이콘에 슬래시로 표시됨
        Toggle("Screen Capture", isOn: Binding(
            get: { model.screenSourceOn },
            set: { model.setScreenSource($0) }
        ))
        Toggle("Face Capture", isOn: Binding(
            get: { model.faceSourceOn },
            set: { model.setFaceSource($0) }
        ))

        if model.isPausedNow {
            Button("Resume") { model.resume() }
        } else {
            Menu("Pause") {
                Button("Pause for 1 hour") { model.pause(for: 3600) }
                Button("Pause for today") { model.pauseToday() }
            }
        }

        Divider()

        if model.lastComboURL != nil {
            Button {
                model.revealLastCapture()
            } label: {
                if let thumb = model.lastThumbnail {
                    Image(nsImage: thumb)
                }
                Text("Show Last Capture")
            }
        }

        if model.lastComboURL != nil {
            Button("Copy Last Capture to Clipboard (for X)") { model.copyLastCapture() }
        }

        Button("Open Today's Folder") { model.openTodayFolder() }

        Menu("Today's Tools") {
            Button("Make Timelapse") { model.runTimelapse() }
            Button("Generate Build Journal (Claude)") { model.runDailySummary() }
        }
        .disabled(model.pipelineRunning)

        if model.lastError != nil {
            Button("⚠️ Show Last Error Log") { model.openErrorLog() }
        }

        Divider()

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Permissions…") { model.showOnboarding() }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
    }
}
