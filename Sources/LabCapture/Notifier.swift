import Foundation
import UserNotifications

/// macOS 알림 래퍼. 번들 없이(bare 실행파일) 실행될 때는 크래시 대신 no-op.
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func show(_ title: String, body: String = "") {
        guard available else { NSLog("LabCapture 알림: \(title) \(body)"); return }
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    static func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        guard available else { completion(.denied); return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus) }
        }
    }
}
