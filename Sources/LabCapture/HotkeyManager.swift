import AppKit
import Carbon.HIToolbox

/// Carbon RegisterEventHotKey 기반 전역 단축키. 접근성 권한 불필요.
final class HotkeyManager {
    static var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    private static var handlerInstalled = false

    func register(keyCode: Int, carbonModifiers: Int) {
        unregister()
        Self.installOnce()
        let hkid = EventHotKeyID(signature: OSType(0x4C43_4150), id: 1) // 'LCAP'
        RegisterEventHotKey(UInt32(keyCode), UInt32(carbonModifiers), hkid,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }

    private static func installOnce() {
        guard !handlerInstalled else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotkeyManager.handler?() }
            return noErr
        }, 1, &type, nil, nil)
        handlerInstalled = true
    }

    // MARK: - 표시/변환 유틸

    /// NSEvent modifier flags → Carbon modifier flags
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    static func displayString(keyCode: Int, carbonModifiers: Int) -> String {
        var s = ""
        if carbonModifiers & controlKey != 0 { s += "⌃" }
        if carbonModifiers & optionKey != 0 { s += "⌥" }
        if carbonModifiers & shiftKey != 0 { s += "⇧" }
        if carbonModifiers & cmdKey != 0 { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    static func keyName(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
            46: "M", 47: ".", 50: "`", 49: "Space", 36: "Return", 48: "Tab", 53: "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return map[keyCode] ?? "key\(keyCode)"
    }
}
