import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Status { case active, paused, capturing, warning }
    enum Trigger: String { case timer, manual, hotkey, push }

    @Published var status: Status = .active
    @Published var lastError: String?
    @Published var lastComboURL: URL?
    @Published var lastThumbnail: NSImage?
    @Published var pausedUntil: Date?
    @Published var nextFireAt: Date?
    @Published var detectedDevices: [AVDevice] = []

    private var timer: Timer?
    private var isLocked = false
    private var isSleeping = false
    private var capturing = false
    private let server = TriggerServer()
    private let hotkey = HotkeyManager()
    private var onboardingWindow: NSWindow?
    private var settingsObserver: Any?

    // MARK: - 부트스트랩

    func bootstrap() {
        Settings.registerDefaults()
        Notifier.requestAuthorization()
        observeLockAndSleep()

        if !FFmpeg.exists { showFFmpegAlert() }

        Task {
            await FFmpeg.detectDevices()
            self.detectedDevices = await FFmpeg.listVideoDevices()
        }

        server.start { method, path, respond in
            Task { @MainActor in
                AppModel.shared.handleAPI(method: method, path: path, respond: respond)
            }
        }

        HotkeyManager.handler = { [weak self] in self?.requestCapture(trigger: .hotkey) }
        applyHotkey()
        startTimer()

        // 설정 변경 시 타이머/단축키 재적용
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settingsChanged() }
        }

        if !Settings.onboardingDone || !Permissions.screenGranted {
            showOnboarding()
        }
        refreshStatus()
    }

    private var lastAppliedInterval = -1
    private var lastAppliedHotkey = (code: -1, mods: -1)

    private func settingsChanged() {
        if Settings.intervalMinutes != lastAppliedInterval { startTimer() }
        let hk = (Settings.hotkeyKeyCode, Settings.hotkeyModifiers)
        if hk != lastAppliedHotkey { applyHotkey() }
        refreshStatus()
    }

    private func applyHotkey() {
        hotkey.register(keyCode: Settings.hotkeyKeyCode, carbonModifiers: Settings.hotkeyModifiers)
        lastAppliedHotkey = (Settings.hotkeyKeyCode, Settings.hotkeyModifiers)
    }

    // MARK: - 타이머

    func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(Settings.intervalMinutes * 60)
        lastAppliedInterval = Settings.intervalMinutes
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.timerFired() }
        }
        t.tolerance = interval * 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
        nextFireAt = Date().addingTimeInterval(interval)
        refreshStatus()
    }

    private func timerFired() {
        nextFireAt = Date().addingTimeInterval(TimeInterval(Settings.intervalMinutes * 60))
        guard !isPausedNow, !isLocked, !isSleeping else { refreshStatus(); return }
        // 두 소스 모두 OFF면 에러 대신 조용히 skip (사용자가 의도적으로 끈 상태)
        guard Settings.effectiveScreenOn || Settings.effectiveFaceOn else { refreshStatus(); return }
        requestCapture(trigger: .timer)
    }

    // MARK: - 소스 토글 (화면/얼굴 개별 ON/OFF)

    var screenSourceOn: Bool { Settings.screenSourceOn }
    var faceSourceOn: Bool { Settings.effectiveFaceOn }

    func setScreenSource(_ on: Bool) {
        Settings.d.set(on, forKey: SK.screenSourceOn)
        objectWillChange.send()
        refreshStatus()
    }

    func setFaceSource(_ on: Bool) {
        // 빠른 토글을 켜면 설정의 웹캠 마스터 스위치도 함께 켠다 (메뉴에서 한 번에 복구)
        Settings.d.set(on, forKey: SK.faceSourceOn)
        if on && !Settings.webcamEnabled { Settings.d.set(true, forKey: SK.webcamEnabled) }
        objectWillChange.send()
        refreshStatus()
    }

    // MARK: - 일시정지

    var isPausedNow: Bool {
        if let until = pausedUntil, until > Date() { return true }
        return Settings.isInPauseSchedule()
    }

    func pause(for seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
        refreshStatus()
    }

    func pauseToday() {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date()).addingTimeInterval(86_400)
        pausedUntil = midnight
        refreshStatus()
    }

    func resume() {
        pausedUntil = nil
        refreshStatus()
    }

    // MARK: - 캡처

    func requestCapture(trigger: Trigger) {
        guard !capturing else { return }
        if trigger == .timer && isPausedNow { return }
        capturing = true
        status = .capturing

        Task {
            // 사전 알림 → 리드타임 대기
            let lead = Settings.preNotifyLead
            if Settings.preNotify && lead > 0 {
                Notifier.show("Capturing in \(lead)s", body: "LabCapture is about to record the screen and webcam.")
                try? await Task.sleep(nanoseconds: UInt64(lead) * 1_000_000_000)
            }
            do {
                let out = try await CaptureEngine.capture(trigger: trigger.rawValue)
                self.lastError = nil
                self.ocrDiscardStreak = 0 // 성공 시 연속 폐기 카운터 리셋
                if let combo = out.comboURL {
                    self.lastComboURL = combo
                    self.lastThumbnail = Self.thumbnail(from: combo)
                }
            } catch let err as CaptureError {
                if case .sensitiveContent(let kinds) = err {
                    self.handleSensitiveDiscard(kinds: kinds, trigger: trigger)
                } else {
                    self.reportCaptureError(err.localizedDescription)
                }
            } catch {
                self.reportCaptureError(error.localizedDescription)
            }
            self.capturing = false
            self.refreshStatus()
        }
    }

    private func reportCaptureError(_ msg: String) {
        lastError = msg
        appendErrorLog(msg)
        Notifier.show("Capture failed", body: msg.components(separatedBy: "\n").first ?? msg)
    }

    // MARK: - 민감정보 폐기 정책
    // 폐기 → 즉시 재캡처 → 연속 3회 폐기 시 캡처 중단(설정 시간) 후 자동 재개

    static let maxOcrDiscards = 3
    private var ocrDiscardStreak = 0

    private func handleSensitiveDiscard(kinds: [String], trigger: Trigger) {
        ocrDiscardStreak += 1
        let detected = kinds.joined(separator: ", ")
        appendErrorLog("Sensitive info discarded (\(ocrDiscardStreak)/\(Self.maxOcrDiscards)): \(detected)")

        if ocrDiscardStreak >= Self.maxOcrDiscards {
            // 화면에 민감정보가 계속 떠 있는 상태 — N시간 캡처 중단
            let hours = Settings.ocrPauseHours
            ocrDiscardStreak = 0
            pause(for: TimeInterval(hours * 3600))
            Notifier.show("Sensitive info detected \(Self.maxOcrDiscards)× in a row — pausing capture for \(hours)h",
                          body: "Detected: \(detected). Clear the sensitive info from your screen, then release it instantly via 'Resume' in the menu.")
            return
        }

        Notifier.show("Sensitive info detected — capture discarded, recapturing now (\(ocrDiscardStreak)/\(Self.maxOcrDiscards))",
                      body: "Detected: \(detected)")
        // 폐기 완료 직후 즉시 재캡처 (사전 알림 없이 한 번만 재시도)
        Task { @MainActor in
            self.capturing = false
            self.retryCapture(trigger: trigger)
        }
    }

    /// 사전 알림 없이 즉시 1회 캡처 (폐기 후 재시도 전용)
    private func retryCapture(trigger: Trigger) {
        guard !capturing else { return }
        capturing = true
        status = .capturing
        Task {
            do {
                let out = try await CaptureEngine.capture(trigger: trigger.rawValue)
                self.lastError = nil
                self.ocrDiscardStreak = 0
                if let combo = out.comboURL {
                    self.lastComboURL = combo
                    self.lastThumbnail = Self.thumbnail(from: combo)
                }
            } catch let err as CaptureError {
                if case .sensitiveContent(let kinds) = err {
                    self.handleSensitiveDiscard(kinds: kinds, trigger: trigger)
                } else {
                    self.reportCaptureError(err.localizedDescription)
                }
            } catch {
                self.reportCaptureError(error.localizedDescription)
            }
            self.capturing = false
            self.refreshStatus()
        }
    }

    // MARK: - 상태 표시

    func refreshStatus() {
        if capturing { status = .capturing }
        else if lastError != nil { status = .warning }
        else if isPausedNow { status = .paused }
        else { status = .active }
    }

    var statusLine: String {
        switch status {
        case .capturing: return "Capturing…"
        case .warning: return "Warning — last capture failed"
        case .paused:
            if let until = pausedUntil, until > Date() {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                return "Paused — until \(f.string(from: until))"
            }
            return "Paused — scheduled"
        case .active:
            if let next = nextFireAt {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                return "Active — next capture \(f.string(from: next))"
            }
            return "Active"
        }
    }

    /// 메뉴바 아이콘 — 좌측 사각형=화면 소스, 우측 원=얼굴 소스.
    /// 채워짐=ON, 윤곽선만=OFF. 색은 전체 상태(활성 라임/일시정지 회색/캡처중 빨강/경고 주황).
    var statusIcon: NSImage {
        let color: NSColor
        switch status {
        case .active: color = NSColor(red: 0.64, green: 0.90, blue: 0.21, alpha: 1) // #A3E635 라임
        case .paused: color = .systemGray
        case .capturing: color = .systemRed
        case .warning: color = .systemOrange
        }
        return Self.sourcesImage(color: color,
                                 screenOn: Settings.effectiveScreenOn,
                                 faceOn: Settings.effectiveFaceOn)
    }

    private static func sourcesImage(color: NSColor, screenOn: Bool, faceOn: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            // 화면: 둥근 사각형 (모니터)
            let rect = NSBezierPath(roundedRect: NSRect(x: 2, y: 5, width: 11, height: 8.5),
                                    xRadius: 2, yRadius: 2)
            // 얼굴: 원 (웹캠)
            let circle = NSBezierPath(ovalIn: NSRect(x: 15, y: 5, width: 8.5, height: 8.5))

            for (path, on) in [(rect, screenOn), (circle, faceOn)] {
                if on {
                    color.setFill()
                    path.fill()
                } else {
                    color.withAlphaComponent(0.8).setStroke()
                    path.lineWidth = 1.3
                    path.stroke()
                    // OFF 표시: 대각 슬래시
                    let b = path.bounds
                    let slash = NSBezierPath()
                    slash.move(to: NSPoint(x: b.minX + 1, y: b.minY + 1))
                    slash.line(to: NSPoint(x: b.maxX - 1, y: b.maxY - 1))
                    slash.lineWidth = 1.3
                    slash.stroke()
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func thumbnail(from url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let targetH: CGFloat = 48
        let ratio = targetH / max(img.size.height, 1)
        let size = NSSize(width: img.size.width * ratio, height: targetH)
        let thumb = NSImage(size: size, flipped: false) { rect in
            img.draw(in: rect)
            return true
        }
        return thumb
    }

    // MARK: - 메뉴 액션

    func openTodayFolder() {
        let dir = CaptureEngine.dateDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func revealLastCapture() {
        guard let url = lastComboURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyLastCapture() {
        guard let url = lastComboURL else {
            Notifier.show("No capture to copy", body: "Run a capture first.")
            return
        }
        if DailyPipeline.copyToClipboard(url: url) {
            Notifier.show("Copied to clipboard", body: "Paste it straight into an X post with ⌘V.")
        }
    }

    // MARK: - 일일 파이프라인 (타임랩스 / LLM 요약)

    @Published var pipelineRunning = false

    func runTimelapse() {
        guard !pipelineRunning else { return }
        pipelineRunning = true
        Task {
            do {
                let out = try await DailyPipeline.buildTimelapse()
                Notifier.show("Timelapse ready", body: out.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                self.reportCaptureError(error.localizedDescription)
            }
            self.pipelineRunning = false
        }
    }

    func runDailySummary() {
        guard !pipelineRunning else { return }
        pipelineRunning = true
        Task {
            do {
                let out = try await DailyPipeline.buildSummary()
                Notifier.show("Today's build journal is ready", body: out.lastPathComponent)
                NSWorkspace.shared.open(out)
            } catch {
                self.reportCaptureError(error.localizedDescription)
            }
            self.pipelineRunning = false
        }
    }

    // MARK: - HTTP API (사람 + LLM/봇 공용, GET /capabilities 가 명세)

    func handleAPI(method: String, path: String,
                   respond: @escaping @Sendable (Int, String) -> Void) {
        switch (method, path) {
        case ("GET", "/trigger"), ("POST", "/trigger"), ("POST", "/capture"):
            guard !capturingNow else {
                respond(409, #"{"ok":false,"error":"capture_in_progress"}"#)
                return
            }
            requestCapture(trigger: .push)
            respond(202, #"{"ok":true,"action":"capture_started","trigger":"push"}"#)

        case ("GET", "/status"):
            respond(200, statusJSON())

        case ("GET", "/capabilities"), ("GET", "/"):
            respond(200, Self.capabilitiesJSON)

        case ("POST", "/source/screen/on"):   setScreenSource(true);  respond(200, statusJSON())
        case ("POST", "/source/screen/off"):  setScreenSource(false); respond(200, statusJSON())
        case ("POST", "/source/face/on"):     setFaceSource(true);    respond(200, statusJSON())
        case ("POST", "/source/face/off"):    setFaceSource(false);   respond(200, statusJSON())

        case ("POST", "/pause"):       pause(for: 3600);  respond(200, statusJSON())
        case ("POST", "/pause/today"): pauseToday();      respond(200, statusJSON())
        case ("POST", "/resume"):      resume();          respond(200, statusJSON())

        case ("POST", "/last/copy"):
            if let url = lastComboURL, DailyPipeline.copyToClipboard(url: url) {
                respond(200, #"{"ok":true,"action":"copied_to_clipboard","file":"\#(url.path)"}"#)
            } else {
                respond(404, #"{"ok":false,"error":"no_capture_yet"}"#)
            }

        case ("POST", "/timelapse"):
            guard !pipelineRunning else { respond(409, #"{"ok":false,"error":"pipeline_busy"}"#); return }
            runTimelapse()
            respond(202, #"{"ok":true,"action":"timelapse_started"}"#)

        case ("POST", "/summary"):
            guard !pipelineRunning else { respond(409, #"{"ok":false,"error":"pipeline_busy"}"#); return }
            guard DailyPipeline.apiKey != nil else {
                respond(400, #"{"ok":false,"error":"no_api_key","hint":"put key in ~/.config/labcapture/anthropic_api_key"}"#)
                return
            }
            runDailySummary()
            respond(202, #"{"ok":true,"action":"summary_started"}"#)

        default:
            respond(404, #"{"ok":false,"error":"not_found","hint":"GET /capabilities"}"#)
        }
    }

    private var capturingNow: Bool { status == .capturing }

    private func statusJSON() -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        let stateName: String
        switch status {
        case .active: stateName = "active"
        case .paused: stateName = "paused"
        case .capturing: stateName = "capturing"
        case .warning: stateName = "warning"
        }
        var obj: [String: Any] = [
            "ok": true,
            "app": "labcapture",
            "version": "0.4",
            "state": stateName,
            "paused": isPausedNow,
            "sources": [
                "screen": Settings.effectiveScreenOn,
                "face": Settings.effectiveFaceOn,
            ],
            "interval_minutes": Settings.intervalMinutes,
            "duration_seconds": Settings.durationSeconds,
            "output_dir": Settings.outputDir.path,
        ]
        if let next = nextFireAt { obj["next_capture_at"] = iso.string(from: next) }
        if let until = pausedUntil, until > Date() { obj["paused_until"] = iso.string(from: until) }
        if let err = lastError { obj["last_error"] = err }
        if let combo = lastComboURL { obj["last_capture_file"] = combo.path }
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    /// LLM/봇이 자가 발견(self-discovery)할 수 있는 머신리더블 API 명세
    static let capabilitiesJSON = """
    {"ok":true,"app":"labcapture","version":"0.4",\
    "description":"macOS menu bar app that periodically records screen and webcam for ~3s and emits 3 GIFs (screen, face, combo with circular face PiP) plus high-quality original mp4s, all named YYYY-MM-DD_HHmmss_*. Output: ~/LabCapture/YYYY-MM-DD/. Each capture appends one JSON line to manifest.jsonl (schema 1: ts, trigger, duration, sources, files, kinds).",\
    "base_url":"http://127.0.0.1:48620",\
    "endpoints":[\
    {"method":"GET","path":"/capabilities","description":"this document"},\
    {"method":"GET","path":"/status","description":"current state: active|paused|capturing|warning, sources on/off, next capture time, last error"},\
    {"method":"POST","path":"/capture","description":"start a capture now (also GET/POST /trigger for git hooks); 202 on start, 409 if already capturing"},\
    {"method":"POST","path":"/source/screen/on","description":"enable screen source"},\
    {"method":"POST","path":"/source/screen/off","description":"disable screen source (face-only captures)"},\
    {"method":"POST","path":"/source/face/on","description":"enable face (webcam) source"},\
    {"method":"POST","path":"/source/face/off","description":"disable face source (screen-only captures)"},\
    {"method":"POST","path":"/pause","description":"pause timer captures for 1 hour"},\
    {"method":"POST","path":"/pause/today","description":"pause timer captures until midnight"},\
    {"method":"POST","path":"/resume","description":"resume timer captures"},\
    {"method":"POST","path":"/last/copy","description":"copy the last combo.gif to the macOS clipboard (paste into X with Cmd+V)"},\
    {"method":"POST","path":"/timelapse","description":"compile today's original mp4 captures into a high-quality 1080p timelapse (screen background + circular face overlay centered), saved as timelapse_YYYY-MM-DD_HHmmss.mp4; 202 on start"},\
    {"method":"POST","path":"/summary","description":"generate today's building journal (summary.md) via Claude API from manifest.jsonl + capture frames; requires API key in ~/.config/labcapture/anthropic_api_key; 202 on start"}\
    ],\
    "safety":"OCR guard: if an API key/token/password is visible on screen, the capture is discarded and retried immediately; after 3 consecutive discards, captures pause for a configurable number of hours."}
    """

    // MARK: - 에러 로그

    private var errorLogURL: URL { Settings.outputDir.appendingPathComponent("labcapture.log") }

    private func appendErrorLog(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(msg)\n---\n"
        try? FileManager.default.createDirectory(at: Settings.outputDir, withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: errorLogURL.path) {
            defer { try? h.close() }
            try? h.seekToEnd()
            try? h.write(contentsOf: line.data(using: .utf8)!)
        } else {
            try? line.data(using: .utf8)!.write(to: errorLogURL)
        }
    }

    func openErrorLog() {
        lastError = nil
        refreshStatus()
        if FileManager.default.fileExists(atPath: errorLogURL.path) {
            NSWorkspace.shared.open(errorLogURL)
        }
    }

    // MARK: - 잠금/잠자기 감지

    private func observeLockAndSleep() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isLocked = true }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isLocked = false }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isSleeping = true }
        }
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isSleeping = false }
        }
    }

    // MARK: - 온보딩 / ffmpeg 안내

    func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = onboardingWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView().environmentObject(self)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Get Started with LabCapture"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        onboardingWindow = w
    }

    func redetectDevices() {
        Task {
            await FFmpeg.detectDevices(force: true)
            self.detectedDevices = await FFmpeg.listVideoDevices()
        }
    }

    private func showFFmpegAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ffmpeg is not installed"
        alert.informativeText = "LabCapture records the screen with ffmpeg.\nRun the command below in Terminal, then restart the app.\n\nbrew install ffmpeg"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
