import AppKit

/// Ein frei belegbares Tastenkürzel für einen Workflow. Entweder eine
/// Tastatur-Kombination (Modifier wie fn/Ctrl/Option/Shift/Cmd, optional plus
/// eine einzelne Taste) oder eine Maus-Zusatztaste (ab der dritten Taste).
///
/// Robustheit: Ein leeres/ungültiges Binding löst einfach nichts aus.
struct HotkeyBinding: Codable, Equatable {
    enum Kind: String, Codable {
        case keyboard
        case mouse
    }

    var kind: Kind
    /// Roh-Wert von `NSEvent.ModifierFlags` (nur die geräteunabhängigen Flags).
    var modifierFlags: UInt
    /// Bei Tastatur: optionaler Tastencode. `nil` = reine Modifier-Kombination.
    var keyCode: UInt16?
    /// Bei Maus: `buttonNumber` (2 = dritte Taste, 3 = vierte Taste ...).
    var mouseButton: Int?

    // MARK: - Komfort-Konstruktoren

    static func keyboard(_ flags: NSEvent.ModifierFlags, keyCode: UInt16? = nil) -> HotkeyBinding {
        HotkeyBinding(
            kind: .keyboard,
            modifierFlags: flags.intersection(.deviceIndependentFlagsMask).rawValue,
            keyCode: keyCode,
            mouseButton: nil
        )
    }

    static func mouse(button: Int) -> HotkeyBinding {
        HotkeyBinding(kind: .mouse, modifierFlags: 0, keyCode: nil, mouseButton: button)
    }

    // MARK: - Abgeleitete Werte

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
    }

    /// Kann nie auslösen (keine Modifier, keine Taste, keine Maustaste).
    var isEmpty: Bool {
        switch kind {
        case .mouse:
            return mouseButton == nil
        case .keyboard:
            return flags.isEmpty && keyCode == nil
        }
    }

    /// Eine normale Schreibtaste ohne Modifier (löst beim Tippen ständig aus).
    /// F-Tasten (F1–F19) gelten nicht als Schreibtaste und sind in Ordnung.
    var isBareTypingKey: Bool {
        guard kind == .keyboard, let keyCode, flags.isEmpty else { return false }
        return !Self.functionKeyCodes.contains(keyCode)
    }

    // MARK: - Treffer-Prüfung (für den HotkeyService)

    /// Reine Modifier-Kombination ohne Einzeltaste (z. B. fn + Shift).
    func matchesModifierOnly(flags currentFlags: NSEvent.ModifierFlags) -> Bool {
        kind == .keyboard && keyCode == nil && !flags.isEmpty && flags == currentFlags
    }

    /// Einzeltaste (mit oder ohne Modifier), z. B. Ctrl + F5 oder F5.
    func matchesKey(keyCode kc: UInt16, flags currentFlags: NSEvent.ModifierFlags) -> Bool {
        kind == .keyboard && keyCode == kc && flags == currentFlags
    }

    func matchesMouse(button: Int) -> Bool {
        kind == .mouse && mouseButton == button
    }

    // MARK: - Anzeige

    var displayString: String {
        switch kind {
        case .mouse:
            if let mouseButton {
                // buttonNumber 2 = physisch dritte Taste -> "Maustaste 3"
                return "Maustaste \(mouseButton + 1)"
            }
            return "—"
        case .keyboard:
            var parts: [String] = []
            let f = flags
            if f.contains(.function) { parts.append("fn") }
            if f.contains(.control) { parts.append("Ctrl") }
            if f.contains(.option) { parts.append("Option") }
            if f.contains(.shift) { parts.append("Shift") }
            if f.contains(.command) { parts.append("Cmd") }
            if f.contains(.capsLock) { parts.append("CapsLock") }
            if let keyCode { parts.append(Self.keyName(for: keyCode)) }
            return parts.isEmpty ? "—" : parts.joined(separator: " + ")
        }
    }

    // MARK: - Standardwerte (= bisherige fest verdrahtete Kürzel)

    static func defaults() -> [WorkflowType: HotkeyBinding] {
        [
            .transcription: .keyboard([.function, .shift]),
            .localTranscription: .keyboard([.function, .shift, .control]),
            .textImprover: .keyboard([.function, .control]),
            .dampfAblassen: .keyboard([.function, .option]),
            .emojiText: .keyboard([.function, .command]),
        ]
    }

    static func `default`(for type: WorkflowType) -> HotkeyBinding {
        defaults()[type] ?? .keyboard([.function])
    }

    // MARK: - Tastencodes

    /// Tastencodes der F-Tasten F1–F19 (gelten ohne Modifier als unkritisch).
    static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        105, 107, 113, 106, 64, 79, 80,                          // F13–F19
    ]

    static func keyName(for keyCode: UInt16) -> String {
        if let name = namedKeys[keyCode] { return name }
        return "Taste \(keyCode)"
    }

    private static let namedKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        49: "Leertaste", 36: "Enter", 48: "Tab", 51: "Löschen", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
    ]
}
