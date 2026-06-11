import AppKit
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(SK.onboardingDone) private var onboardingDone = false

    @State private var screenOK = Permissions.screenGranted
    @State private var cameraOK = Permissions.cameraGranted
    @State private var notifOK = false
    @State private var ffmpegOK = FFmpeg.exists

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LabCapture 권한 설정")
                .font(.title2.bold())
            Text("캡처가 동작하려면 아래 항목이 모두 허용되어야 합니다.\n허용 후 자동으로 체크 표시가 갱신됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            row(ok: ffmpegOK, title: "ffmpeg 설치",
                detail: "터미널에서 brew install ffmpeg",
                action: nil, actionTitle: nil)

            row(ok: screenOK, title: "화면 기록 (Screen Recording)",
                detail: "시스템 설정 → 개인정보 보호 → 화면 기록에서 LabCapture 허용",
                action: {
                    Permissions.requestScreen()
                    Permissions.openScreenSettings()
                }, actionTitle: "설정 열기")

            row(ok: cameraOK, title: "카메라 (Camera)",
                detail: "웹캠(얼굴) 캡처에 필요 — 웹캠 사용 OFF면 건너뛰어도 됩니다",
                action: {
                    Permissions.requestCamera { ok in cameraOK = ok }
                    Permissions.openCameraSettings()
                }, actionTitle: "설정 열기")

            row(ok: notifOK, title: "알림 (Notifications)",
                detail: "사전 알림(캡처 N초 전)에 필요",
                action: {
                    Notifier.requestAuthorization()
                    Permissions.openNotificationSettings()
                }, actionTitle: "설정 열기")

            Divider()

            HStack {
                Text("권한 변경 후 앱 재시작이 필요할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("완료") {
                    onboardingDone = true
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onReceive(poll) { _ in refresh() }
        .onAppear { refresh() }
    }

    private func refresh() {
        screenOK = Permissions.screenGranted
        cameraOK = Permissions.cameraGranted
        ffmpegOK = FFmpeg.exists
        Notifier.authorizationStatus { status in
            notifOK = (status == .authorized || status == .provisional)
        }
    }

    @ViewBuilder
    private func row(ok: Bool, title: String, detail: String,
                     action: (() -> Void)?, actionTitle: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Color(red: 0.64, green: 0.90, blue: 0.21) : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok, let action, let actionTitle {
                Button(actionTitle, action: action)
            }
        }
    }
}
