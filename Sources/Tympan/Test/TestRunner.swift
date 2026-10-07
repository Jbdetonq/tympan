import CoreAudio
import Foundation
import Observation

struct TestConfig {
    var userID: UUID
    var earMode: EarMode
    var headphone: HeadphoneProfile
    var length: TestLength = .standard
    var kidMode = false
}

/// Déroulé complet d'un test : casque, bruit ambiant, mesure, vérification.
@MainActor
@Observable
final class TestRunner {
    enum Phase: Int, Comparable {
        case headphones, ambient, measuring, verifying, finished
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    /// Au-delà, la session est marquée "environnement bruyant".
    static let noisyThreshold: Double = 45
    static let catchProbability = 0.1

    let config: TestConfig
    private(set) var phase: Phase = .headphones
    private(set) var ambientLevel: Double?
    private(set) var noisy = false
    private(set) var micUnavailable = false
    private(set) var catchTotal = 0
    private(set) var catchFalseAlarms = 0
    private(set) var spuriousPresses = 0
    private(set) var startDate = Date()
    private(set) var isPaused = false
    private(set) var result: TestSession?
    private(set) var errorMessage: String?
    private(set) var deviceName = ""
    private(set) var tracks: [ThresholdTrack]
    private(set) var retests: [ThresholdTrack]
    /// Incrémenté à chaque bonne détection (utile au mode enfant).
    private(set) var hits = 0
    /// Fréquence du dernier bip entendu (mode enfant : quel animal montrer).
    private(set) var lastHitFrequency: Int?
    /// Incrémenté à chaque appui accepté (retour visuel du bouton).
    private(set) var pressCount = 0
    /// Mode enfant : mesures dont l'animal peut être montré (trouvé sur un bip entendu, ou endormi).
    private(set) var revealedKeys: Set<String> = []

    /// Mode enfant : bip de révélation joué après un seuil validé sur un bip raté,
    /// pour que l'animal apparaisse sur un appui et pas dans le silence. Ne change pas le seuil.
    private struct Reveal {
        let ear: Ear
        let frequency: Int
        var level: Int
        var attempts = 0
    }
    private var pendingReveals: [Reveal] = []
    private var revealTrialsDone = 0
    static let revealMargin = 5
    static let maxRevealAttempts = 2

    private let tone = ToneGenerator()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var windowOpen = false
    @ObservationIgnored private var respondedInWindow = false
    /// Verrou du volume ; son `hold` dit si le test attend (Échap, muet, autre son).
    private(set) var volumeLock: VolumeLock?
    @ObservationIgnored private var device: AudioDeviceID?
    /// La sortie audio a changé pendant le test (casque débranché...) : test en pause.
    private(set) var outputChanged = false

    init(config: TestConfig) {
        self.config = config
        tracks = config.earMode.ears.flatMap { ear in
            config.length.frequencies.map { ThresholdTrack(ear: ear, frequency: $0, length: config.length) }
        }
        retests = config.length.includesRetest ? config.earMode.ears.map { ThresholdTrack(ear: $0, frequency: 1000, length: config.length) } : []
    }

    // MARK: Affichage

    private var remainingTrials: Int {
        tracks.reduce(0) { $0 + $1.estimatedRemainingTrials } + retests.reduce(0) { $0 + $1.estimatedRemainingTrials }
            + pendingReveals.count
    }

    private var doneTrials: Int {
        tracks.reduce(0) { $0 + $1.trials } + retests.reduce(0) { $0 + $1.trials } + revealTrialsDone
    }

    nonisolated static func key(ear: Ear, frequency: Int) -> String { "\(ear.rawValue)-\(frequency)" }

    /// Mode enfant : l'animal de cette mesure peut être montré.
    func isRevealed(_ track: ThresholdTrack) -> Bool {
        revealedKeys.contains(Self.key(ear: track.ear, frequency: track.frequency))
    }

    /// Fréquences terminées / total (vérification comprise).
    var doneCount: Int { tracks.filter(\.isDone).count + retests.filter(\.isDone).count }
    var totalCount: Int { tracks.count + retests.count }

    /// Avancement de la mesure (0...1), vérification comprise.
    var measureProgress: Double {
        let total = doneTrials + remainingTrials
        return total == 0 ? 0 : Double(doneTrials) / Double(total)
    }

    var headphonesOnSpeaker: Bool {
        guard let device else { return false }
        return SystemAudio.isBuiltInSpeaker(device)
    }

    // MARK: Commandes

    func start() {
        guard task == nil else { return }
        startDate = Date()
        task = Task { await self.run() }
    }

    func respond() {
        guard phase == .measuring || phase == .verifying, !isPaused else { return }
        pressCount += 1
        if windowOpen {
            respondedInWindow = true
        } else {
            spuriousPresses += 1
        }
    }

    func togglePause() {
        if isPaused, outputChanged {
            // Reprise après changement de sortie : on reverrouille sur la nouvelle sortie.
            outputChanged = false
            lockVolume()
        }
        isPaused.toggle()
    }

    func cancel() {
        task?.cancel()
        tone.stopEngine()
        restoreVolume()
    }

    // MARK: Déroulé

    private func run() async {
        phase = .headphones
        lockVolume()
        audioLog.info("Test : sortie \(self.deviceName, privacy: .public), volume \(self.config.headphone.volume)")
        await pause(0.5)
        await waitForSafeAudio()

        phase = .ambient
        audioLog.info("Mesure du bruit ambiant")
        if let level = await AmbientNoiseMeter.measure(seconds: 3) {
            ambientLevel = level
            noisy = level > Self.noisyThreshold
        } else {
            micUnavailable = true
        }
        guard !Task.isCancelled else { return }

        do {
            try tone.startEngine()
        } catch {
            errorMessage = String(localized: "Impossible de démarrer l'audio : \(error.localizedDescription)")
            restoreVolume()
            return
        }

        audioLog.info("Mesure des seuils")
        phase = .measuring
        while !Task.isCancelled {
            if let r = pendingReveals.first {
                await trial(frequency: r.frequency, level: r.level, ear: r.ear) { heard in
                    self.recordReveal(heard: heard)
                }
                continue
            }
            guard let i = randomOpenIndex(tracks) else { break }
            if tracks[i].trials == 0 {
                tracks[i].prime(startLevel: probableStart(for: tracks[i]))
            }
            let t = tracks[i]
            await trial(frequency: t.frequency, level: t.level, ear: t.ear) { heard in
                self.tracks[i].record(heard: heard)
                self.afterRecord(self.tracks[i], heard: heard)
            }
        }

        phase = .verifying
        while !Task.isCancelled, let i = randomOpenIndex(retests) {
            if retests[i].trials == 0 {
                retests[i].prime(startLevel: probableStart(for: retests[i]))
            }
            let t = retests[i]
            await trial(frequency: t.frequency, level: t.level, ear: t.ear) { heard in
                self.retests[i].record(heard: heard)
            }
        }
        guard !Task.isCancelled else { return }

        tone.stopEngine()
        restoreVolume()
        result = buildSession()
        phase = .finished
    }

    /// Mode enfant : décide quand l'animal d'une mesure terminée peut apparaître.
    private func afterRecord(_ track: ThresholdTrack, heard: Bool) {
        guard config.kidMode, track.isDone else { return }
        let key = Self.key(ear: track.ear, frequency: track.frequency)
        if track.noResponse || heard {
            revealedKeys.insert(key)
        } else {
            // Seuil validé sur un bip raté : un bip de plus, un peu au-dessus du seuil.
            let level = min(track.threshold + Self.revealMargin, track.maxLevel)
            pendingReveals.append(Reveal(ear: track.ear, frequency: track.frequency, level: level))
        }
    }

    private func recordReveal(heard: Bool) {
        guard var r = pendingReveals.first else { return }
        revealTrialsDone += 1
        r.attempts += 1
        if heard || r.attempts >= Self.maxRevealAttempts {
            pendingReveals.removeFirst()
            revealedKeys.insert(Self.key(ear: r.ear, frequency: r.frequency))
        } else {
            r.level = min(r.level + Self.revealMargin, config.length.maxLevel)
            pendingReveals[0] = r
        }
    }

    /// Seuil de la fréquence déjà mesurée la plus proche (même oreille) + 15 dB, sinon 35 dB.
    /// Mode enfant : + 10 dB, sinon 30 dB (moins de bips par seuil).
    private func probableStart(for track: ThresholdTrack) -> Int {
        let margin = config.kidMode ? 10 : 15
        let fallback = config.kidMode ? 30 : 35
        let known = tracks.filter { $0.ear == track.ear && $0.result != nil }
        guard let nearest = known.min(by: {
            abs(log2(Double($0.frequency) / Double(track.frequency))) < abs(log2(Double($1.frequency) / Double(track.frequency)))
        }), let r = nearest.result else { return fallback }
        return r + margin
    }

    private func randomOpenIndex(_ list: [ThresholdTrack]) -> Int? {
        list.indices.filter { !list[$0].isDone }.randomElement()
    }

    /// Un essai : délai aléatoire, puis bip (ou silence piège), puis fenêtre de réponse.
    private func trial(frequency: Int, level: Int, ear: Ear, record: (Bool) -> Void) async {
        await waitWhilePaused()
        let gap = config.kidMode ? TestTiming.kidGap : TestTiming.minGap...TestTiming.maxGap
        await pause(Double.random(in: gap))
        await waitWhilePaused()
        guard !Task.isCancelled else { return }

        checkOutputDevice()
        await waitWhilePaused()
        await waitForSafeAudio()
        guard !Task.isCancelled else { return }
        let holdsBefore = volumeLock?.holdCount ?? 0
        let isCatch = Double.random(in: 0..<1) < Self.catchProbability
        respondedInWindow = false
        windowOpen = true
        if !isCatch {
            tone.play(frequency: Double(frequency), level: level, ear: ear)
        }
        // Fenêtre de réponse : on passe à la suite dès l'appui.
        let deadline = Date().addingTimeInterval(ToneGenerator.pulsedDuration + TestTiming.responseTail)
        while Date() < deadline && !respondedInWindow && !Task.isCancelled {
            await pause(0.03)
        }
        if respondedInWindow { await pause(0.25) }
        windowOpen = false
        guard !Task.isCancelled else { return }
        // Essai interrompu (Échap, muet, autre son, pause) : il ne compte pas, il sera rejoué.
        if (volumeLock?.holdCount ?? 0) != holdsBefore || isPaused {
            tone.silence()
            return
        }

        if isCatch {
            catchTotal += 1
            if respondedInWindow { catchFalseAlarms += 1 }
        } else {
            if respondedInWindow {
                lastHitFrequency = frequency
                hits += 1
            }
            record(respondedInWindow)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Attend que le son soit sûr : pas d'arrêt d'urgence, pas de muet, pas d'autre son sur le Mac.
    private func waitForSafeAudio() async {
        while volumeLock?.hold != nil && !Task.isCancelled {
            await pause(0.2)
        }
    }

    private func waitWhilePaused() async {
        while isPaused && !Task.isCancelled {
            await pause(0.2)
        }
    }

    private func lockVolume() {
        volumeLock?.release()
        volumeLock = nil
        guard let d = SystemAudio.defaultOutputDevice() else { return }
        device = d
        deviceName = SystemAudio.name(of: d)
        let lock = VolumeLock(device: d, target: config.headphone.volume)
        let tone = self.tone
        lock.onEmergency = { tone.silence() }
        lock.engage()
        volumeLock = lock
    }

    /// Casque débranché ou sortie changée : on met en pause plutôt que de fausser le test.
    private func checkOutputDevice() {
        guard let current = SystemAudio.defaultOutputDevice(), current != device else { return }
        audioLog.info("Sortie audio changée pendant le test")
        outputChanged = true
        isPaused = true
    }

    private func restoreVolume() {
        volumeLock?.release()
        volumeLock = nil
    }

    private func buildSession() -> TestSession {
        var s = TestSession(headphoneID: config.headphone.id, earMode: config.earMode)
        s.thresholds = tracks.map {
            Threshold(ear: $0.ear, frequency: $0.frequency, level: $0.threshold, noResponse: $0.noResponse)
        }
        s.catchTrials = catchTotal
        s.catchFalseAlarms = catchFalseAlarms
        s.spuriousPresses = spuriousPresses
        s.ambientLevel = ambientLevel
        s.noisy = noisy
        s.kidMode = config.kidMode
        s.length = config.length
        let shifts: [Int] = retests.compactMap { r in
            guard let first = tracks.first(where: { $0.ear == r.ear && $0.frequency == 1000 }) else { return nil }
            return abs(r.threshold - first.threshold)
        }
        s.retestShift = shifts.max()
        return s
    }
}
