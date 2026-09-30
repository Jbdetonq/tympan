import Foundation
import Observation

/// Stockage local : un fichier JSON dans ~/Library/Application Support/Tympan.
@Observable
final class DataStore {
    var data = AppData()
    var lastError: String?

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tympan", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("tympan-data.json")
        load()
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Fichier

    func load() {
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        do {
            data = try Self.makeDecoder().decode(AppData.self, from: raw)
        } catch {
            // Fichier illisible : on le met de côté plutôt que de l'écraser.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("illisible.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            lastError = "Données illisibles, copie de sécurité : \(backup.lastPathComponent)"
        }
    }

    func save() {
        do {
            try Self.makeEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Utilisateurs

    func user(_ id: UUID) -> UserProfile? {
        data.users.first { $0.id == id }
    }

    @discardableResult
    func addUser(name: String, birthYear: Int) -> UUID {
        let user = UserProfile(name: name, birthYear: birthYear)
        data.users.append(user)
        save()
        return user.id
    }

    func deleteUser(_ id: UUID) {
        data.users.removeAll { $0.id == id }
        data.mosquitoGames?.removeAll { $0.userID == id }
        data.pitchGames?.removeAll { $0.userID == id }
        save()
    }

    // MARK: Casques

    func headphone(_ id: UUID?) -> HeadphoneProfile? {
        guard let id else { return nil }
        return data.headphones.first { $0.id == id }
    }

    @discardableResult
    func addHeadphone(name: String, volume: Float) -> HeadphoneProfile {
        let profile = HeadphoneProfile(name: name, volume: volume)
        data.headphones.append(profile)
        save()
        return profile
    }

    // MARK: Sessions

    func add(_ session: TestSession, to userID: UUID) {
        guard let i = data.users.firstIndex(where: { $0.id == userID }) else { return }
        data.users[i].sessions.append(session)
        if data.users[i].reference == nil && !session.noisy && session.format.canConfirm {
            data.users[i].referenceSessionID = session.id
        }
        save()
    }

    func setReference(_ sessionID: UUID, for userID: UUID) {
        guard let i = data.users.firstIndex(where: { $0.id == userID }) else { return }
        data.users[i].referenceSessionID = sessionID
        save()
    }

    func setNote(_ text: String, session sessionID: UUID, of userID: UUID) {
        guard let i = data.users.firstIndex(where: { $0.id == userID }),
              let j = data.users[i].sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let note = TestSession.cleanNote(text)
        guard data.users[i].sessions[j].note != note else { return }
        data.users[i].sessions[j].note = note
        save()
    }

    func deleteSession(_ sessionID: UUID, of userID: UUID) {
        guard let i = data.users.firstIndex(where: { $0.id == userID }) else { return }
        data.users[i].sessions.removeAll { $0.id == sessionID }
        if data.users[i].referenceSessionID == sessionID {
            data.users[i].referenceSessionID = nil
        }
        save()
    }

    // MARK: Chasse au moustique

    var mosquitoGames: [MosquitoRecord] { data.mosquitoGames ?? [] }

    func addMosquitoGame(_ record: MosquitoRecord) {
        var games = data.mosquitoGames ?? []
        guard !games.contains(where: { $0.id == record.id }) else { return }
        games.append(record)
        data.mosquitoGames = games
        save()
    }

    func mosquitoBest(for userID: UUID) -> Int? {
        mosquitoGames.filter { $0.userID == userID }.compactMap(\.bestFrequency).max()
    }

    /// Parties d'un joueur, de la plus ancienne à la plus récente.
    func mosquitoGames(for userID: UUID) -> [MosquitoRecord] {
        mosquitoGames.filter { $0.userID == userID }.sorted { $0.date < $1.date }
    }

    /// Meilleur score de chaque joueur, du plus aigu au plus grave.
    /// Égalité : le premier à avoir atteint ce score passe devant.
    func mosquitoLeaderboard() -> [MosquitoRank] {
        data.users
            .compactMap { u -> MosquitoRank? in
                guard let best = mosquitoBest(for: u.id),
                      let first = mosquitoGames(for: u.id).first(where: { $0.bestFrequency == best })
                else { return nil }
                return MosquitoRank(user: u, best: best, date: first.date)
            }
            .sorted { $0.best != $1.best ? $0.best > $1.best : $0.date < $1.date }
    }

    // MARK: La juste note

    var pitchGames: [PitchRecord] { data.pitchGames ?? [] }

    func addPitchGame(_ record: PitchRecord) {
        var games = data.pitchGames ?? []
        guard !games.contains(where: { $0.id == record.id }) else { return }
        games.append(record)
        data.pitchGames = games
        save()
    }

    func pitchBest(for userID: UUID, level: PitchLevel) -> PitchRecord? {
        pitchGames
            .filter { $0.userID == userID && $0.level == level }
            .reduce(nil as PitchRecord?) { best, r in
                guard let best else { return r }
                return r.beats(best) ? r : best
            }
    }

    /// Parties complètes d'un joueur, tous niveaux.
    func pitchGames(for userID: UUID) -> [PitchRecord] {
        pitchGames.filter { $0.userID == userID }.sorted { $0.date < $1.date }
    }

    /// Meilleure partie de chaque joueur pour un niveau.
    func pitchLeaderboard(level: PitchLevel) -> [PitchRank] {
        data.users
            .compactMap { u in pitchBest(for: u.id, level: level).map { PitchRank(user: u, record: $0) } }
            .sorted { $0.record.beats($1.record) }
    }

    // MARK: Export / import

    func export(to url: URL) throws {
        try Self.makeEncoder().encode(data).write(to: url, options: .atomic)
    }

    /// Fusionne un export venant d'un autre Mac. Renvoie le nombre de sessions ajoutées.
    @discardableResult
    func importFile(from url: URL) throws -> Int {
        let other = try Self.makeDecoder().decode(AppData.self, from: Data(contentsOf: url))
        var added = 0
        for var h in other.headphones where !data.headphones.contains(where: { $0.id == h.id }) {
            // Fichier reçu : volume ramené dans la plage du réglage (10 à 100 %).
            h.volume = h.volume.isFinite ? min(max(h.volume, 0.1), 1) : 0.5
            data.headphones.append(h)
        }
        if let games = other.mosquitoGames {
            var mine = data.mosquitoGames ?? []
            for g in games where !mine.contains(where: { $0.id == g.id }) {
                mine.append(g)
            }
            data.mosquitoGames = mine
        }
        if let games = other.pitchGames {
            var mine = data.pitchGames ?? []
            for g in games where !mine.contains(where: { $0.id == g.id }) {
                mine.append(g)
            }
            data.pitchGames = mine
        }
        for u in other.users {
            if let i = data.users.firstIndex(where: { $0.id == u.id }) {
                for s in u.sessions {
                    if let j = data.users[i].sessions.firstIndex(where: { $0.id == s.id }) {
                        // Session déjà là : on récupère seulement un commentaire ajouté sur l'autre Mac.
                        if data.users[i].sessions[j].note == nil, let note = s.note {
                            data.users[i].sessions[j].note = note
                        }
                    } else {
                        data.users[i].sessions.append(s)
                        added += 1
                    }
                }
                if data.users[i].referenceSessionID == nil {
                    data.users[i].referenceSessionID = u.referenceSessionID
                }
            } else {
                data.users.append(u)
                added += u.sessions.count
            }
        }
        save()
        return added
    }
}
