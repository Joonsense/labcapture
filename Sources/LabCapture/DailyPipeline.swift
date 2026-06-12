import AppKit
import Foundation

/// v0.3 일일 파이프라인: 타임랩스 컴파일 + Claude API 일일 요약.
enum DailyPipeline {

    // MARK: - 클립보드 복사 (X 업로드 헬퍼)

    /// 마지막 combo.gif를 클립보드에 파일로 복사 — X 작성창에 ⌘V로 바로 붙는다.
    @discardableResult
    static func copyToClipboard(url: URL) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([url as NSURL])
    }

    // MARK: - 일일 타임랩스

    static let tlTsFile = "/tmp/labcap_tl_ts.txt"
    static let tlW = 1920, tlH = 1080, tlFps = 30
    static let tlFaceDiameter = 320 // 원형 face 지름 (1080p 기준)

    /// 해당 날짜 폴더의 캡처들을 시간순으로 이어붙여 고화질 타임랩스 mp4 생성.
    /// v0.4: 원본 mp4 기반 (screen 배경 그대로 + face 원형을 화면 중앙에 오버레이, 1080p crf18).
    /// 원본 mp4가 없는 구버전 폴더는 GIF concat으로 폴백.
    static func buildTimelapse(for date: Date = Date()) async throws -> URL {
        let dir = CaptureEngine.dateDir(for: date)
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []

        let nameFmt = DateFormatter()
        nameFmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let out = dir.appendingPathComponent("timelapse_\(nameFmt.string(from: Date())).mp4")

        let screens = entries.filter { $0.hasSuffix("_screen.mp4") }.sorted()
        guard !screens.isEmpty else {
            return try await buildTimelapseFromGifs(dir: dir, entries: entries, out: out)
        }

        // ── 1. 캡처별 세그먼트 정규화 인코딩 (1080p/30fps 통일 → concat copy 가능) ──
        var segs: [String] = []
        defer {
            for s in segs { try? fm.removeItem(atPath: s) }
            try? fm.removeItem(atPath: tlTsFile)
        }

        for (i, name) in screens.enumerated() {
            let base = String(name.dropLast("_screen.mp4".count))
            let facePath = dir.appendingPathComponent("\(base)_face.mp4").path
            let seg = "/tmp/labcap_seg_\(i).mp4"

            // 구간별 타임스탬프 (파일명에서 캡처 시각 복원)
            try tsLabel(base: base, dir: dir).data(using: .utf8)!
                .write(to: URL(fileURLWithPath: tlTsFile))

            let bg = "[0:v]fps=\(tlFps),scale=\(tlW):\(tlH):force_original_aspect_ratio=decrease:flags=lanczos," +
                "pad=\(tlW):\(tlH):(ow-iw)/2:(oh-ih)/2[bg]"
            let ts = CaptureEngine.drawtext(fontsize: 28, textfile: tlTsFile)

            var args = ["-y", "-i", dir.appendingPathComponent(name).path]
            let filter: String
            if fm.fileExists(atPath: facePath) {
                args += ["-i", facePath]
                // face를 원형으로 화면 정중앙에 오버레이, screen은 배경 그대로
                filter = bg + ";" +
                    CaptureEngine.circleFilter(input: "1:v", diameter: tlFaceDiameter, fps: tlFps, out: "face") + ";" +
                    "[bg][face]overlay=(W-w)/2:(H-h)/2,\(ts)"
            } else {
                filter = bg + ";[bg]\(ts)"
            }
            args += ["-filter_complex", filter,
                     "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
                     "-pix_fmt", "yuv420p", "-r", "\(tlFps)", seg]

            let r = await FFmpeg.run(args, timeout: 120)
            guard r.ok else {
                throw NSError(domain: "LabCapture", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Timelapse segment encoding failed (\(name)):\n\(r.tail)"])
            }
            segs.append(seg)
        }

        // ── 2. 무손실 concat (세그먼트 인코딩 파라미터 동일 → -c copy) ──
        let listPath = "/tmp/labcap_timelapse_list.txt"
        try segs.map { "file '\($0)'" }.joined(separator: "\n")
            .write(toFile: listPath, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(atPath: listPath) }

        let r = await FFmpeg.run([
            "-y", "-f", "concat", "-safe", "0", "-i", listPath, "-c", "copy", out.path,
        ], timeout: 120)
        guard r.ok else {
            throw NSError(domain: "LabCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Timelapse concat failed:\n\(r.tail)"])
        }
        return out
    }

    /// 파일명 base에서 타임스탬프 라벨 복원 — "yyyy-MM-dd_HHmmss"(v0.4) 또는 "HHmmss"(구버전)
    private static func tsLabel(base: String, dir: URL) -> String {
        let comps = base.split(separator: "_")
        let datePart = comps.count >= 2 ? String(comps[0]) : dir.lastPathComponent
        let timePart = String(comps.last ?? "")
        guard timePart.count == 6, Int(timePart) != nil else { return datePart }
        let h = timePart.prefix(2)
        let m = timePart.dropFirst(2).prefix(2)
        let s = timePart.suffix(2)
        return "\(datePart) \(h):\(m):\(s)"
    }

    /// 구버전 폴백: 원본 mp4가 없는 날짜 폴더는 screen.gif concat (저화질)
    private static func buildTimelapseFromGifs(dir: URL, entries: [String], out: URL) async throws -> URL {
        let gifs = entries.filter { $0.hasSuffix("_screen.gif") }.sorted()
        guard !gifs.isEmpty else {
            throw NSError(domain: "LabCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No original mp4/screen.gif captured today."])
        }
        let listPath = "/tmp/labcap_timelapse_list.txt"
        let list = gifs.map { "file '\(dir.appendingPathComponent($0).path.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n")
        try list.write(toFile: listPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: listPath) }

        let r = await FFmpeg.run([
            "-y", "-f", "concat", "-safe", "0", "-i", listPath,
            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=12",
            "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
            out.path,
        ], timeout: 300)
        guard r.ok else {
            throw NSError(domain: "LabCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Timelapse encoding failed:\n\(r.tail)"])
        }
        return out
    }

    // MARK: - Claude API 일일 요약

    /// API 키 로딩: 환경변수 → ~/.config/labcapture/anthropic_api_key 파일 순.
    /// (하드코딩 금지 원칙. 파일은 chmod 600 권장, git 추적 안 됨)
    static var apiKey: String? {
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        let keyFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/labcapture/anthropic_api_key")
        if let k = try? String(contentsOf: keyFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
            return k
        }
        return nil
    }

    static let summaryModel = "claude-opus-4-8"

    /// manifest.jsonl + combo 프레임 몇 장을 Claude에 보내 일일 빌딩 일지(summary.md) 생성.
    static func buildSummary(for date: Date = Date()) async throws -> URL {
        guard let key = apiKey else {
            throw NSError(domain: "LabCapture", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "No Anthropic API key found. In Terminal:\nmkdir -p ~/.config/labcapture && printf '%s' 'sk-ant-...' > ~/.config/labcapture/anthropic_api_key && chmod 600 ~/.config/labcapture/anthropic_api_key"])
        }
        let dir = CaptureEngine.dateDir(for: date)
        let manifestPath = dir.appendingPathComponent("manifest.jsonl")
        guard let manifest = try? String(contentsOf: manifestPath, encoding: .utf8), !manifest.isEmpty else {
            throw NSError(domain: "LabCapture", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "No manifest.jsonl for today."])
        }

        // combo.gif에서 최대 6장의 대표 프레임 추출 (시간순 균등 샘플) → base64 PNG
        let fm = FileManager.default
        let combos = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix("_combo.gif") }.sorted()
        let sampled = sample(combos, max: 6)
        var imageBlocks: [[String: Any]] = []
        for (i, name) in sampled.enumerated() {
            let png = "/tmp/labcap_sum_\(i).png"
            let r = await FFmpeg.run([
                "-y", "-i", dir.appendingPathComponent(name).path,
                "-frames:v", "1", "-vf", "scale=720:-1", "-update", "1", png,
            ], timeout: 30)
            guard r.ok, let data = fm.contents(atPath: png) else { continue }
            imageBlocks.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/png",
                           "data": data.base64EncodedString()],
            ])
            imageBlocks.append(["type": "text", "text": "↑ \(name) (capture time is the timestamp in the bottom-left corner)"])
            try? fm.removeItem(atPath: png)
        }

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let prompt = """
        You are an assistant that writes a solo founder's building work journal.
        Below is today's (\(dayFmt.string(from: date))) manifest.jsonl from the automatic capture system (LabCapture) and \
        representative screen captures. Read the screen images to figure out what work (coding/docs/terminal/browser, etc.) was being done.

        manifest.jsonl (one line per capture, ts=time, trigger=how it fired):
        ```
        \(manifest)
        ```

        Write in English, conclusion first, in Markdown:
        1. **One-line summary of today**
        2. **Timeline** — what was worked on by time of day (based on capture times)
        3. **Content ideas** — 1-2 moments worth posting on X (Twitter) plus a draft caption
        Don't exaggerate — base everything only on what's actually visible in the images.
        """

        var content: [[String: Any]] = imageBlocks
        content.append(["type": "text", "text": prompt])

        let body: [String: Any] = [
            "model": summaryModel,
            "max_tokens": 2048,
            "messages": [["role": "user", "content": content]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 180
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let errText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LabCapture", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Claude API error (\((resp as? HTTPURLResponse)?.statusCode ?? -1)):\n\(errText.prefix(300))"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw NSError(domain: "LabCapture", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        guard !text.isEmpty else {
            let stop = json["stop_reason"] as? String ?? "unknown"
            throw NSError(domain: "LabCapture", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Empty response (stop_reason=\(stop))"])
        }

        let out = dir.appendingPathComponent("summary.md")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    /// 배열에서 시간순 균등 샘플 n개
    private static func sample<T>(_ arr: [T], max n: Int) -> [T] {
        guard arr.count > n else { return arr }
        let step = Double(arr.count) / Double(n)
        return (0..<n).map { arr[Int(Double($0) * step)] }
    }
}
