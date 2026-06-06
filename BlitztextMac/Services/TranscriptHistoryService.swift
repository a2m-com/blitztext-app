import Foundation
import Observation

/// Ein einzelner Verlaufseintrag: nur Zeitpunkt und reiner Text.
struct TranscriptHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String

    init(id: UUID = UUID(), date: Date = Date(), text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

/// Lokaler Verlauf der zuletzt erzeugten Texte – ein Sicherheitsnetz, falls das Einfügen
/// fehlschlägt, der Nutzer wegklickt oder eine Übertragung abreißt.
///
/// Performance: Es wird ausschließlich NACH Fertigstellung eines Textes geschrieben –
/// niemals während Aufnahme oder Einfügen. Gespeichert wird nur reiner Text in einer
/// kleinen JSON-Datei. Die Aufnahme- und Einfüge-Geschwindigkeit bleibt unberührt.
@Observable
@MainActor
final class TranscriptHistoryService {
    /// Neueste Einträge zuerst.
    private(set) var entries: [TranscriptHistoryEntry] = []

    /// Höchstzahl gespeicherter Einträge – ältere fallen automatisch heraus,
    /// damit der Verlauf nie unkontrolliert wächst.
    private let maxEntries = 100

    private let fileURL = AppSupportPaths.historyURL

    init() {
        load()
    }

    /// Fügt einen fertigen Text vorne hinzu (nur nicht-leere Texte).
    func add(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        entries.insert(TranscriptHistoryEntry(text: text), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    /// Löscht den gesamten Verlauf.
    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([TranscriptHistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL)
        }
    }
}
