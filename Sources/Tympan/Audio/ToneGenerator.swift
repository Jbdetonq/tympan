import AVFoundation
import os

let audioLog = Logger(subsystem: "fr.jb.tympan", category: "audio")

/// Génère des sons purs, pulsés (test) ou continus (jeux), sur une oreille ou les deux.
/// Niveau en dB relatifs à l'app : 100 dB = 0 dBFS, donc 0 dB = -100 dBFS.
final class ToneGenerator {
    /// Son en cours, partagé avec le fil audio (protégé par un verrou).
    struct ToneState {
        var active = false
        var frequency: Double = 1000
        var amplitude: Double = 0
        var ear: Ear? = .right          // nil = les deux oreilles
        var pulsed = true
        var frame = 0
        var totalFrames = 0
        var phase: Double = 0
    }

    // Bip du test : 3 impulsions de 200 ms toutes les 350 ms, rampes de 25 ms.
    static let pulseOn = 0.2
    static let pulsePeriod = 0.35
    static let pulseCount = 3
    static let ramp = 0.025
    /// Durée d'une présentation pulsée (3 impulsions de 200 ms).
    static var pulsedDuration: Double { Double(pulseCount - 1) * pulsePeriod + pulseOn }

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let state = OSAllocatedUnfairLock(initialState: ToneState())
    private var sampleRate: Double = 48_000
    private var configObserver: NSObjectProtocol?

    /// Démarre le moteur (ou le relance s'il existe déjà). Le son est synthétisé échantillon
    /// par échantillon dans le fil audio, à partir de `state`.
    func startEngine() throws {
        guard node == nil else {
            if !engine.isRunning { try engine.start() }
            return
        }
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48_000
        audioLog.info("Sortie : \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) canaux")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "Tympan", code: 1)
        }
        let sr = sampleRate
        let state = self.state

        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            state.withLock { s in
                for f in 0..<Int(frameCount) {
                    var sample: Float = 0
                    if s.active {
                        let t = Double(s.frame) / sr
                        let env = s.pulsed
                            ? ToneGenerator.pulsedEnvelope(t)
                            : ToneGenerator.steadyEnvelope(t, total: Double(s.totalFrames) / sr)
                        sample = Float(sin(s.phase) * s.amplitude * env)
                        s.phase += 2 * Double.pi * s.frequency / sr
                        if s.phase > 2 * Double.pi { s.phase -= 2 * Double.pi }
                        s.frame += 1
                        if s.frame >= s.totalFrames { s.active = false }
                    }
                    for (channel, buffer) in buffers.enumerated() {
                        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        let isRightChannel = channel == 1
                        let audible: Bool
                        switch s.ear {
                        case .none: audible = true
                        case .some(.right): audible = isRightChannel
                        case .some(.left): audible = !isRightChannel
                        }
                        data[f] = audible ? sample : 0
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
        audioLog.info("Moteur audio démarré (running: \(self.engine.isRunning))")

        // Changement de sortie (casque branché / débranché) : le moteur s'arrête, on le relance.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            audioLog.info("Configuration audio modifiée, redémarrage")
            try? self.engine.start()
        }
    }

    var isRunning: Bool { engine.isRunning }

    /// Coupe le bip en cours sans arrêter le moteur (arrêt d'urgence).
    func silence() {
        state.withLock { $0.active = false }
    }

    /// Coupe le son et arrête le moteur (fin de test ou de partie).
    func stopEngine() {
        state.withLock { $0.active = false }
        engine.stop()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Présentation pulsée standard du test (0,9 s).
    func play(frequency: Double, level: Int, ear: Ear?) {
        play(frequency: frequency, level: level, ear: ear, duration: Self.pulsedDuration, pulsed: true)
    }

    /// Joue un son de `duration` secondes ; remplace celui en cours. Niveau plafonné à 95 dB app.
    func play(frequency: Double, level: Int, ear: Ear?, duration: Double, pulsed: Bool) {
        let amplitude = pow(10, Double(min(level, 95) - 100) / 20)
        let frames = Int(duration * sampleRate)
        if !engine.isRunning {
            audioLog.error("Moteur arrêté au moment de jouer, relance")
            try? engine.start()
        }
        let earName = ear?.rawValue ?? "both"
        let hz = Int(frequency)
        audioLog.debug("Bip \(hz) Hz, \(level) dB, oreille \(earName)")
        state.withLock { s in
            s = ToneState(active: true, frequency: frequency, amplitude: amplitude, ear: ear,
                          pulsed: pulsed, frame: 0, totalFrames: frames, phase: 0)
        }
    }

    // Rampes en cosinus pour éviter tout clic audible (qui serait un indice).
    static func pulsedEnvelope(_ t: Double) -> Double {
        let tp = t.truncatingRemainder(dividingBy: pulsePeriod)
        if tp >= pulseOn { return 0 }
        if tp < ramp { return 0.5 - 0.5 * cos(Double.pi * tp / ramp) }
        if tp > pulseOn - ramp { return 0.5 - 0.5 * cos(Double.pi * (pulseOn - tp) / ramp) }
        return 1
    }

    /// Son continu : rampes de 50 ms au début et à la fin.
    static func steadyEnvelope(_ t: Double, total: Double) -> Double {
        let r = 0.05
        if t < r { return 0.5 - 0.5 * cos(Double.pi * t / r) }
        if t > total - r { return max(0, 0.5 - 0.5 * cos(Double.pi * (total - t) / r)) }
        return 1
    }
}
