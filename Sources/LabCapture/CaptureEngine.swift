import Foundation

struct CaptureOutput {
    let dir: URL
    let files: [String]
    let comboURL: URL?
}

enum CaptureError: LocalizedError {
    case ffmpegMissing
    case lowDiskSpace
    case noScreenDevice
    case noCamDevice
    case allSourcesOff
    case sensitiveContent([String])
    case recordFailed(String)
    case convertFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: return "ffmpeg not found. Run `brew install ffmpeg` in Terminal, then try again."
        case .lowDiskSpace: return "Less than 500MB of free disk space — skipping capture."
        case .noScreenDevice: return "No screen capture device found. Check Screen Recording permission."
        case .noCamDevice: return "No webcam device found. Check Camera permission."
        case .allSourcesOff: return "Both screen and face sources are off — nothing to capture."
        case .sensitiveContent(let kinds): return "Capture discarded due to detected sensitive info: \(kinds.joined(separator: ", "))"
        case .recordFailed(let s): return "Recording failed:\n\(s)"
        case .convertFailed(let s): return "GIF conversion failed:\n\(s)"
        }
    }
}

enum CaptureEngine {
    static let tmpScreen = "/tmp/labcap_screen.mp4"
    static let tmpFace = "/tmp/labcap_face.mp4"
    static let menloFont = "/System/Library/Fonts/Menlo.ttc"
    static let tsFile = "/tmp/labcap_ts.txt"

    /// 캡처 1회 수행: 활성 소스(화면/얼굴) 동시 녹화 → GIF 변환 → manifest 기록.
    /// 소스 토글에 따라 화면만 / 얼굴만 / 둘 다(+combo) 출력이 달라진다.
    static func capture(trigger: String) async throws -> CaptureOutput {
        guard FFmpeg.exists else { throw CaptureError.ffmpegMissing }
        try checkDiskSpace()

        let useScreen = Settings.effectiveScreenOn
        let wantFace = Settings.effectiveFaceOn
        guard useScreen || wantFace else { throw CaptureError.allSourcesOff }

        var (screenIdx, camIdx) = await FFmpeg.detectDevices()
        if (useScreen && screenIdx < 0) || (wantFace && camIdx < 0) {
            (screenIdx, camIdx) = await FFmpeg.detectDevices(force: true)
        }
        if useScreen { guard screenIdx >= 0 else { throw CaptureError.noScreenDevice } }
        let useCam = wantFace && camIdx >= 0
        if wantFace && !useScreen { guard useCam else { throw CaptureError.noCamDevice } }

        let duration = Settings.durationSeconds
        let startedAt = Date()
        cleanupTmp()

        // ── 1. 활성 소스 동시 녹화 (별도 ffmpeg 프로세스, ±0.3초 오차 허용) ──
        // crf 18 = 시각적 무손실급. ultrafast는 실시간 캡처 드롭 방지용 (원본은 타임랩스 재료).
        let evenScale = "scale=trunc(iw/2)*2:trunc(ih/2)*2" // libx264 짝수 해상도 보장
        let screenArgs = [
            "-y", "-f", "avfoundation", "-framerate", "30", "-capture_cursor", "1",
            "-i", "\(screenIdx):none", "-t", "\(duration)",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", "-vf", evenScale,
            tmpScreen,
        ]
        let faceArgs = [
            "-y", "-f", "avfoundation", "-framerate", "30",
            "-i", "\(camIdx):none", "-t", "\(duration)",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", "-vf", evenScale,
            tmpFace,
        ]
        let recTimeout = TimeInterval(duration + 20)

        let screenTask: Task<FFResult, Never>? = useScreen ? Task { await FFmpeg.run(screenArgs, timeout: recTimeout) } : nil
        let faceTask: Task<FFResult, Never>? = useCam ? Task { await FFmpeg.run(faceArgs, timeout: recTimeout) } : nil

        let sRes = await screenTask?.value
        var fRes = await faceTask?.value

        if useScreen {
            guard sRes!.ok, fileOK(tmpScreen) else {
                cleanupTmp()
                throw CaptureError.recordFailed("Screen recording (device \(screenIdx))\n\(sRes!.tail)")
            }
        }
        if useCam, !(fRes?.ok ?? false) || !fileOK(tmpFace) {
            // 웹캠은 framerate 미지원으로 실패하는 경우가 있어 -framerate 없이 1회 재시도
            let retryArgs = faceArgs.filter { $0 != "-framerate" && $0 != "30" }
            fRes = await FFmpeg.run(retryArgs, timeout: recTimeout)
            guard fRes!.ok, fileOK(tmpFace) else {
                cleanupTmp()
                throw CaptureError.recordFailed("Webcam recording (device \(camIdx))\n\(fRes!.tail)")
            }
        }

        // ── 1.5. 민감정보 OCR 가드 (화면 소스에만 해당) ──
        // 감지 시 통캡처 폐기 — 부분 블러는 프레임 단위 추적 누락 시 유출 위험이 있어 안 한다.
        if useScreen, Settings.ocrGuard {
            let hits = await OCRGuard.scan(videoPath: tmpScreen)
            if !hits.isEmpty {
                cleanupTmp()
                throw CaptureError.sensitiveContent(hits)
            }
        }

        // ── 2. GIF 3종 변환 ──
        let dateDir = Self.dateDir(for: startedAt)
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let nameFmt = DateFormatter()
        nameFmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let base = nameFmt.string(from: startedAt)

        // 타임스탬프는 콜론 이스케이프 문제(필터그래프 2단계 파싱)를 피하기 위해
        // drawtext의 textfile= 옵션으로 주입한다.
        let tsFmt = DateFormatter()
        tsFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        try tsFmt.string(from: startedAt).data(using: .utf8)!
            .write(to: URL(fileURLWithPath: tsFile))

        let fps = Settings.gifFps
        let screenW = Settings.screenGifWidth
        var files: [String] = []

        // screen.gif (화면 소스 ON일 때)
        if useScreen {
            let screenGif = dateDir.appendingPathComponent("\(base)_screen.gif")
            let r1 = await FFmpeg.run([
                "-y", "-i", tmpScreen,
                "-filter_complex", "[0:v]fps=\(fps),scale=\(screenW):-1:flags=lanczos,\(drawtext(fontsize: 16)),\(paletteChain)",
                "-loop", "0", screenGif.path,
            ], timeout: 120)
            guard r1.ok, fileOK(screenGif.path) else { cleanupTmp(); throw CaptureError.convertFailed("screen.gif\n\(r1.tail)") }
            files.append(screenGif.lastPathComponent)
        }

        // face.gif (얼굴 소스 ON일 때)
        if useCam {
            let faceGif = dateDir.appendingPathComponent("\(base)_face.gif")
            let r2 = await FFmpeg.run([
                "-y", "-i", tmpFace,
                "-filter_complex", "[0:v]fps=\(fps),scale=480:-1:flags=lanczos,\(drawtext(fontsize: 14)),\(paletteChain)",
                "-loop", "0", faceGif.path,
            ], timeout: 120)
            guard r2.ok, fileOK(faceGif.path) else { cleanupTmp(); throw CaptureError.convertFailed("face.gif\n\(r2.tail)") }
            files.append(faceGif.lastPathComponent)
        }

        // combo.gif (둘 다 ON일 때만 PiP 합성)
        var comboURL: URL? = nil
        if useScreen && useCam {
            let comboGif = dateDir.appendingPathComponent("\(base)_combo.gif")
            let r3 = await FFmpeg.run(comboArgs(width: screenW, fps: fps, out: comboGif.path), timeout: 180)
            guard r3.ok, fileOK(comboGif.path) else { cleanupTmp(); throw CaptureError.convertFailed("combo.gif\n\(r3.tail)") }

            // 5MB 초과 시 720px로 자동 다운스케일 재인코딩
            if fileSize(comboGif.path) > 5_000_000, screenW > 720 {
                let r4 = await FFmpeg.run(comboArgs(width: 720, fps: fps, out: comboGif.path), timeout: 180)
                guard r4.ok else { cleanupTmp(); throw CaptureError.convertFailed("combo.gif 720px re-encode\n\(r4.tail)") }
            }
            files.append(comboGif.lastPathComponent)
            comboURL = comboGif
        }

        // ── 3. 원본 mp4 보존 또는 삭제, manifest 기록 ──
        if Settings.keepOriginals {
            let fm = FileManager.default
            if useScreen { try? fm.moveItem(atPath: tmpScreen, toPath: dateDir.appendingPathComponent("\(base)_screen.mp4").path) }
            if useCam { try? fm.moveItem(atPath: tmpFace, toPath: dateDir.appendingPathComponent("\(base)_face.mp4").path) }
        }
        cleanupTmp()
        var sources: [String] = []
        if useScreen { sources.append("screen") }
        if useCam { sources.append("face") }
        try appendManifest(dir: dateDir, ts: startedAt, files: files, duration: duration,
                           trigger: trigger, sources: sources)

        return CaptureOutput(dir: dateDir, files: files, comboURL: comboURL)
    }

    // MARK: - 필터 그래프

    /// 좌하단 타임스탬프 오버레이 (라임 그린 텍스트 + 반투명 검정 박스).
    /// textfile 방식 — 콜론 이스케이프 문제(필터그래프 2단계 파싱) 회피.
    static func drawtext(fontsize: Int, textfile: String) -> String {
        "drawtext=textfile=\(textfile):fontfile=\(menloFont):fontsize=\(fontsize):fontcolor=0xA3E635:box=1:boxcolor=black@0.55:boxborderw=6:x=12:y=h-th-12"
    }

    private static func drawtext(fontsize: Int) -> String { drawtext(fontsize: fontsize, textfile: tsFile) }

    /// 2-pass 팔레트 — stats_mode=diff(움직임 영역 가중) + sierra2_4a 디더링(고품질)
    private static let paletteChain = "split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle"

    /// 입력 스트림을 정사각 크롭 → 지름 d 원형(가장자리 1.5px 페더 알파)으로 만드는 체인.
    /// PiP combo와 타임랩스가 공용으로 쓴다.
    static func circleFilter(input: String, diameter: Int, fps: Int?, out: String) -> String {
        let d = max(2, diameter / 2 * 2)
        let fpsPart = fps.map { "fps=\($0)," } ?? ""
        let r = "hypot(X-W/2,Y-H/2)"
        let feather = "if(lt(\(r),W/2-1.5),255,if(lt(\(r),W/2),255*(W/2-\(r))/1.5,0))"
        return "[\(input)]\(fpsPart)crop='min(iw,ih)':'min(iw,ih)',scale=\(d):\(d):flags=lanczos," +
            "format=yuva420p,geq=lum='p(X,Y)':cb='p(X,Y)':cr='p(X,Y)':a='\(feather)'[\(out)]"
    }

    /// 라임 그린 원판 (원형 PiP의 링 테두리용 — face 원 뒤에 깔린다)
    static func limeDiscFilter(diameter: Int, out: String) -> String {
        let d = max(2, diameter / 2 * 2)
        let r = "hypot(X-W/2,Y-H/2)"
        let feather = "if(lt(\(r),W/2-1),255,if(lt(\(r),W/2),255*(W/2-\(r)),0))"
        return "color=c=0xA3E635:s=\(d)x\(d),format=yuva420p," +
            "geq=lum='p(X,Y)':cb='p(X,Y)':cr='p(X,Y)':a='\(feather)'[\(out)]"
    }

    /// (ring, face) overlay 좌표 — ring 지름 = face 지름 + 8, face는 4px 안쪽
    private static func circleOverlayExprs() -> (ring: String, face: String) {
        switch Settings.pipPosition {
        case "tl": return ("16:16", "20:20")
        case "tr": return ("W-w-16:16", "W-w-20:20")
        case "bl": return ("16:H-h-16", "20:H-h-20")
        default:   return ("W-w-16:H-h-16", "W-w-20:H-h-20") // br
        }
    }

    private static func comboArgs(width: Int, fps: Int, out: String) -> [String] {
        let faceD = max(2, Int(Double(width) * 0.24) / 2 * 2) // 원 지름 = 화면 가로의 24%, 짝수
        let pos = circleOverlayExprs()
        // ring(color 소스)은 무한 스트림이라 shortest=1 필수 — 없으면 인코딩이 끝나지 않는다.
        let filter = "[0:v]fps=\(fps),scale=\(width):-1:flags=lanczos[bg];" +
            limeDiscFilter(diameter: faceD + 8, out: "ring") + ";" +
            circleFilter(input: "1:v", diameter: faceD, fps: fps, out: "face") + ";" +
            "[bg][ring]overlay=\(pos.ring):shortest=1[t1];" +
            "[t1][face]overlay=\(pos.face),\(drawtext(fontsize: 16)),\(paletteChain)"
        return ["-y", "-i", tmpScreen, "-i", tmpFace, "-filter_complex", filter, "-loop", "0", out]
    }

    // MARK: - 헬퍼

    static func dateDir(for date: Date = Date()) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return Settings.outputDir.appendingPathComponent(f.string(from: date))
    }

    private static func checkDiskSpace() throws {
        let dir = Settings.outputDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage, free < 500_000_000 {
            throw CaptureError.lowDiskSpace
        }
    }

    /// manifest.jsonl — LLM/봇 파이프라인(v0.3 일일 요약)의 입력.
    /// schema=1: ts(ISO8601), trigger, duration(초), sources(활성 소스),
    /// files(파일명 배열), kinds(파일명→종류: screen|face|combo)
    private static func appendManifest(dir: URL, ts: Date, files: [String], duration: Int,
                                       trigger: String, sources: [String]) throws {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var kinds: [String: String] = [:]
        for f in files {
            if f.hasSuffix("_screen.gif") { kinds[f] = "screen" }
            else if f.hasSuffix("_face.gif") { kinds[f] = "face" }
            else if f.hasSuffix("_combo.gif") { kinds[f] = "combo" }
        }
        let entry: [String: Any] = [
            "schema": 1,
            "ts": iso.string(from: ts),
            "files": files,
            "kinds": kinds,
            "sources": sources,
            "duration": duration,
            "trigger": trigger,
        ]
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        var line = String(data: data, encoding: .utf8)!
        line += "\n"
        let manifest = dir.appendingPathComponent("manifest.jsonl")
        if let h = FileHandle(forWritingAtPath: manifest.path) {
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line.data(using: .utf8)!)
        } else {
            try line.data(using: .utf8)!.write(to: manifest)
        }
    }

    private static func cleanupTmp() {
        try? FileManager.default.removeItem(atPath: tmpScreen)
        try? FileManager.default.removeItem(atPath: tmpFace)
        try? FileManager.default.removeItem(atPath: tsFile)
    }

    private static func fileOK(_ path: String) -> Bool { fileSize(path) > 0 }

    private static func fileSize(_ path: String) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int) ?? 0
    }
}
