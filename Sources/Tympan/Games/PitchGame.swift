import CoreAudio
import Foundation
import Observation

/// Niveaux de « La juste note ».
enum PitchLevel: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }

    /// Durée d'écoute du modèle (s).
    var listenDuration: Double {
        switch self {
        case .easy: return 3
        case .medium: return 2
        case .hard: return 1
        }
    }

    /// Silence imposé entre l'écoute et la recherche (s).
    var silence: Double { self == .hard ? 3 : 0 }

    /// Nom de la note et Hz affichés sous le curseur.
    var showsNote: Bool { self == .easy }

    /// Étendue du curseur (demi-tons).
    var span: Double {
        switch self {
        case .easy: return 12
        case .medium: return 18
        case .hard: return 24
        }
    }

    /// Réécoutes du modèle permises par manche.
    var modelReplays: Int { self == .easy ? 1 : 0 }

    /// Son imposé par le niveau : voix (la plus facile à chanter dans sa tête),
    /// flûte, puis piano (attaque brève, timbre qui s'éteint).
    var timbre: TimbreChoice {
        switch self {
        case .easy: return .voice
        case .medium: return .flute
        case .hard: return .piano
        }
    }
}

/// Son d'une partie. « Au hasard » (un timbre par manche) reste possible mais n'est plus proposé :
/// le son est imposé par le niveau.
enum TimbreChoice: String, Codable, CaseIterable, Identifiable {
    case flute, piano, voice, random
    var id: String { rawValue }

    /// Timbre de la manche.
    func pick() -> Timbre {
        switch self {
        case .flute: return .flute
        case .piano: return .piano
        case .voice: return .voice
        case .random: return Timbre.allCases.randomElement() ?? .flute
        }
    }
}

/// Hauteurs en numéros MIDI décimaux (69 = La 440 Hz). Un demi-ton = 1, un cent = 0,01 :
/// l'échelle suit l'oreille (logarithmique), pas les Hz.
enum PitchMath {
    /// Fréquence (Hz) d'une hauteur MIDI.
    static func frequency(_ midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    /// Noms des 12 demi-tons, à partir de Do (C).
    static let frenchNames = ["Do", "Do♯", "Ré", "Ré♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
    static let englishNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static var names: [String] { AppLocale.isFrench ? frenchNames : englishNames }

    /// Note la plus proche, notation scientifique : « La 4 » en français, « A4 » en anglais (440 Hz).
    static func noteName(_ midi: Double, spaced: Bool = true) -> String {
        let n = Int(midi.rounded())
        let name = names[((n % 12) + 12) % 12]
        let octave = Int((Double(n) / 12).rounded(.down)) - 1
        return spaced && AppLocale.isFrench ? "\(name) \(octave)" : "\(name)\(octave)"
    }

    /// Touche noire du clavier (dièses).
    static func black(_ n: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((n % 12) + 12) % 12)
    }

    /// 3 étoiles sous 10 cents, 2 sous 25, 1 sous 50 (un quart de ton).
    static func stars(cents: Double) -> Int {
        let e = abs(cents)
        if e < 10 { return 3 }
        if e < 25 { return 2 }
        if e < 50 { return 1 }
        return 0
    }
}

/// Une manche jouée : note à retrouver et réponse, en hauteurs MIDI.
struct PitchRound: Identifiable, Hashable {
    var id = UUID()
    let target: Double
    let answer: Double
    let timbre: Timbre
    /// Écart en cents, positif = trop aigu.
    var cents: Double { (answer - target) * 100 }
    var stars: Int { PitchMath.stars(cents: cents) }
}

/// Joueur, casque et niveau choisis sur la page d'accueil du jeu.
struct PitchConfig {
    var userID: UUID
    var headphone: HeadphoneProfile
    var level: PitchLevel
    var timbre: TimbreChoice
}

/// La juste note : écouter une note, puis la retrouver au curseur. 10 manches.
@MainActor
@Observable
final class PitchGame {
    /// Départ, écoute du modèle, silence (Difficile), recherche au curseur, résultat de la manche, fin.
    enum Phase { case starting, listening, silence, searching, feedback, over }

    static let roundCount = 10
    /// Niveau fixe et modéré (dB app), comme la chasse au moustique.
    static let level = 60
    /// Notes tirées entre Do 3 et Do 6 (131 à 1 047 Hz) : zone où la précision
    /// de l'oreille en cents varie peu.
    static let lowNote = 48.0
    static let highNote = 84.0
    /// Départ du curseur à au moins 3 demi-tons de la note (pas de réussite par chance).
    static let minStartDistance = 3.0

    let config: PitchConfig
    /// Identifiant de la partie : l'enregistrer deux fois ne la duplique pas.
    let recordID = UUID()
    private(set) var phase: Phase = .starting
    /// Manches jouées.
    private(set) var results: [PitchRound] = []
    /// Timbre de la manche en cours.
    private(set) var timbre: Timbre = .flute
    /// Étendue du curseur (hauteurs MIDI), placée au hasard autour de la note.
    private(set) var window: ClosedRange<Double> = 60...72
    /// Note à retrouver et position du curseur (hauteurs MIDI).
    private(set) var target: Double = 66
    private(set) var cursor: Double = 62
    /// Réécoutes du modèle restantes pour cette manche.
    private(set) var replaysLeft = 0
    /// La note du curseur sonne.
    private(set) var sounding = false
    /// Pendant « Comparer les deux » : 0 = la note, 1 = ton choix.
    private(set) var comparePart: Int?
    /// La sortie audio a changé : le jeu attend Reprendre.
    private(set) var outputChanged = false
    private(set) var errorMessage: String?

    private let synth = NoteSynth()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Extinction différée de la note du curseur.
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    /// Verrou du volume ; son `hold` dit si le jeu attend (Échap, muet, autre son).
    private(set) var volumeLock: VolumeLock?
    /// Sortie audio au début de la partie, pour repérer un changement.
    @ObservationIgnored private var device: AudioDeviceID?

    init(config: PitchConfig) {
        self.config = config
    }

    /// Numéro de la manche affichée (1 à 10).
    var roundNumber: Int {
        let n = (phase == .feedback || phase == .over) ? results.count : results.count + 1
        return min(max(n, 1), Self.roundCount)
    }

    var isComplete: Bool { results.count >= Self.roundCount }
    /// Étoiles gagnées, sur 30.
    var totalStars: Int { results.reduce(0) { $0 + $1.stars } }

    /// Écart moyen en cents (valeur absolue).
    var meanError: Double? {
        guard !results.isEmpty else { return nil }
        return results.map { abs($0.cents) }.reduce(0, +) / Double(results.count)
    }

    /// Tendance : moyenne signée (positif = on vise trop aigu).
    var meanBias: Double? {
        guard !results.isEmpty else { return nil }
        return results.map(\.cents).reduce(0, +) / Double(results.count)
    }

    /// Seules les parties complètes sont enregistrées (classement équitable).
    var record: PitchRecord? {
        guard isComplete, let e = meanError, let b = meanBias else { return nil }
        return PitchRecord(id: recordID, userID: config.userID, headphoneID: config.headphone.id,
                           level: config.level, timbre: config.timbre,
                           stars: totalStars, meanError: e, meanBias: b)
    }

    // MARK: Commandes

    /// Lance la partie (une seule fois).
    func start() {
        guard task == nil else { return }
        task = Task { await self.run() }
    }

    /// Déplace le curseur ; la note suit en direct.
    func setCursor(_ value: Double) {
        guard phase == .searching else { return }
        cursor = min(max(value, window.lowerBound), window.upperBound)
        releaseTask?.cancel()
        synth.hold(frequency: PitchMath.frequency(cursor), timbre: timbre, level: Self.level)
        sounding = true
    }

    /// Curseur relâché : la note s'éteint 0,7 s plus tard.
    func endDrag() {
        releaseLater(0.7)
    }

    /// Flèches : 5 cents, ou un demi-ton avec Maj.
    func nudge(cents: Double) {
        guard phase == .searching else { return }
        setCursor(cursor + cents / 100)
        releaseLater(1.0)
    }

    /// Espace : rejoue la note du curseur.
    func playMine() {
        guard phase == .searching else { return }
        setCursor(cursor)
        releaseLater(1.5)
    }

    /// R : réécouter la note à retrouver (Facile seulement, une fois par manche).
    func replayModel() {
        guard phase == .searching, replaysLeft > 0 else { return }
        replaysLeft -= 1
        stopSound()
        task = Task {
            await self.listenModel()
            guard !Task.isCancelled else { return }
            await self.pause(0.3)
            guard !Task.isCancelled else { return }
            self.phase = .searching
        }
    }

    /// Entrée : la position du curseur est la réponse de la manche.
    func validate() {
        guard phase == .searching else { return }
        stopSound()
        results.append(PitchRound(target: target, answer: cursor, timbre: timbre))
        phase = .feedback
    }

    /// Rejoue la note puis ton choix.
    func compare() {
        guard phase == .feedback, comparePart == nil, let r = results.last else { return }
        task = Task {
            self.comparePart = 0
            self.synth.play(frequency: PitchMath.frequency(r.target), timbre: r.timbre, level: Self.level, duration: 1.2)
            await self.pause(1.5)
            guard !Task.isCancelled else { return }
            self.comparePart = 1
            self.synth.play(frequency: PitchMath.frequency(r.answer), timbre: r.timbre, level: Self.level, duration: 1.2)
            await self.pause(1.4)
            self.comparePart = nil
        }
    }

    /// Manche suivante, ou fin après la 10e.
    func next() {
        guard phase == .feedback else { return }
        task?.cancel()
        comparePart = nil
        synth.release()
        if isComplete {
            finish()
        } else {
            task = Task { await self.playRound() }
        }
    }

    /// Reprise après changement de sortie : on reverrouille le volume sur la nouvelle sortie.
    func resume() {
        guard outputChanged else { return }
        lockVolume()
        outputChanged = false
    }

    /// Partie quittée : rien n'est enregistré, volume d'origine rendu.
    func cancel() {
        task?.cancel()
        releaseTask?.cancel()
        synth.stopEngine()
        restoreVolume()
    }

    // MARK: Déroulé

    /// Démarrage du son, puis première manche ; les suivantes sont lancées par `next`.
    private func run() async {
        lockVolume()
        do {
            try synth.startEngine()
        } catch {
            errorMessage = String(localized: "Impossible de démarrer l'audio : \(error.localizedDescription)")
            restoreVolume()
            phase = .over
            return
        }
        await pause(0.8)
        guard !Task.isCancelled else { return }
        await playRound()
    }

    /// Nouvelle manche : note tirée au hasard, curseur placé, écoute du modèle.
    private func playRound() async {
        timbre = config.timbre.pick()
        target = Double.random(in: Self.lowNote...Self.highNote)
        // Fenêtre du curseur placée au hasard autour de la note, au moins un demi-ton de marge :
        // la position à l'écran ne renseigne pas sur la hauteur.
        let span = config.level.span
        let low = target - 1 - Double.random(in: 0...(span - 2))
        window = low...(low + span)
        var c = Double.random(in: window)
        var tries = 0
        while abs(c - target) < Self.minStartDistance && tries < 200 {
            c = Double.random(in: window)
            tries += 1
        }
        cursor = c
        replaysLeft = config.level.modelReplays
        audioLog.debug("Juste note : manche \(self.results.count + 1), cible \(PitchMath.frequency(self.target)) Hz")

        await listenModel()
        guard !Task.isCancelled else { return }
        if config.level.silence > 0 {
            phase = .silence
            await pause(config.level.silence)
        } else {
            await pause(0.3)
        }
        guard !Task.isCancelled else { return }
        phase = .searching
    }

    /// Joue la note à retrouver (durée selon le niveau).
    private func listenModel() async {
        await waitForOutput()
        guard !Task.isCancelled else { return }
        phase = .listening
        let d = config.level.listenDuration
        synth.play(frequency: PitchMath.frequency(target), timbre: timbre, level: Self.level, duration: d)
        await pause(d + 0.25)
    }

    /// Fin de partie : arrêt du son, volume d'origine rendu.
    private func finish() {
        releaseTask?.cancel()
        synth.stopEngine()
        restoreVolume()
        phase = .over
    }

    private func stopSound() {
        releaseTask?.cancel()
        synth.release()
        sounding = false
    }

    /// Éteint la note du curseur après `seconds`, sauf si elle est rejouée entre-temps.
    private func releaseLater(_ seconds: Double) {
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.synth.release()
            self.sounding = false
        }
    }

    /// Sortie changée : le jeu attend Reprendre.
    private func waitForOutput() async {
        if let current = SystemAudio.defaultOutputDevice(), current != device {
            audioLog.info("Sortie audio changée pendant le jeu")
            outputChanged = true
        }
        // Attend aussi que le son soit sûr : pas d'arrêt d'urgence, pas de muet, pas d'autre son.
        while (outputChanged || volumeLock?.hold != nil) && !Task.isCancelled {
            await pause(0.2)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Verrouille le volume du profil sur la sortie par défaut ; Échap éteint aussi la note.
    private func lockVolume() {
        volumeLock?.release()
        volumeLock = nil
        guard let d = SystemAudio.defaultOutputDevice() else { return }
        device = d
        let lock = VolumeLock(device: d, target: config.headphone.volume)
        let synth = self.synth
        lock.onEmergency = { synth.release() }
        lock.engage()
        volumeLock = lock
    }

    private func restoreVolume() {
        volumeLock?.release()
        volumeLock = nil
    }
}
