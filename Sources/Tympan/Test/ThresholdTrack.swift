import Foundation

/// Recherche du seuil pour une oreille et une fréquence, par encadrement avec mémoire.
///
/// - Tant que rien n'est entendu : +10 dB.
/// - Dès qu'un niveau est entendu : on descend de 10 dB pour trouver un niveau raté.
/// - Entre un raté et un entendu : on coupe l'écart en deux (par pas de `fineStep`),
///   jamais en dessous d'un niveau déjà raté.
/// - Seuil = plus bas niveau entendu `confirmations` fois, avec un raté à `fineStep` dessous.
///
/// Rapide : pas 5, 1 fois (~3,7 bips). Moyen : pas 5, 2 fois (~5,4). Complet : pas 2, 3 fois (~9).
struct ThresholdTrack {
    static let minLevel = -10
    static let coarseStep = 10

    let ear: Ear
    let frequency: Int
    let fineStep: Int
    let confirmations: Int
    /// 90 dB, ou 70 dB en mode enfant.
    let maxLevel: Int

    private(set) var level: Int = 35
    private(set) var trials = 0
    private(set) var result: Int?
    private(set) var noResponse = false

    private var hits: [Int: Int] = [:]
    private var misses: [Int: Int] = [:]

    init(ear: Ear, frequency: Int, length: TestLength) {
        self.ear = ear
        self.frequency = frequency
        self.fineStep = length.fineStep
        self.confirmations = length.confirmations
        self.maxLevel = length.maxLevel
    }

    private var maxTrials: Int { 8 + 5 * confirmations }

    var isDone: Bool { result != nil || noResponse }

    /// Seuil retenu (niveau max + 5 si aucune réponse : 95, ou 75 en mode enfant).
    var threshold: Int { result ?? (noResponse ? maxLevel + 5 : lowestReliableHit ?? level) }

    /// Présentations encore probables (sert uniquement à la barre de progression).
    var estimatedRemainingTrials: Int { isDone ? 0 : max(1, 2 + 2 * confirmations - trials) }

    /// Démarre près du seuil probable (déduit des fréquences voisines déjà mesurées).
    mutating func prime(startLevel: Int) {
        guard trials == 0 else { return }
        level = min(max(startLevel, 0), min(70, maxLevel))
    }

    /// Plus bas niveau entendu plus souvent que raté.
    private var lowestReliableHit: Int? {
        hits.keys.filter { (hits[$0] ?? 0) > (misses[$0] ?? 0) }.min()
    }

    mutating func record(heard: Bool) {
        guard !isDone else { return }
        trials += 1
        if heard {
            hits[level, default: 0] += 1
        } else {
            misses[level, default: 0] += 1
        }

        guard let h = lowestReliableHit else {
            // Rien d'entendu de façon fiable : on monte (ou on redemande en cas d'égalité).
            if heard { return }
            if level >= maxLevel {
                noResponse = true
                return
            }
            level = min(level + Self.coarseStep, maxLevel)
            return
        }

        if trials >= maxTrials {
            result = h
            return
        }

        let confirmed = (hits[h] ?? 0) >= confirmations
        if h == Self.minLevel {
            if confirmed { result = h } else { level = h }
            return
        }

        // Plus haut niveau raté sous le seuil provisoire.
        let missedBelow = misses.keys.filter { $0 < h && (misses[$0] ?? 0) >= (hits[$0] ?? 0) }.max()
        guard let m = missedBelow else {
            level = max(h - Self.coarseStep, Self.minLevel)
            return
        }
        let gap = h - m
        if gap > fineStep {
            // Milieu de l'écart, arrondi au pas fin.
            let half = max(fineStep, (gap / 2) / fineStep * fineStep)
            level = h - half
        } else if confirmed {
            result = h
        } else {
            level = h
        }
    }
}
