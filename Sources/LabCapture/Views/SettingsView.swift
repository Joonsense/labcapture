import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @AppStorage(SK.intervalMinutes) private var intervalMinutes = 20
    @AppStorage(SK.durationSeconds) private var durationSeconds = 3
    @AppStorage(SK.preNotify) private var preNotify = true
    @AppStorage(SK.preNotifyLead) private var preNotifyLead = 3
    @AppStorage(SK.webcamEnabled) private var webcamEnabled = true
    @AppStorage(SK.pipPosition) private var pipPosition = "br"
    @AppStorage(SK.gifFps) private var gifFps = 15
    @AppStorage(SK.screenGifWidth) private var screenGifWidth = 960
    @AppStorage(SK.outputDir) private var outputDir = NSString("~/LabCapture").expandingTildeInPath
    @AppStorage(SK.keepOriginals) private var keepOriginals = false
    @AppStorage(SK.pauseSchedule) private var pauseSchedule = false
    @AppStorage(SK.pauseStartMin) private var pauseStartMin = 21 * 60
    @AppStorage(SK.pauseEndMin) private var pauseEndMin = 9 * 60
    @AppStorage(SK.hotkeyKeyCode) private var hotkeyKeyCode = 8
    @AppStorage(SK.hotkeyModifiers) private var hotkeyModifiers = 256 + 2048 + 4096
    @AppStorage(SK.screenDeviceIndex) private var screenDeviceIndex = -1
    @AppStorage(SK.camDeviceIndex) private var camDeviceIndex = -1
    @AppStorage(SK.ocrGuard) private var ocrGuard = true
    @AppStorage(SK.ocrPauseHours) private var ocrPauseHours = 2

    @State private var recordingHotkey = false
    @State private var keyMonitor: Any?

    var body: some View {
        Form {
            Section("캡처") {
                Stepper("캡처 주기: \(intervalMinutes)분", value: $intervalMinutes, in: 5...120, step: 5)
                Stepper("캡처 길이: \(durationSeconds)초", value: $durationSeconds, in: 1...5)
                Toggle("사전 알림 사용", isOn: $preNotify)
                if preNotify {
                    Stepper("사전 알림 리드타임: \(preNotifyLead)초", value: $preNotifyLead, in: 0...10)
                }
            }

            Section("웹캠") {
                Toggle("웹캠 캡처 사용", isOn: $webcamEnabled)
                    .help("끄면 screen.gif만 생성됩니다")
                if webcamEnabled {
                    Picker("PiP 위치", selection: $pipPosition) {
                        Text("좌상단").tag("tl")
                        Text("우상단").tag("tr")
                        Text("좌하단").tag("bl")
                        Text("우하단").tag("br")
                    }
                }
            }

            Section("GIF") {
                Stepper("fps: \(gifFps)", value: $gifFps, in: 8...15)
                Stepper("화면 GIF 가로폭: \(screenGifWidth)px", value: $screenGifWidth, in: 480...1080, step: 40)
            }

            Section("민감정보 가드 (OCR)") {
                Toggle("화면에 API 키·토큰 보이면 캡처 폐기", isOn: $ocrGuard)
                if ocrGuard {
                    Stepper("연속 \(AppModel.maxOcrDiscards)회 폐기 시 중단: \(ocrPauseHours)시간",
                            value: $ocrPauseHours, in: 1...12)
                    Text("폐기 후 즉시 재캡처합니다. \(AppModel.maxOcrDiscards)회 연속 감지되면 위 시간만큼 캡처를 중단하고 자동 재개합니다 (메뉴 '재개'로 즉시 해제 가능).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("저장") {
                HStack {
                    Text("출력 폴더")
                    Spacer()
                    Text(abbreviatedPath(outputDir))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("변경…") { chooseOutputDir() }
                }
                Toggle("원본 mp4 보존", isOn: $keepOriginals)
                    .help("고화질 타임랩스의 재료입니다 — 끄면 타임랩스가 GIF 기반(저화질)으로 만들어집니다")
            }

            Section("일시정지 스케줄") {
                Toggle("스케줄 사용", isOn: $pauseSchedule)
                if pauseSchedule {
                    DatePicker("시작", selection: minuteBinding($pauseStartMin), displayedComponents: .hourAndMinute)
                    DatePicker("종료", selection: minuteBinding($pauseEndMin), displayedComponents: .hourAndMinute)
                    Text("이 시간 동안 타이머 캡처가 자동 일시정지됩니다 (수동 캡처는 가능)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("전역 단축키") {
                HStack {
                    Text("지금 캡처")
                    Spacer()
                    Button(recordingHotkey
                           ? "키를 누르세요…"
                           : HotkeyManager.displayString(keyCode: hotkeyKeyCode, carbonModifiers: hotkeyModifiers)) {
                        toggleHotkeyRecording()
                    }
                }
            }

            Section("캡처 장치") {
                if model.detectedDevices.isEmpty {
                    Text("장치 미탐지 — 화면 기록 권한 허용 후 재탐지하세요")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.detectedDevices, id: \.index) { dev in
                        HStack {
                            Text("[\(dev.index)] \(dev.name)")
                            Spacer()
                            if dev.index == screenDeviceIndex { Text("화면").foregroundStyle(.secondary) }
                            if dev.index == camDeviceIndex { Text("웹캠").foregroundStyle(.secondary) }
                        }
                        .font(.caption)
                    }
                }
                Button("장치 재탐지") { model.redetectDevices() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .onDisappear { stopHotkeyRecording() }
    }

    // MARK: - 헬퍼

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: outputDir)
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// 분(0~1439) Int ↔ DatePicker용 Date 변환
    private func minuteBinding(_ source: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let cal = Calendar.current
                return cal.date(bySettingHour: source.wrappedValue / 60,
                                minute: source.wrappedValue % 60,
                                second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                source.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func toggleHotkeyRecording() {
        if recordingHotkey { stopHotkeyRecording(); return }
        recordingHotkey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = HotkeyManager.carbonModifiers(from: event.modifierFlags)
            if mods != 0 || event.keyCode == 53 { // 수식키 필수 (Esc는 취소)
                if event.keyCode != 53 {
                    hotkeyKeyCode = Int(event.keyCode)
                    hotkeyModifiers = mods
                }
                stopHotkeyRecording()
                return nil
            }
            return event
        }
    }

    private func stopHotkeyRecording() {
        recordingHotkey = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}
