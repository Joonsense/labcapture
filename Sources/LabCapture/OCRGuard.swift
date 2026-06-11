import Foundation
import Vision

/// 민감정보 OCR 가드 (v0.2).
/// 녹화된 화면 mp4에서 프레임을 추출해 Vision OCR로 텍스트를 읽고,
/// API 키·토큰·비밀번호 패턴이 보이면 해당 캡처를 통째로 폐기하게 한다.
/// (부분 블러는 모든 프레임에서 영역 추적이 필요해 한 프레임만 놓쳐도 유출 —
///  통폐기가 안전하다. 폐기 정책은 AppModel이 담당.)
enum OCRGuard {
    /// (패턴 이름, 정규식) — OCR이 -를 =로, l을 1로 오인식하는 경우가 있어
    /// 구분자는 [-=_] 허용, 본문 문자 클래스도 약간 느슨하게 잡는다 (가드는 과잉 감지가 안전)
    private static let patterns: [(name: String, regex: String)] = [
        ("Anthropic/OpenAI key", #"sk[-=][A-Za-z0-9_=-]{16,}"#),
        ("GitHub token", #"(ghp|gho|ghu|ghs|ghr)[-=_][A-Za-z0-9]{20,}"#),
        ("GitHub PAT", #"github[-=_]pat[-=_][A-Za-z0-9_]{20,}"#),
        ("AWS access key", #"AKIA[0-9A-Z]{16}"#),
        ("Slack token", #"xox[bpars][-=][A-Za-z0-9=-]{10,}"#),
        ("Private key block", #"BEGIN [A-Z ]*PRIVATE KEY"#),
        ("JWT", #"eyJ[A-Za-z0-9_=-]{14,}\.eyJ"#),
        ("Webhook secret", #"whsec[-=_][A-Za-z0-9]{16,}"#),
        ("Notion token", #"ntn[-=_][A-Za-z0-9]{16,}"#),
        ("Bearer token", #"Bearer [A-Za-z0-9._~+/=-]{30,}"#),
        ("DB connection string", #"(postgres(ql)?|mysql|mongodb(\+srv)?)://[^\s/]+:[^\s@]+@"#),
        ("Env secret assignment", #"(API_KEY|SECRET|TOKEN|PASSWORD|PASSWD)\s*=\s*['"]?[^\s'"]{12,}"#),
    ]

    private static let framePrefix = "/tmp/labcap_ocr_"

    /// 화면 mp4를 스캔해 감지된 패턴 이름 목록을 반환 (비면 안전).
    static func scan(videoPath: String) async -> [String] {
        cleanupFrames()
        defer { cleanupFrames() }

        // 2fps로 프레임 추출 (2초 녹화 → 최대 ~5장), OCR 정확도를 위해 원본 해상도 유지
        let r = await FFmpeg.run([
            "-y", "-i", videoPath, "-vf", "fps=2", "-frames:v", "6",
            "\(framePrefix)%02d.png",
        ], timeout: 30)
        guard r.ok else { return [] } // 추출 실패 시 가드 통과 (캡처 자체를 막지 않음)

        let debug = ProcessInfo.processInfo.environment["LABCAP_OCR_DEBUG"] == "1"
        var hits = Set<String>()
        for i in 1...6 {
            let path = String(format: "%@%02d.png", framePrefix, i)
            guard FileManager.default.fileExists(atPath: path) else { break }
            var text = recognizeText(at: path)
            // OCR이 하이픈을 en/em 대시·민ус로 읽는 경우가 있어 정규화
            text = text.replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-")
                .replacingOccurrences(of: "−", with: "-")
            if debug { FileHandle.standardError.write("--- frame \(i) OCR ---\n\(text)\n".data(using: .utf8)!) }
            guard !text.isEmpty else { continue }
            for p in patterns where text.range(of: p.regex, options: .regularExpression) != nil {
                hits.insert(p.name)
            }
            if !hits.isEmpty { break } // 한 프레임이라도 걸리면 폐기 확정
        }
        return Array(hits).sorted()
    }

    private static func recognizeText(at path: String) -> String {
        guard let url = URL(string: "file://" + path),
              let handler = try? VNImageRequestHandler(url: url) as VNImageRequestHandler?
        else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // 키 문자열을 단어로 "교정"하지 않도록
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    private static func cleanupFrames() {
        for i in 1...10 {
            try? FileManager.default.removeItem(atPath: String(format: "%@%02d.png", framePrefix, i))
        }
    }
}
