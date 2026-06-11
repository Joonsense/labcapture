import Foundation

/// UserDefaults 키 — SettingsView의 @AppStorage와 엔진 코드가 공유한다.
enum SK {
    static let intervalMinutes   = "intervalMinutes"     // 캡처 주기 (분)
    static let durationSeconds   = "durationSeconds"     // 캡처 길이 (초)
    static let preNotify         = "preNotify"           // 사전 알림 사용
    static let preNotifyLead     = "preNotifyLead"       // 사전 알림 리드타임 (초)
    static let webcamEnabled     = "webcamEnabled"       // 웹캠 캡처 사용
    static let pipPosition       = "pipPosition"         // tl/tr/bl/br
    static let gifFps            = "gifFps"
    static let screenGifWidth    = "screenGifWidth"
    static let outputDir         = "outputDir"
    static let keepOriginals     = "keepOriginals"       // 원본 mp4 보존
    static let pauseSchedule     = "pauseSchedule"       // 일시정지 스케줄 사용
    static let pauseStartMin     = "pauseStartMin"       // 0~1439 (분 단위)
    static let pauseEndMin       = "pauseEndMin"
    static let hotkeyKeyCode     = "hotkeyKeyCode"
    static let hotkeyModifiers   = "hotkeyModifiers"     // Carbon modifier flags
    static let screenDeviceIndex = "screenDeviceIndex"   // avfoundation 인덱스 (-1 = 미탐지)
    static let camDeviceIndex    = "camDeviceIndex"
    static let onboardingDone    = "onboardingDone"
    static let screenSourceOn    = "screenSourceOn"      // 빠른 토글: 화면 소스
    static let faceSourceOn      = "faceSourceOn"        // 빠른 토글: 얼굴(웹캠) 소스
    static let ocrGuard          = "ocrGuard"            // 민감정보 OCR 가드
    static let ocrPauseHours     = "ocrPauseHours"       // 3연속 폐기 시 중단 시간
    static let qualityMigrated   = "qualityMigratedV4"   // v0.4 고화질 마이그레이션 완료
}

enum Settings {
    static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            SK.intervalMinutes: 20,
            SK.durationSeconds: 3,
            SK.preNotify: true,
            SK.preNotifyLead: 3,
            SK.webcamEnabled: true,
            SK.pipPosition: "br",
            SK.gifFps: 15,
            SK.screenGifWidth: 960,
            SK.outputDir: NSString("~/LabCapture").expandingTildeInPath,
            SK.keepOriginals: true,
            SK.pauseSchedule: false,
            SK.pauseStartMin: 21 * 60,   // 21:00
            SK.pauseEndMin: 9 * 60,      // 09:00
            SK.hotkeyKeyCode: 8,         // C
            SK.hotkeyModifiers: 256 + 2048 + 4096, // cmd + option + control
            SK.screenDeviceIndex: -1,
            SK.camDeviceIndex: -1,
            SK.onboardingDone: false,
            SK.screenSourceOn: true,
            SK.faceSourceOn: true,
            SK.ocrGuard: true,
            SK.ocrPauseHours: 2,
        ])
        migrateQualityV4()
    }

    /// v0.4 고화질 마이그레이션 (1회): 캡처 3초 + 원본 mp4 보존(고화질 타임랩스 재료) +
    /// GIF fps/폭 상향. 기존에 저장된 구버전 값을 새 기본값으로 끌어올린다.
    private static func migrateQualityV4() {
        guard !d.bool(forKey: SK.qualityMigrated) else { return }
        if d.object(forKey: SK.durationSeconds) != nil, d.integer(forKey: SK.durationSeconds) < 3 {
            d.set(3, forKey: SK.durationSeconds)
        }
        d.set(true, forKey: SK.keepOriginals)
        if d.object(forKey: SK.gifFps) != nil, d.integer(forKey: SK.gifFps) < 15 {
            d.set(15, forKey: SK.gifFps)
        }
        if d.object(forKey: SK.screenGifWidth) != nil, d.integer(forKey: SK.screenGifWidth) < 960 {
            d.set(960, forKey: SK.screenGifWidth)
        }
        d.set(true, forKey: SK.qualityMigrated)
    }

    static var intervalMinutes: Int { clamp(d.integer(forKey: SK.intervalMinutes), 5, 120) }
    static var durationSeconds: Int { clamp(d.integer(forKey: SK.durationSeconds), 1, 5) }
    static var preNotify: Bool { d.bool(forKey: SK.preNotify) }
    static var preNotifyLead: Int { clamp(d.integer(forKey: SK.preNotifyLead), 0, 10) }
    static var webcamEnabled: Bool { d.bool(forKey: SK.webcamEnabled) }
    static var pipPosition: String { d.string(forKey: SK.pipPosition) ?? "br" }
    static var gifFps: Int { clamp(d.integer(forKey: SK.gifFps), 8, 15) }
    static var screenGifWidth: Int { clamp(d.integer(forKey: SK.screenGifWidth), 480, 1080) }
    static var outputDir: URL {
        URL(fileURLWithPath: d.string(forKey: SK.outputDir) ?? NSString("~/LabCapture").expandingTildeInPath)
    }
    static var keepOriginals: Bool { d.bool(forKey: SK.keepOriginals) }
    static var pauseSchedule: Bool { d.bool(forKey: SK.pauseSchedule) }
    static var pauseStartMin: Int { d.integer(forKey: SK.pauseStartMin) }
    static var pauseEndMin: Int { d.integer(forKey: SK.pauseEndMin) }
    static var hotkeyKeyCode: Int { d.integer(forKey: SK.hotkeyKeyCode) }
    static var hotkeyModifiers: Int { d.integer(forKey: SK.hotkeyModifiers) }
    static var screenDeviceIndex: Int { d.object(forKey: SK.screenDeviceIndex) == nil ? -1 : d.integer(forKey: SK.screenDeviceIndex) }
    static var camDeviceIndex: Int { d.object(forKey: SK.camDeviceIndex) == nil ? -1 : d.integer(forKey: SK.camDeviceIndex) }
    static var onboardingDone: Bool { d.bool(forKey: SK.onboardingDone) }
    static var screenSourceOn: Bool { d.bool(forKey: SK.screenSourceOn) }
    static var faceSourceOn: Bool { d.bool(forKey: SK.faceSourceOn) }

    /// 실효 소스 상태 (설정 + 빠른 토글 결합)
    static var effectiveScreenOn: Bool { screenSourceOn }
    static var effectiveFaceOn: Bool { webcamEnabled && faceSourceOn }

    static var ocrGuard: Bool { d.bool(forKey: SK.ocrGuard) }
    static var ocrPauseHours: Int { clamp(d.integer(forKey: SK.ocrPauseHours), 1, 12) }

    /// 일시정지 스케줄 구간 안인지 (자정 넘김 지원: 21:00~09:00)
    static func isInPauseSchedule(_ date: Date = Date()) -> Bool {
        guard pauseSchedule else { return false }
        let cal = Calendar.current
        let comp = cal.dateComponents([.hour, .minute], from: date)
        let nowMin = (comp.hour ?? 0) * 60 + (comp.minute ?? 0)
        let start = pauseStartMin, end = pauseEndMin
        if start == end { return false }
        if start < end { return nowMin >= start && nowMin < end }
        return nowMin >= start || nowMin < end // 자정 넘김
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
}
