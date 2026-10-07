import CoreAudio
import Foundation
import Observation

struct MosquitoConfig {
    var userID: UUID
    var headphone: HeadphoneProfile
}

/// Chasse au moustique : choix forcé entre 3 bocaux, un seul contient le son aigu.
/// Bonne réponse : le moustique monte en fréquence. Mauvaise : une vie perdue, même fréquence.
@MainActor
@Observable
final class MosquitoGame {
    enum Phase { case starting, listening, choosing, feedback, over }

    static let startFrequency = 8000
    static let maxFrequency = 20000
    /// Niveau fixe et modéré (dB app) : protège les oreilles et évite toute distorsion
    /// audible qui trahirait le bon bocal.
    static let level = 60
    static let toneDuration = 1.0
    static let gap = 0.4
    static let lifeCount = 3

    /// +500 Hz jusqu'à 14 kHz, puis +250 Hz, plafond 20 kHz.
    static func next(after f: Int) -> Int {
        min(maxFrequency, f + (f < 14000 ? 500 : 250))
    }

    let config: MosquitoConfig
    let recordID = UUID()
    private(set) var phase: Phase = .starting
    private(set) var round = 1
    private(set) var frequency = MosquitoGame.startFrequency
    private(set) var lives = MosquitoGame.lifeCount
    /// Fréquence la plus aiguë attrapée pendant la partie.
    private(set) var best: Int?
    private(set) var playingJar: Int?
    private(set) var heard: Set<Int> = []
    private(set) var choice: Int?
    private(set) var lastCorrect = false
    private(set) var won = false
    /// Le joueur a arrêté la partie avec « Je n'entends plus rien ».
    private(set) var gaveUp = false
    private(set) var outputChanged = false
    private(set) var errorMessage: String?
    /// Bocal du moustique : n'est montré qu'après le choix.
    private(set) var mosquitoJar = 0

    private let tone = ToneGenerator()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var replayRequested = false
    /// Verrou du volume ; son `hold` dit si le jeu attend (Échap, muet, autre son).
    private(set) var volumeLock: VolumeLock?
    @ObservationIgnored private var device: AudioDeviceID?

    init(config: MosquitoConfig) {
        self.config = config
    }

    var record: MosquitoRecord {
        MosquitoRecord(id: recordID, userID: config.userID, headphoneID: config.headphone.id,
                       bestFrequency: best, rounds: round)
    }

    // MARK: Commandes

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

    func cancel() {
        task?.cancel()
        tone.stopEngine()
        restoreVolume()
    }

    // MARK: Déroulé

    private func run() async {
        lockVolume()
        do {
            try tone.startEngine()
        } catch {
            errorMessage = "Impossible de démarrer l'audio : \(error.localizedDescription)"
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
        for i in 0..<3 {
            await waitForOutput()
            guard !Task.isCancelled, choice == nil, !gaveUp else { break }
            playingJar = i
            if i == mosquitoJar {
                tone.play(frequency: Double(frequency), level: Self.level, ear: nil,
                          duration: Self.toneDuration, pulsed: false)
            }
            await pauseUntilChoice(Self.toneDuration)
            playingJar = nil
            heard.insert(i)
            await pauseUntilChoice(Self.gap)
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
