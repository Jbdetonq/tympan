import Foundation

enum Analysis {
    /// Toutes les fréquences testées (Moyen et Complet). Le Rapide n'a ni 250 Hz ni 10 kHz.
    static let frequencies = TestLength.full.frequencies
    static let allFrequencies = frequencies
    /// Graduations de l'axe de l'audiogramme.
    static let axisFrequencies = frequencies

    static func frequencyLabel(_ f: Int) -> String {
        if f < 1000 { return "\(f)" }
        if f % 1000 == 0 { return "\(f / 1000)k" }
        return String(format: "%.1fk", Double(f) / 1000)
    }

    /// Sessions comparables : même profil casque, pièce calme. Triées de la plus ancienne à la plus récente.
    static func comparableSessions(_ user: UserProfile, headphoneID: UUID) -> [TestSession] {
        user.sessions
            .filter { $0.headphoneID == headphoneID && !$0.noisy }
            .sorted { $0.date < $1.date }
    }

    struct Degradation: Identifiable {
        let ear: Ear
        let items: [(frequency: Int, delta: Int)]
        /// Vrai : perte confirmée (Moyen ou Complet). Faux : écart à vérifier par un test plus poussé.
        let confirmed: Bool
        var id: String { ear.rawValue }
    }

    /// Compare une session à la référence, sur les fréquences mesurées dans les deux.
    /// - Confirmée : test Moyen ou Complet, +10 dB sur 2 fréquences voisines.
    /// - À vérifier : +15 dB sur une fréquence, ou +10 dB sur 2 voisines vu par un test Rapide.
    static func degradations(latest: TestSession, reference: TestSession) -> [Degradation] {
        guard latest.id != reference.id,
              latest.headphoneID == reference.headphoneID,
              !latest.noisy else { return [] }
        var result: [Degradation] = []
        for ear in Ear.allCases {
            let common = allFrequencies.filter { latest.level(ear, $0) != nil && reference.level(ear, $0) != nil }
            guard !common.isEmpty else { continue }
            let deltas = common.map { (latest.level(ear, $0) ?? 0) - (reference.level(ear, $0) ?? 0) }
            var pairs = Set<Int>()
            if common.count >= 2 {
                for i in 0..<(common.count - 1) where deltas[i] >= 10 && deltas[i + 1] >= 10 {
                    pairs.insert(i)
                    pairs.insert(i + 1)
                }
            }
            let singles = Set(deltas.indices.filter { deltas[$0] >= 15 })
            let confirmed = latest.format.canConfirm && !pairs.isEmpty
            let flagged = confirmed ? pairs : pairs.union(singles)
            if !flagged.isEmpty {
                let items = flagged.sorted().map { (frequency: common[$0], delta: deltas[$0]) }
                result.append(Degradation(ear: ear, items: items, confirmed: confirmed))
            }
        }
        return result
    }
}
