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
        /// `noResponse` : rien entendu au niveau maximum (l'écart est alors un minimum).
        let items: [(frequency: Int, delta: Int, noResponse: Bool)]
        /// Vrai : perte confirmée (Moyen ou Complet). Faux : écart à vérifier par un test plus poussé.
        let confirmed: Bool
        var id: String { ear.rawValue }
    }

    /// Écart d'une fréquence entre deux sessions (positif = moins bien), « pas de réponse » compris.
    /// Rien entendu au maximum vaut au moins le niveau maximum : l'écart est un minimum.
    /// Une référence sans réponse ne permet pas de voir une baisse.
    static func delta(latest l: Threshold, reference r: Threshold) -> Int {
        switch (l.noResponse, r.noResponse) {
        case (false, false): return l.level - r.level
        case (true, true): return 0
        case (true, false): return max(0, l.level - r.level)
        case (false, true): return min(0, l.level - r.level)
        }
    }

    /// Compare une session à la référence, sur les fréquences testées dans les deux.
    /// Une fréquence passée à « rien entendu » compte comme une baisse.
    /// - Confirmée : test Moyen ou Complet, +10 dB sur 2 fréquences voisines.
    /// - À vérifier : +15 dB ou plus rien entendu sur une fréquence, ou +10 dB sur 2 voisines vu par un test Rapide.
    static func degradations(latest: TestSession, reference: TestSession) -> [Degradation] {
        guard latest.id != reference.id,
              latest.headphoneID == reference.headphoneID,
              !latest.noisy else { return [] }
        var result: [Degradation] = []
        for ear in Ear.allCases {
            let rows: [(frequency: Int, latest: Threshold, reference: Threshold)] = allFrequencies.compactMap { f in
                guard let l = latest.threshold(ear, f), let r = reference.threshold(ear, f) else { return nil }
                return (f, l, r)
            }
            guard !rows.isEmpty else { continue }
            let common = rows.map(\.frequency)
            let deltas = rows.map { delta(latest: $0.latest, reference: $0.reference) }
            var pairs = Set<Int>()
            if common.count >= 2 {
                for i in 0..<(common.count - 1) where deltas[i] >= 10 && deltas[i + 1] >= 10 {
                    pairs.insert(i)
                    pairs.insert(i + 1)
                }
            }
            // Une fréquence entendue dans la référence et plus du tout aujourd'hui est toujours signalée.
            let singles = Set(deltas.indices.filter {
                deltas[$0] >= 15 || (rows[$0].latest.noResponse && !rows[$0].reference.noResponse)
            })
            let confirmed = latest.format.canConfirm && !pairs.isEmpty
            let flagged = confirmed ? pairs : pairs.union(singles)
            if !flagged.isEmpty {
                let items = flagged.sorted().map {
                    (frequency: common[$0], delta: deltas[$0], noResponse: rows[$0].latest.noResponse)
                }
                result.append(Degradation(ear: ear, items: items, confirmed: confirmed))
            }
        }
        return result
    }

    // MARK: Résumé en phrases simples

    struct SummaryLine: Identifiable {
        enum Tone { case ok, info, warn }
        let tone: Tone
        let text: String
        var id: String { text }
    }

    /// « 500 Hz », « 4 kHz ».
    static func frequencyName(_ f: Int) -> String {
        if f < 1000 { return "\(f) Hz" }
        if f % 1000 == 0 { return "\(f / 1000) kHz" }
        return "\(f / 1000),\(f % 1000 / 100) kHz"
    }

    /// Lecture d'un audiogramme pour un non-spécialiste : les deux oreilles entre elles,
    /// la comparaison avec la référence, la fiabilité. Jamais de « normal » ou « anormal » :
    /// les dB de l'app ne sont pas des dB HL.
    static func summary(session s: TestSession, reference: TestSession?) -> [SummaryLine] {
        var lines: [SummaryLine] = []

        // Les deux oreilles, fréquence par fréquence (même casque, donc comparables).
        if s.earMode == .both {
            let common = allFrequencies.filter { s.level(.right, $0) != nil && s.level(.left, $0) != nil }
            // Écart positif : l'oreille gauche entend moins bien.
            let diffs = common.map { (s.level(.left, $0) ?? 0) - (s.level(.right, $0) ?? 0) }
            if let i = diffs.indices.max(by: { abs(diffs[$0]) < abs(diffs[$1]) }), abs(diffs[i]) >= 15 {
                let name = frequencyName(common[i])
                let gap = abs(diffs[i])
                let text = diffs[i] > 0
                    ? String(localized: "L'oreille gauche entend moins bien que la droite vers \(name) (\(gap) dB d'écart). Refais un test pour voir si ça se confirme.")
                    : String(localized: "L'oreille droite entend moins bien que la gauche vers \(name) (\(gap) dB d'écart). Refais un test pour voir si ça se confirme.")
                lines.append(SummaryLine(tone: .info, text: text))
            } else if !common.isEmpty {
                lines.append(SummaryLine(tone: .ok, text: String(localized: "Tes deux oreilles entendent à peu près pareil.")))
            }
        }

        // Fréquences sans réponse jusqu'au niveau maximum.
        for ear in s.earMode.ears {
            let silent = s.thresholds.filter { $0.ear == ear && $0.noResponse }.map(\.frequency).sorted()
            guard !silent.isEmpty else { continue }
            let names = silent.map { frequencyName($0) }.joined(separator: ", ")
            let text = ear == .right
                ? String(localized: "Oreille droite : rien entendu à \(names), même au niveau maximum. À refaire, et à montrer à un ORL si ça se confirme.")
                : String(localized: "Oreille gauche : rien entendu à \(names), même au niveau maximum. À refaire, et à montrer à un ORL si ça se confirme.")
            lines.append(SummaryLine(tone: .warn, text: text))
        }

        // Comparaison avec la référence.
        if let r = reference {
            if r.id == s.id {
                lines.append(SummaryLine(tone: .info, text: String(localized: "Ce test est ta référence : les suivants seront comparés à lui (en pointillés).")))
            } else if r.headphoneID != s.headphoneID {
                lines.append(SummaryLine(tone: .info, text: String(localized: "Ta référence a été faite avec un autre casque : pas de comparaison possible.")))
            } else if !s.noisy {
                if !degradations(latest: s, reference: r).isEmpty {
                    lines.append(SummaryLine(tone: .warn, text: String(localized: "Moins bien que ta référence à certaines fréquences : voir le bandeau en haut de la fiche.")))
                } else {
                    var deltas: [Int] = []
                    for ear in Ear.allCases {
                        for f in allFrequencies {
                            if let a = s.level(ear, f), let b = r.level(ear, f) { deltas.append(a - b) }
                        }
                    }
                    let date = Format.long.string(from: r.date)
                    if !deltas.isEmpty, Double(deltas.reduce(0, +)) / Double(deltas.count) <= -5 {
                        lines.append(SummaryLine(tone: .ok, text: String(localized: "Un peu mieux que ta référence du \(date) (souvent l'habitude du test).")))
                    } else if !deltas.isEmpty {
                        lines.append(SummaryLine(tone: .ok, text: String(localized: "Stable par rapport à ta référence du \(date).")))
                    }
                }
            }
        }

        // Fiabilité.
        if (s.reliability.map { $0 < 0.8 } ?? false) || s.spuriousPresses > 3 {
            lines.append(SummaryLine(tone: .info, text: String(localized: "Plusieurs appuis sans bip : résultat à prendre avec prudence.")))
        } else if let shift = s.retestShift, shift >= 10 {
            lines.append(SummaryLine(tone: .info, text: String(localized: "Le 1 kHz refait en fin de test a bougé de \(shift) dB : attention un peu dispersée, résultat à confirmer.")))
        }
        return lines
    }
}
