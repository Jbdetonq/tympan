import Foundation
import SwiftUI

enum Ear: String, Codable, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .right ? "Droite" : "Gauche" }
}

enum EarMode: String, Codable, CaseIterable, Identifiable {
    case both, right, left
    var id: String { rawValue }
    var ears: [Ear] {
        switch self {
        case .both: return [.right, .left]
        case .right: return [.right]
        case .left: return [.left]
        }
    }
}

/// Trois formats adultes (mêmes fréquences, précision croissante) et le format Enfant, court.
enum TestLength: String, Codable, CaseIterable, Identifiable {
    case quick, standard, full, kid
    var id: String { rawValue }

    /// Formats proposés dans Nouveau test (le format Enfant passe par le mode enfant).
    static let adultCases: [TestLength] = [.quick, .standard, .full]

    /// Fréquences communes à tous les formats.
    static let core = [500, 1000, 2000, 3000, 4000, 6000, 8000]

    var frequencies: [Int] {
        switch self {
        case .quick: return Self.core
        case .standard, .full: return [250] + Self.core + [10000]
        case .kid: return [500, 1000, 2000, 4000, 8000]
        }
    }

    /// Niveau maximal présenté (dB app). Plafonné en mode enfant pour protéger les oreilles.
    var maxLevel: Int { self == .kid ? 70 : 90 }

    /// Pas d'affinage autour du seuil (dB).
    var fineStep: Int {
        switch self {
        case .quick, .standard, .kid: return 5
        case .full: return 2
        }
    }

    /// Nombre de fois où le seuil doit être entendu.
    var confirmations: Int {
        switch self {
        case .quick, .kid: return 1
        case .standard: return 2
        case .full: return 3
        }
    }

    /// Bips moyens par fréquence (simulation).
    var trialsPerFrequency: Double {
        switch self {
        case .quick, .kid: return 3.7
        case .standard: return 5.4
        case .full: return 9.0
        }
    }

    /// Le 1 kHz refait en fin de test (contrôle de cohérence).
    var includesRetest: Bool { self == .standard || self == .full }

    /// Un test rapide ne confirme jamais une perte : il invite à refaire un test plus poussé.
    var canConfirm: Bool { self == .standard || self == .full }

    var title: LocalizedStringKey {
        switch self {
        case .quick: return "Rapide"
        case .standard: return "Moyen"
        case .full: return "Complet"
        case .kid: return "Enfant"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .quick: return "7 fréquences, précision 5 dB. Repère un écart à vérifier."
        case .standard: return "9 fréquences (250 Hz à 10 kHz), seuil confirmé 2 fois. Pour le suivi."
        case .full: return "9 fréquences, précision 2 dB, seuil confirmé 3 fois."
        case .kid: return "5 fréquences, plafond 70 dB. Présenté en jeu."
        }
    }

    func estimatedMinutes(ears: Int) -> Int {
        let tracks = Double(frequencies.count * ears) + (includesRetest ? Double(ears) : 0)
        let seconds = tracks * trialsPerFrequency * TestTiming.averageTrial * 1.1 + 5
        return max(1, Int((seconds / 60).rounded()))
    }
}

enum TestTiming {
    static let minGap = 1.2
    static let maxGap = 2.8
    /// Mode enfant : délai plus court (attention courte).
    static let kidGap = 1.0...2.0
    static let responseTail = 1.0
    /// Moitié entendue (on enchaîne dès l'appui), moitié ratée (fenêtre complète).
    static var averageTrial: Double { (minGap + maxGap) / 2 + 0.5 * 0.8 + 0.5 * (0.9 + responseTail) }
}

/// Seuil mesuré à une fréquence, pour une oreille. Niveau en dB relatifs à l'app.
struct Threshold: Codable, Hashable {
    var ear: Ear
    var frequency: Int
    var level: Int
    var noResponse: Bool
}

struct HeadphoneProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Volume système imposé pendant le test (0...1).
    var volume: Float
}

struct TestSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var headphoneID: UUID
    var earMode: EarMode
    var thresholds: [Threshold] = []
    var catchTrials: Int = 0
    var catchFalseAlarms: Int = 0
    var spuriousPresses: Int = 0
    /// Bruit ambiant mesuré (dB relatifs), nil si micro indisponible.
    var ambientLevel: Double? = nil
    var noisy: Bool = false
    /// Écart max entre le 1 kHz initial et le 1 kHz refait en fin de test.
    var retestShift: Int? = nil
    var kidMode: Bool = false
    var length: TestLength? = nil
    /// Commentaire libre et court (ex. « otite en cours », « enfant pas concentré »).
    /// Optionnel : les anciens fichiers n'ont pas ce champ.
    var note: String? = nil

    /// Longueur maximale d'un commentaire.
    static let noteLimit = 80

    /// Commentaire nettoyé, nil s'il est vide.
    static func cleanNote(_ text: String) -> String? {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(noteLimit))
        return t.isEmpty ? nil : t
    }

    /// Les anciennes sessions sans format sont traitées comme des tests Moyens.
    var format: TestLength { length ?? .standard }

    func level(_ ear: Ear, _ frequency: Int) -> Int? {
        thresholds.first { $0.ear == ear && $0.frequency == frequency && !$0.noResponse }?.level
    }

    /// Part des essais pièges correctement ignorés.
    var reliability: Double? {
        guard catchTrials > 0 else { return nil }
        return Double(catchTrials - catchFalseAlarms) / Double(catchTrials)
    }
}

struct UserProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var birthYear: Int
    var sessions: [TestSession] = []
    var referenceSessionID: UUID? = nil

    var age: Int { Calendar.current.component(.year, from: Date()) - birthYear }
    var sortedSessions: [TestSession] { sessions.sorted { $0.date > $1.date } }
    var reference: TestSession? { sessions.first { $0.id == referenceSessionID } }
    var initials: String { String(name.prefix(2)).uppercased() }
}

/// Partie de chasse au moustique. Stockée à part des sessions : ne compte jamais dans l'audiogramme.
struct MosquitoRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var userID: UUID
    var headphoneID: UUID
    /// Fréquence la plus aiguë attrapée (Hz), nil si aucune manche réussie.
    var bestFrequency: Int?
    var rounds: Int
}

/// Meilleur score d'un joueur, pour le classement.
struct MosquitoRank: Identifiable {
    let user: UserProfile
    let best: Int
    /// Première fois que ce record a été atteint (départage les égalités).
    let date: Date
    var id: UUID { user.id }
}

/// Partie complète de « La juste note ». Stockée à part : ne compte jamais dans l'audiogramme.
struct PitchRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var userID: UUID
    var headphoneID: UUID
    var level: PitchLevel
    var timbre: TimbreChoice
    /// Étoiles gagnées sur 30.
    var stars: Int
    /// Écart moyen en cents (valeur absolue).
    var meanError: Double
    /// Écart moyen signé en cents (positif = trop aigu).
    var meanBias: Double

    /// Plus d'étoiles, puis écart moyen plus faible.
    func beats(_ other: PitchRecord) -> Bool {
        stars != other.stars ? stars > other.stars : meanError < other.meanError
    }
}

struct PitchRank: Identifiable {
    let user: UserProfile
    let record: PitchRecord
    var id: UUID { user.id }
}

struct AppData: Codable {
    var users: [UserProfile] = []
    var headphones: [HeadphoneProfile] = []
    /// Optionnel : les fichiers de la v1 n'ont pas ce champ.
    var mosquitoGames: [MosquitoRecord]? = nil
    /// Optionnel : ajouté avec « La juste note ».
    var pitchGames: [PitchRecord]? = nil
}
