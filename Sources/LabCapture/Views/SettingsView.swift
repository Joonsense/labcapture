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
            Section("Capture") {
                Stepper("Capture interval: \(intervalMinutes) min", value: $intervalMinutes, in: 5...120, step: 5)
                Stepper("Capture length: \(durationSeconds) sec", value: $durationSeconds, in: 1...5)
                Toggle("Pre-capture notification", isOn: $preNotify)
                if preNotify {
                    Stepper("Notification lead time: \(preNotifyLead) sec", value: $preNotifyLead, in: 0...10)
                }
            }

            Section("Webcam") {
                Toggle("Enable webcam capture", isOn: $webcamEnabled)
                    .help("When off, only screen.gif is generated")
                if webcamEnabled {
                    Picker("PiP position", selection: $pipPosition) {
                        Text("Top left").tag("tl")
                        Text("Top right").tag("tr")
                        Text("Bottom left").tag("bl")
                        Text("Bottom right").tag("br")
                    }
                }
            }

            Section("GIF") {
                Stepper("fps: \(gifFps)", value: $gifFps, in: 8...15)
                Stepper("Screen GIF width: \(screenGifWidth)px", value: $screenGifWidth, in: 480...1080, step: 40)
            }

            Section("Sensitive Info Guard (OCR)") {
                Toggle("Discard capture if API keys/tokens are visible", isOn: $ocrGuard)
                if ocrGuard {
                    Stepper("Pause after \(AppModel.maxOcrDiscards) discards in a row: \(ocrPauseHours) hr",
                            value: $ocrPauseHours, in: 1...12)
                    Text("Recaptures immediately after a discard. If detected \(AppModel.maxOcrDiscards) times in a row, capture pauses for the time above and resumes automatically (release instantly via 'Resume' in the menu).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                HStack {
                    Text("Output folder")
                    Spacer()
                    Text(abbreviatedPath(outputDir))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") { chooseOutputDir() }
                }
                Toggle("Keep original mp4", isOn: $keepOriginals)
                    .help("Source material for high-quality timelapse — when off, the timelapse is built from GIFs (low quality)")
            }

            Section("Pause Schedule") {
                Toggle("Enable schedule", isOn: $pauseSchedule)
                if pauseSchedule {
                    DatePicker("Start", selection: minuteBinding($pauseStartMin), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: minuteBinding($pauseEndMin), displayedComponents: .hourAndMinute)
                    Text("Timer captures pause automatically during this window (manual capture still works)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Global Shortcut") {
                HStack {
                    Text("Capture Now")
                    Spacer()
                    Button(recordingHotkey
                           ? "Press a key…"
                           : HotkeyManager.displayString(keyCode: hotkeyKeyCode, carbonModifiers: hotkeyModifiers)) {
                        toggleHotkeyRecording()
                    }
                }
            }

            Section("Capture Devices") {
                if model.detectedDevices.isEmpty {
                    Text("No devices detected — grant Screen Recording permission, then re-detect")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.detectedDevices, id: \.index) { dev in
                        HStack {
                            Text("[\(dev.index)] \(dev.name)")
                            Spacer()
                            if dev.index == screenDeviceIndex { Text("Screen").foregroundStyle(.secondary) }
                            if dev.index == camDeviceIndex { Text("Webcam").foregroundStyle(.secondary) }
                        }
                        .font(.caption)
                    }
                }
                Button("Re-detect Devices") { model.redetectDevices() }
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
