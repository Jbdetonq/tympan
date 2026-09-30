import AVFoundation
import os

/// Mesure le bruit de la pièce au micro pendant quelques secondes.
/// Résultat en dB relatifs (dBFS + 100), non calibré : sert à comparer, pas à mesurer.
enum AmbientNoiseMeter {
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private struct Accumulator {
        var sumSquares: Double = 0
        var count: Int = 0
    }

    static func measure(seconds: Double) async -> Double? {
        guard await requestAccess() else { return nil }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }

        let acc = OSAllocatedUnfairLock(initialState: Accumulator())
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Double = 0
            for i in 0..<n {
                let v = Double(channel[i])
                sum += v * v
            }
            let total = sum
            acc.withLock { a in
                a.sumSquares += total
                a.count += n
            }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return nil
        }
        try? await Task.sleep(for: .seconds(seconds))
        input.removeTap(onBus: 0)
        engine.stop()

        let result = acc.withLock { $0 }
        guard result.count > 0 else { return nil }
        let rms = sqrt(result.sumSquares / Double(result.count))
        let dbfs = 20 * log10(max(rms, 1e-9))
        return dbfs + 100
    }
}
