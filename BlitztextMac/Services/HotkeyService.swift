import Cocoa
import Observation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold    // Tasten halten = aufnehmen, loslassen = stoppen
    case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Halten"
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
        case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
        }
    }
}

enum HotkeyEvent {
    case down(WorkflowType)  // Kürzel ausgelöst (Tasten/Maustaste gedrückt)
    case up(WorkflowType)    // Kürzel losgelassen (für Halten-Modus)
    case cancel              // Escape gedrückt
}

@Observable
@MainActor
final class HotkeyService {
    private var monitors: [Any] = []

    /// Welche Quelle hat das aktuell aktive Kürzel ausgelöst?
    private enum TriggerSource { case modifier, key, mouse }
    private var activeType: WorkflowType?
    private var activeSource: TriggerSource?
    private var activeKeyCode: UInt16?
    private var activeButton: Int?

    /// Aktuell gültige Belegung pro Workflow. Wird von `AppState` aktuell gehalten.
    var bindings: [WorkflowType: HotkeyBinding] = HotkeyBinding.defaults()

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    func start() {
        stop() // doppelte Monitore vermeiden
        addBoth(.flagsChanged) { [weak self] event in self?.handleFlags(event) }
        addBoth(.keyDown) { [weak self] event in self?.handleKeyDown(event) }
        addBoth(.keyUp) { [weak self] event in self?.handleKeyUp(event) }
        addBoth(.otherMouseDown) { [weak self] event in self?.handleMouseDown(event) }
        addBoth(.otherMouseUp) { [weak self] event in self?.handleMouseUp(event) }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        resetActive()
    }

    /// Registriert einen globalen (andere Apps) und einen lokalen (eigene App) Monitor.
    private func addBoth(_ mask: NSEvent.EventTypeMask, _ body: @escaping @MainActor (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor in body(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor in body(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    // MARK: - Tastatur (Modifier)

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Passt eine reine Modifier-Kombination exakt?
        if let match = bindings.first(where: { $0.value.matchesModifierOnly(flags: flags) }) {
            if activeType == nil {
                beginTrigger(match.key, source: .modifier)
            }
            return
        }

        // Keine Modifier-Kombination trifft mehr -> aktives Halten beenden.
        if activeSource == .modifier {
            endTrigger()
        }
    }

    // MARK: - Tastatur (Einzeltaste)

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape bricht immer ab
            handleEscape()
            return
        }
        guard activeType == nil else { return } // kein Auto-Repeat erneut auslösen
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let match = bindings.first(where: { $0.value.matchesKey(keyCode: event.keyCode, flags: flags) }) {
            activeKeyCode = event.keyCode
            beginTrigger(match.key, source: .key)
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard activeSource == .key, event.keyCode == activeKeyCode else { return }
        endTrigger()
    }

    // MARK: - Maus-Zusatztasten

    private func handleMouseDown(_ event: NSEvent) {
        let button = event.buttonNumber
        // Nur Zusatztasten ab der dritten Taste. Links/Rechts kommen ohnehin nicht
        // als .otherMouseDown an und werden hier zusätzlich ausgeschlossen.
        guard button >= 2 else { return }
        guard activeType == nil else { return }
        if let match = bindings.first(where: { $0.value.matchesMouse(button: button) }) {
            activeButton = button
            beginTrigger(match.key, source: .mouse)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard activeSource == .mouse, event.buttonNumber == activeButton else { return }
        endTrigger()
    }

    // MARK: - Auslösen / Beenden

    private func beginTrigger(_ type: WorkflowType, source: TriggerSource) {
        activeType = type
        activeSource = source
        onHotkeyEvent?(.down(type))
    }

    private func endTrigger() {
        guard let type = activeType else { return }
        resetActive()
        onHotkeyEvent?(.up(type))
    }

    private func handleEscape() {
        resetActive()
        onHotkeyEvent?(.cancel)
    }

    private func resetActive() {
        activeType = nil
        activeSource = nil
        activeKeyCode = nil
        activeButton = nil
    }
}
