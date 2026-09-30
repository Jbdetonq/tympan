import AVFoundation
import os

/// Timbres musicaux de « La juste note », produits par synthèse additive.
enum Timbre: String, Codable, CaseIterable, Identifiable {
    case flute, piano, voice
    var id: String { rawValue }
}

/// Synthé monophonique : joue une note pour une durée donnée (le modèle), ou la tient
/// pendant que le joueur déplace le curseur (glissando continu, sans clic).
/// Niveau en dB relatifs à l'app, comme `ToneGenerator` (100 dB = 0 dBFS), en valeur efficace.
final class NoteSynth {
    static let harmonicLimit = 32

    struct Voice {
        var active = false
        var gate = false
        var timbre: Timbre = .flute
        var amplitude: Double = 0
        /// Hauteurs en log2(Hz) : glissement exponentiel de la hauteur courante vers la cible.
        var targetLog: Double = 8.78
        var currentLog: Double = 8.78
        var configuredLog: Double = -100
        var count = 0
        var phases = [Double](repeating: 0, count: NoteSynth.harmonicLimit)
        var weights = [Double](repeating: 0, count: NoteSynth.harmonicLimit)
        var ratios = [Double](repeating: 1, count: NoteSynth.harmonicLimit)
        var decays = [Double](repeating: 0, count: NoteSynth.harmonicLimit)
        /// Temps depuis l'attaque (s).
        var t: Double = 0
        var startLevel: Double = 0
        var releaseT: Double = 0
        var releaseFrom: Double = 1
        /// Relâchement automatique (s après l'attaque) ; infini quand la note est tenue.
        var autoRelease: Double = .infinity
        var env: Double = 0
    }

    private static let fluteWeights: [Double] = [1, 0.42, 0.16, 0.07, 0.03, 0.015]
    /// Plancher de la décroissance du piano : la note reste audible tant qu'on la tient.
    private static let pianoFloor = 0.2

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let state = OSAllocatedUnfairLock(initialState: Voice())
    private var sampleRate: Double = 48_000
    private var configObserver: NSObjectProtocol?

    func startEngine() throws {
        guard node == nil else {
            if !engine.isRunning { try engine.start() }
            return
        }
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "Tympan", code: 1)
        }
        let sr = sampleRate
        let dt = 1 / sr
        let glide = 1 - exp(-1 / (0.015 * sr))
        let limit = min(16_000, 0.45 * sr)
        let state = self.state

        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            state.withLock { s in
                for f in 0..<Int(frameCount) {
                    let sample = s.active ? NoteSynth.render(&s, dt: dt, glide: glide, limit: limit) : 0
                    for buffer in buffers {
                        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        data[f] = Float(sample)
                    }
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        node = source
        engine.prepare()
        try engine.start()
        audioLog.info("Synthé musical démarré (running: \(self.engine.isRunning))")

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            audioLog.info("Configuration audio modifiée, redémarrage du synthé")
            try? self.engine.start()
        }
    }

    func stopEngine() {
        state.withLock { $0.active = false }
        engine.stop()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: Commandes

    /// Joue une note pendant `duration` secondes (relâchement compris).
    func play(frequency: Double, timbre: Timbre, level: Int, duration: Double) {
        ensureRunning()
        let amp = Self.amplitude(level)
        let off = max(0.05, duration - Self.releaseTime(timbre))
        state.withLock { s in
            Self.trigger(&s, frequency: frequency, timbre: timbre, amplitude: amp, autoRelease: off)
        }
    }

    /// Tient la note : si elle sonne déjà, elle glisse vers la nouvelle hauteur.
    func hold(frequency: Double, timbre: Timbre, level: Int) {
        ensureRunning()
        let amp = Self.amplitude(level)
        state.withLock { s in
            if s.active && s.gate && s.timbre == timbre {
                s.targetLog = log2(frequency)
                s.autoRelease = .infinity
            } else {
                Self.trigger(&s, frequency: frequency, timbre: timbre, amplitude: amp, autoRelease: .infinity)
            }
        }
    }

    /// Fin de note en douceur.
    func release() {
        state.withLock { s in
            guard s.active && s.gate else { return }
            s.gate = false
            s.releaseFrom = s.env
            s.releaseT = 0
        }
    }

    private func ensureRunning() {
        if !engine.isRunning {
            audioLog.error("Synthé arrêté au moment de jouer, relance")
            try? engine.start()
        }
    }

    // MARK: Synthèse

    private static func amplitude(_ level: Int) -> Double {
        pow(10, Double(min(level, 95) - 100) / 20)
    }

    private static func attackTime(_ timbre: Timbre) -> Double {
        switch timbre {
        case .flute: return 0.06
        case .piano: return 0.005
        case .voice: return 0.08
        }
    }

    private static func releaseTime(_ timbre: Timbre) -> Double {
        switch timbre {
        case .flute: return 0.12
        case .piano: return 0.25
        case .voice: return 0.15
        }
    }

    /// Nouvelle attaque. Si une note sonne encore, on repart de son niveau et de ses phases :
    /// aucune discontinuité, donc aucun clic.
    private static func trigger(_ s: inout Voice, frequency: Double, timbre: Timbre,
                                amplitude: Double, autoRelease: Double) {
        let wasSounding = s.active
        s.startLevel = wasSounding ? s.env : 0
        if !wasSounding {
            for k in 0..<harmonicLimit { s.phases[k] = 0 }
        }
        s.active = true
        s.gate = true
        s.timbre = timbre
        s.amplitude = amplitude
        s.targetLog = log2(frequency)
        s.currentLog = s.targetLog
        s.configuredLog = -100
        s.t = 0
        s.releaseT = 0
        s.autoRelease = autoRelease
    }

    /// Poids des harmoniques selon le timbre et la hauteur, normalisés en valeur efficace
    /// (même niveau perçu d'un timbre à l'autre).
    private static func configure(_ s: inout Voice, limit: Double) {
        let f0 = pow(2, s.currentLog)
        switch s.timbre {
        case .flute:
            s.count = fluteWeights.count
            for k in 0..<s.count {
                s.ratios[k] = Double(k + 1)
                s.weights[k] = fluteWeights[k]
                s.decays[k] = 0
            }
        case .piano:
            // Corde légèrement inharmonique, 7e harmonique atténuée (point de frappe),
            // les aigus s'éteignent plus vite que le fondamental.
            s.count = 14
            let b = 0.0003
            for k in 0..<s.count {
                let n = Double(k + 1)
                s.ratios[k] = n * (1 + b * n * n).squareRoot()
                s.weights[k] = pow(n, -1.2) * (k == 6 ? 0.3 : 1)
                s.decays[k] = 1.1 + 0.45 * n
            }
        case .voice:
            // Voyelle « a » : source riche filtrée par quatre formants.
            s.count = harmonicLimit
            for k in 0..<s.count {
                let n = Double(k + 1)
                let fn = n * f0
                s.ratios[k] = n
                s.weights[k] = (1 / n) * formantGain(fn)
                s.decays[k] = 0
            }
        }
        var sum = 0.0
        for k in 0..<s.count {
            if f0 * s.ratios[k] > limit { s.weights[k] = 0 }
            sum += s.weights[k] * s.weights[k]
        }
        let norm = sum > 0 ? 1 / sum.squareRoot() : 0
        for k in 0..<s.count { s.weights[k] *= norm }
        s.configuredLog = s.currentLog
    }

    private static func formantGain(_ f: Double) -> Double {
        func peak(_ center: Double, _ gain: Double, _ width: Double) -> Double {
            let x = (f - center) / width
            return gain / (1 + x * x)
        }
        return 0.06 + peak(750, 1, 100) + peak(1150, 0.55, 120) + peak(2600, 0.28, 180) + peak(3400, 0.12, 250)
    }

    private static func render(_ s: inout Voice, dt: Double, glide: Double, limit: Double) -> Double {
        // Hauteur : glissement vers la cible, harmoniques recalculées tous les 1/8 de ton.
        s.currentLog += (s.targetLog - s.currentLog) * glide
        if abs(s.currentLog - s.configuredLog) > 1.0 / 48 {
            configure(&s, limit: limit)
        }
        var f0 = pow(2, s.currentLog)
        if s.timbre == .voice {
            // Léger vibrato (7 cents) qui s'installe après l'attaque, centré sur la note.
            let depth = 7 * min(1, max(0, (s.t - 0.3) / 0.5))
            f0 *= pow(2, depth / 1200 * sin(2 * Double.pi * 5.3 * s.t))
        }

        // Enveloppe : attaque en cosinus depuis le niveau courant, relâchement en cosinus.
        if s.gate && s.t >= s.autoRelease {
            s.gate = false
            s.releaseFrom = s.env
            s.releaseT = 0
        }
        var env: Double
        let a = attackTime(s.timbre)
        if s.t < a {
            env = s.startLevel + (1 - s.startLevel) * (0.5 - 0.5 * cos(Double.pi * s.t / a))
        } else {
            env = 1
        }
        if !s.gate {
            let x = s.releaseT / releaseTime(s.timbre)
            if x >= 1 {
                s.active = false
                s.env = 0
                return 0
            }
            env = s.releaseFrom * (0.5 + 0.5 * cos(Double.pi * x))
            s.releaseT += dt
        }
        s.env = env

        var acc = 0.0
        let piano = s.timbre == .piano
        for k in 0..<s.count {
            var w = s.weights[k]
            if w == 0 { continue }
            if piano {
                w *= pianoFloor + (1 - pianoFloor) * exp(-s.decays[k] * s.t)
            }
            acc += w * sin(2 * Double.pi * s.phases[k])
            s.phases[k] += f0 * s.ratios[k] * dt
            if s.phases[k] >= 1 { s.phases[k] -= s.phases[k].rounded(.down) }
        }
        s.t += dt
        return acc * s.amplitude * env
    }
}
