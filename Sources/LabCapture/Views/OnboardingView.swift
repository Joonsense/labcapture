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
            Text("LabCapture Permissions")
                .font(.title2.bold())
            Text("All of the items below must be granted for capture to work.\nCheckmarks update automatically once granted.")
                .font(.callout)
                .foregroundStyle(.secondary)

            row(ok: ffmpegOK, title: "Install ffmpeg",
                detail: "Run brew install ffmpeg in Terminal",
                action: nil, actionTitle: nil)

            row(ok: screenOK, title: "Screen Recording",
                detail: "Allow LabCapture in System Settings → Privacy & Security → Screen Recording",
                action: {
                    Permissions.requestScreen()
                    Permissions.openScreenSettings()
                }, actionTitle: "Open Settings")

            row(ok: cameraOK, title: "Camera",
                detail: "Needed for webcam (face) capture — skip it if webcam is off",
                action: {
                    Permissions.requestCamera { ok in cameraOK = ok }
                    Permissions.openCameraSettings()
                }, actionTitle: "Open Settings")

            row(ok: notifOK, title: "Notifications",
                detail: "Needed for pre-capture notifications (N seconds before capture)",
                action: {
                    Notifier.requestAuthorization()
                    Permissions.openNotificationSettings()
                }, actionTitle: "Open Settings")

            Divider()

            HStack {
                Text("A restart may be required after changing permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
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
