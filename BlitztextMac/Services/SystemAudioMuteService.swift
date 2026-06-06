import AppKit
import CoreAudio
import Foundation

/// Schaltet das Standard-Audioausgabegerät (Systemausgabe) per CoreAudio stumm und
/// stellt es nach der Aufnahme wieder her. Wird genutzt, um Hintergrundmusik
/// (Apple Music, Spotify, Browser-Audio ...) während eines Diktats automatisch
/// stummzuschalten. Funktioniert systemweit und braucht keine zusätzlichen
/// macOS-Berechtigungen.
///
/// Robustheit: Schlägt ein CoreAudio-Aufruf fehl, passiert einfach nichts –
/// kein Crash, keine Fehlermeldung an den Nutzer.
final class SystemAudioMuteService {
    static let shared = SystemAudioMuteService()

    /// Spiegelt die Einstellung `muteMusicWhileRecording`. Wird von `AppState` gesetzt.
    var isEnabled: Bool = false

    /// Merkt sich, ob WIR stummgeschaltet haben. Nur dann wird wiederhergestellt,
    /// damit eine vom Nutzer selbst gewollte Stummschaltung nicht aufgehoben wird.
    private var didMute = false

    private init() {
        // Sicherheitsnetz: Beim Beenden der App Ton in jedem Fall wiederherstellen,
        // damit nie versehentlich dauerhaft stummgeschaltet bleibt.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreOutput()
        }
    }

    /// Schaltet die Systemausgabe stumm – nur wenn aktiviert und nicht bereits stumm.
    func muteOutput() {
        guard isEnabled, !didMute else { return }
        guard let deviceID = defaultOutputDevice(), isMuteSettable(deviceID) else { return }

        // Vorherigen Zustand merken: ist schon stumm? Dann nichts tun.
        guard let currentlyMuted = readMute(deviceID) else { return }
        if currentlyMuted { return }

        if writeMute(deviceID, mute: true) {
            didMute = true
        }
    }

    /// Stellt die Systemausgabe wieder her – nur wenn WIR vorher stummgeschaltet haben.
    func restoreOutput() {
        guard didMute else { return }
        didMute = false
        guard let deviceID = defaultOutputDevice() else { return }
        _ = writeMute(deviceID, mute: false)
    }

    // MARK: - CoreAudio Helpers

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isMuteSettable(_ deviceID: AudioDeviceID) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    private func readMute(_ deviceID: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { return nil }
        return muted != 0
    }

    @discardableResult
    private func writeMute(_ deviceID: AudioDeviceID, mute: Bool) -> Bool {
        var address = muteAddress()
        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        return status == noErr
    }
}
