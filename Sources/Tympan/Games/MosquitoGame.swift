import CoreAudio
import Foundation
import Observation

/// Joueur et casque choisis sur la page d'accueil du jeu.
struct MosquitoConfig {
    var userID: UUID
    var headphone: HeadphoneProfile
}

/// Chasse au moustique : choix forcé entre 3 bocaux, un seul contient le son aigu.
/// Bonne réponse : le moustique monte en fréquence. Mauvaise : une vie perdue, même fréquence.
@MainActor
@Observable
final class MosquitoGame {
    /// Départ, écoute des bocaux, attente du choix, réponse montrée, fin.
    enum Phase { case starting, listening, choosing, feedback, over }

    static let startFrequency = 8000
    static let maxFrequency = 20000
    /// Niveau fixe et modéré (dB app) : protège les oreilles et évite toute distorsion
    /// audible qui trahirait le bon bocal.
    static let level = 60
    /// Son continu d'une seconde par bocal, 0,4 s entre deux bocaux.
    static let toneDuration = 1.0
    static let gap = 0.4
    static let lifeCount = 3

    /// +500 Hz jusqu'à 14 kHz, puis +250 Hz, plafond 20 kHz.
    static func next(after f: Int) -> Int {
        min(maxFrequency, f + (f < 14000 ? 500 : 250))
    }

    let config: MosquitoConfig
    /// Identifiant de la partie : l'enregistrer deux fois ne la duplique pas.
    let recordID = UUID()
    private(set) var phase: Phase = .starting
    private(set) var round = 1
    private(set) var frequency = MosquitoGame.startFrequency
    private(set) var lives = MosquitoGame.lifeCount
    /// Fréquence la plus aiguë attrapée pendant la partie.
    private(set) var best: Int?
    /// Bocal allumé en ce moment (0 à 2), qu'il contienne le son ou non.
    private(set) var playingJar: Int?
    /// Bocaux déjà écoutés pendant cette manche.
    private(set) var heard: Set<Int> = []
    /// Bocal désigné par le joueur, et s'il était le bon.
    private(set) var choice: Int?
    private(set) var lastCorrect = false
    /// 20 kHz atteint et trouvé.
    private(set) var won = false
    /// Le joueur a arrêté la partie avec « Je n'entends plus rien ».
    private(set) var gaveUp = false
    /// La sortie audio a changé : le jeu attend Reprendre.
    private(set) var outputChanged = false
    private(set) var errorMessage: String?
    /// Bocal du moustique : n'est montré qu'après le choix.
    private(set) var mosquitoJar = 0

    private let tone = ToneGenerator()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Réécouter demandé (R) : les trois bocaux sont rejoués.
    @ObservationIgnored private var replayRequested = false
    /// Verrou du volume ; son `hold` dit si le jeu attend (Échap, muet, autre son).
    private(set) var volumeLock: VolumeLock?
    /// Sortie audio au début de la partie, pour repérer un changement.
    @ObservationIgnored private var device: AudioDeviceID?

    init(config: MosquitoConfig) {
        self.config = config
    }

    /// Partie à enregistrer.
    var record: MosquitoRecord {
        MosquitoRecord(id: recordID, userID: config.userID, headphoneID: config.headphone.id,
                       bestFrequency: best, rounds: round)
    }

    // MARK: Commandes

    /// Lance la partie (une seule fois).
    func start() {
        guard task == nil else { return }
        task = Task { await self.run() }
    }

    /// Choix possible dès l'écoute : inutile d'attendre les trois bocaux si on a entendu le moustique.
    func choose(_ jar: Int) {
        guard phase == .listening || phase == .choosing, choice == nil, (0..<3).contains(jar) else { return }
        choice = jar
    }

    /// « Je n'entends plus rien » : fin de partie, le meilleur moustique est gardé.
    func giveUp() {
        guard phase == .listening || phase == .choosing, choice == nil else { return }
        gaveUp = true
        tone.silence()
    }

    /// Réécouter les trois bocaux, sans limite, tant qu'aucun n'est choisi.
    func replay() {
        guard phase == .choosing, choice == nil else { return }
        replayRequested = true
    }

    /// Reprise après changement de sortie : on reverrouille le volume sur la nouvelle sortie.
    func resume() {
        guard outputChanged else { return }
        lockVolume()
        outputChanged = false
    }

    /// Partie quittée : arrêt du son et volume d'origine rendu.
    func cancel() {
        task?.cancel()
        tone.stopEngine()
        restoreVolume()
    }

    // MARK: Déroulé

    /// Manches jusqu'à la dernière vie perdue, 20 kHz, ou « Je n'entends plus rien ».
    private func run() async {
        lockVolume()
        do {
            try tone.startEngine()
        } catch {
            errorMessage = String(localized: "Impossible de démarrer l'audio : \(error.localizedDescription)")
            restoreVolume()
            phase = .over
            return
        }
        await pause(0.8)

        while !Task.isCancelled {
            mosquitoJar = Int.random(in: 0..<3)
            choice = nil
            replayRequested = false
            audioLog.debug("Moustique : manche \(self.round), \(self.frequency) Hz")
            await listen()
            guard !Task.isCancelled else { return }
            if gaveUp { break }
            if choice == nil { phase = .choosing }
            while choice == nil && !gaveUp && !Task.isCancelled {
                if replayRequested {
                    replayRequested = false
                    await listen()
                    if choice == nil && !gaveUp { phase = .choosing }
                }
                await pause(0.03)
            }
            guard !Task.isCancelled else { return }
            if gaveUp { break }
            guard let c = choice else { return }

            lastCorrect = c == mosquitoJar
            if lastCorrect {
                best = frequency
            } else {
                lives -= 1
            }
            phase = .feedback
            await pause(1.8)
            guard !Task.isCancelled else { return }

            if lives == 0 { break }
            if lastCorrect {
                if frequency >= Self.maxFrequency {
                    won = true
                    break
                }
                frequency = Self.next(after: frequency)
            }
            round += 1
        }
        guard !Task.isCancelled else { return }
        tone.stopEngine()
        restoreVolume()
        phase = .over
    }

    /// Les trois bocaux s'allument l'un après l'autre ; le son ne sort que dans un seul.
    private func listen() async {
        phase = .listening
        heard = []
        var i = 0
        while i < 3 {
            await waitForOutput()
            guard !Task.isCancelled, choice == nil, !gaveUp else { break }
            let holdsBefore = volumeLock?.holdCount ?? 0
            playingJar = i
            if i == mosquitoJar {
                tone.play(frequency: Double(frequency), level: Self.level, ear: nil,
                          duration: Self.toneDuration, pulsed: false)
            }
            await pauseUntilChoice(Self.toneDuration)
            playingJar = nil
            // Son coupé pendant ce bocal (Échap, muet, autre son, sortie changée) : il est rejoué.
            if (volumeLock?.holdCount ?? 0) != holdsBefore || volumeLock?.hold != nil || outputChanged {
                continue
            }
            heard.insert(i)
            await pauseUntilChoice(Self.gap)
            i += 1
        }
        playingJar = nil
    }

    /// Attente écourtée dès que le joueur a choisi un bocal.
    private func pauseUntilChoice(_ seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && choice == nil && !gaveUp && !Task.isCancelled {
            await pause(0.02)
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

    /// Verrouille le volume du profil sur la sortie par défaut ; Échap coupe aussi le générateur.
    private func lockVolume() {
        volumeLock?.release()
        volumeLock = nil
        guard let d = SystemAudio.defaultOutputDevice() else { return }
        device = d
        let lock = VolumeLock(device: d, target: config.headphone.volume)
        let tone = self.tone
        lock.onEmergency = { tone.silence() }
        lock.engage()
        volumeLock = lock
    }

    private func restoreVolume() {
        volumeLock?.release()
        volumeLock = nil
    }
}
