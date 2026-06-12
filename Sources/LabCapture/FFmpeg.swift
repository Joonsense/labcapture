import Foundation

struct FFResult {
    let code: Int32
    let stderr: String
    var ok: Bool { code == 0 }
    /// 에러 보고용 stderr 요약 — 에러성 줄 우선, 없으면 마지막 줄들
    var tail: String {
        let lines = stderr.split(separator: "\n").map(String.init)
        let keywords = ["error", "denied", "permission", "failed", "invalid", "not permitted", "cannot"]
        let errorLines = lines.filter { line in
            let l = line.lowercased()
            return keywords.contains { l.contains($0) }
        }
        if !errorLines.isEmpty { return errorLines.suffix(5).joined(separator: "\n") }
        return lines.suffix(6).joined(separator: "\n")
    }
}

struct AVDevice {
    let index: Int
    let name: String
    var isScreen: Bool { name.lowercased().contains("capture screen") }
}

enum FFmpeg {
    static let path = "/opt/homebrew/bin/ffmpeg"
    static var exists: Bool { FileManager.default.isExecutableFile(atPath: path) }

    /// ffmpeg 서브프로세스를 실행하고 종료를 기다린다. timeout 초과 시 강제 종료.
    static func run(_ args: [String], timeout: TimeInterval = 60) async -> FFResult {
        await withCheckedContinuation { (cont: CheckedContinuation<FFResult, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice

            let stderrBox = LockedBox()
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                if data.isEmpty { h.readabilityHandler = nil } else { stderrBox.append(data) }
            }

            // TCC 권한 대기에 걸린 ffmpeg는 SIGTERM을 무시할 수 있어 SIGKILL로 에스컬레이션
            let timeoutWork = DispatchWorkItem {
                guard p.isRunning else { return }
                let pid = p.processIdentifier
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if p.isRunning { kill(pid, SIGKILL) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            p.terminationHandler = { proc in
                timeoutWork.cancel()
                errPipe.fileHandleForReading.readabilityHandler = nil
                let text = String(data: stderrBox.data, encoding: .utf8) ?? ""
                cont.resume(returning: FFResult(code: proc.terminationStatus, stderr: text))
            }

            do { try p.run() } catch {
                timeoutWork.cancel()
                cont.resume(returning: FFResult(code: -1, stderr: "ffmpeg failed to launch: \(error.localizedDescription)"))
            }
        }
    }

    /// avfoundation 비디오 장치 목록 (list_devices는 종료코드 1이 정상)
    static func listVideoDevices() async -> [AVDevice] {
        let r = await run(["-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""], timeout: 15)
        var devices: [AVDevice] = []
        var inVideo = false
        for line in r.stderr.split(separator: "\n") {
            if line.contains("AVFoundation video devices") { inVideo = true; continue }
            if line.contains("AVFoundation audio devices") { inVideo = false; continue }
            guard inVideo else { continue }
            // 예: [AVFoundation indev @ 0x...] [1] Capture screen 0
            if let m = line.range(of: #"\[(\d+)\] (.+)$"#, options: .regularExpression) {
                let part = String(line[m])
                let idxEnd = part.firstIndex(of: "]")!
                let idx = Int(part[part.index(after: part.startIndex)..<idxEnd]) ?? -1
                let name = String(part[part.index(idxEnd, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces)
                if idx >= 0 { devices.append(AVDevice(index: idx, name: name)) }
            }
        }
        return devices
    }

    /// 장치 인덱스 자동 탐지 → UserDefaults에 저장. 반환: (screenIdx, camIdx)
    @discardableResult
    static func detectDevices(force: Bool = false) async -> (screen: Int, cam: Int) {
        if !force, Settings.screenDeviceIndex >= 0 {
            return (Settings.screenDeviceIndex, Settings.camDeviceIndex)
        }
        let devices = await listVideoDevices()
        let screen = devices.first(where: { $0.isScreen })?.index ?? -1
        let cam = devices.first(where: { !$0.isScreen })?.index ?? -1
        Settings.d.set(screen, forKey: SK.screenDeviceIndex)
        Settings.d.set(cam, forKey: SK.camDeviceIndex)
        return (screen, cam)
    }
}

/// readabilityHandler(백그라운드 스레드)에서 안전하게 stderr를 모으는 박스
final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buf = Data()
    func append(_ d: Data) { lock.lock(); buf.append(d); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return buf }
}
