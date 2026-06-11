import AppKit
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.statusLine)

        Button("지금 캡처") {
            model.requestCapture(trigger: .manual)
        }

        Divider()

        // 소스 빠른 토글 — 끄면 메뉴바 아이콘에 슬래시로 표시됨
        Toggle("화면 캡처", isOn: Binding(
            get: { model.screenSourceOn },
            set: { model.setScreenSource($0) }
        ))
        Toggle("얼굴 캡처", isOn: Binding(
            get: { model.faceSourceOn },
            set: { model.setFaceSource($0) }
        ))

        if model.isPausedNow {
            Button("재개") { model.resume() }
        } else {
            Menu("일시정지") {
                Button("1시간 일시정지") { model.pause(for: 3600) }
                Button("오늘 하루 일시정지") { model.pauseToday() }
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
                Text("마지막 캡처 보기")
            }
        }

        if model.lastComboURL != nil {
            Button("마지막 캡처 클립보드 복사 (X용)") { model.copyLastCapture() }
        }

        Button("오늘 폴더 열기") { model.openTodayFolder() }

        Menu("오늘 정리") {
            Button("타임랩스 만들기") { model.runTimelapse() }
            Button("빌딩 일지 생성 (Claude)") { model.runDailySummary() }
        }
        .disabled(model.pipelineRunning)

        if model.lastError != nil {
            Button("⚠️ 마지막 에러 로그 보기") { model.openErrorLog() }
        }

        Divider()

        Button("설정…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("권한 설정…") { model.showOnboarding() }

        Divider()

        Button("종료") { NSApp.terminate(nil) }
    }
}
