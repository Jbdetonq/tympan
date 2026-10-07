import AppKit
import CoreAudio
import Foundation
import Observation

/// Verrouille le volume de la sortie audio pendant un test ou un jeu, en protégeant les oreilles.
///
/// - Le volume du profil casque n'est imposé que si le Mac est silencieux par ailleurs :
///   si une autre app joue du son (musique, vidéo, notification), le volume habituel est
///   rétabli et le test attend (sinon cette musique sortirait au volume du test).
/// - Échap coupe le son aussitôt (arrêt d'urgence). La touche muet est respectée.
///   Dans les deux cas le test attend ; Reprendre (dans le bandeau) réactive le son.
/// - Le volume d'origine est rétabli à la fin, à la fermeture de l'app (Cmd+Q)
///   et même au lancement suivant après un plantage.
@MainActor
@Observable
final class VolumeLock {
    enum Hold: Equatable {
        /// Son coupé : Échap (`emergency`) ou touche muet.
        case muted(emergency: Bool)
        /// Une autre app joue du son sur cette sortie (liste vide : app inconnue).
        case otherAudio([String])
    }

    let device: AudioDeviceID
    let target: Float

    /// Raison de l'attente, nil quand le volume du test est appliqué.
    private(set) var hold: Hold?
    /// Incrémenté à chaque début d'attente : un essai interrompu n'est pas compté.
    private(set) var holdCount = 0

    /// Coupe le son de l'app elle-même (appelé par Échap, en plus du muet système).
    @ObservationIgnored var onEmergency: (() -> Void)?

    @ObservationIgnored private var savedVolume: Float?
    @ObservationIgnored private var savedMute = false
    @ObservationIgnored private var emergency = false
    @ObservationIgnored private var mutedByUs = false
    @ObservationIgnored private var zeroedByUs = false
    /// Volume juste avant la mise à zéro d'Échap (sortie sans commande muet).
    @ObservationIgnored private var volumeBeforeZero: Float?
    @ObservationIgnored private var raised = false
    @ObservationIgnored private var everActive = false
    @ObservationIgnored private var ignoredApps: Set<String> = []
    @ObservationIgnored private var ignoreUnnamed = false
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var timer: Timer?

    init(device: AudioDeviceID, target: Float) {
        self.device = device
        self.target = min(max(target.isFinite ? target : 0.5, 0), 1)
    }

    // MARK: Cycle de vie

    func engage() {
        savedVolume = SystemAudio.volume(of: device)
        savedMute = SystemAudio.isMuted(device)
        Self.register(self)
        for address in SystemAudio.listenAddresses() {
            var addr = address
            guard AudioObjectHasProperty(device, &addr) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.evaluate(checkOthers: false) }
            }
            if AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block) == noErr {
                listeners.append((address, block))
            }
        }
        evaluate(checkOthers: true)
        // Surveillance continue : volume imposé, muet, autres sons.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                self.tick += 1
                self.evaluate(checkOthers: self.tick % 2 == 0)
            }
        }
    }

    func release() {
        timer?.invalidate()
        timer = nil
        for (address, block) in listeners {
            var addr = address
            AudioObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
        listeners.removeAll()
        // Avant restoreUserVolume : si le volume du test était appliqué, c'est lui qui rend le volume d'origine.
        undoZero()
        restoreUserVolume()
        if savedMute {
            SystemAudio.setMuted(true, of: device)
        } else if mutedByUs {
            SystemAudio.setMuted(false, of: device)
        }
        mutedByUs = false
        zeroedByUs = false
        hold = nil
        Self.unregister(self)
        Self.clearCrashRecord()
    }

    // MARK: Commandes (bandeau et clavier)

    /// Arrêt d'urgence : coupe le son tout de suite, le test attend Reprendre.
    func emergencyStop() {
        onEmergency?()
        emergency = true
        if SystemAudio.canMute(device) {
            if !SystemAudio.isMuted(device) {
                SystemAudio.setMuted(true, of: device)
                mutedByUs = true
            }
        } else {
            // Sortie sans commande muet : volume à zéro, rendu à Reprendre ou à la fin.
            if !zeroedByUs {
                volumeBeforeZero = SystemAudio.volume(of: device)
                if !raised { Self.writeCrashRecord(device: device, volume: volumeBeforeZero, muted: savedMute) }
            }
            SystemAudio.setVolume(0, of: device)
            zeroedByUs = true
        }
        audioLog.info("Arrêt d'urgence (Échap)")
        evaluate(checkOthers: false)
    }

    /// Reprendre après Échap ou muet : réactive le son, le volume du test revient.
    func resumeSound() {
        emergency = false
        undoZero()
        if SystemAudio.isMuted(device) { SystemAudio.setMuted(false, of: device) }
        mutedByUs = false
        evaluate(checkOthers: true)
    }

    /// L'utilisateur confirme que les sons détectés sont inaudibles (app qui garde la sortie ouverte).
    func ignoreOtherAudio() {
        if case .otherAudio(let names) = hold {
            if names.isEmpty { ignoreUnnamed = true } else { ignoredApps.formUnion(names) }
        }
        evaluate(checkOthers: true)
    }

    // MARK: Logique

    private func evaluate(checkOthers: Bool) {
        var newHold: Hold?
        if emergency {
            newHold = .muted(emergency: true)
        } else if SystemAudio.isMuted(device) {
            newHold = .muted(emergency: false)
        } else if checkOthers {
            let others = otherAudio()
            if let others { newHold = .otherAudio(others) }
        } else if case .otherAudio = hold {
            newHold = hold
        }

        if let newHold {
            if hold == nil { holdCount += 1 }
            if hold != newHold { hold = newHold }
            if case .otherAudio = newHold { restoreUserVolume() }
            return
        }

        if hold != nil {
            // Fin d'attente : si l'utilisateur a changé son volume entre-temps, c'est le nouveau qu'on rétablira.
            if !raised, let v = SystemAudio.volume(of: device) { savedVolume = v }
            hold = nil
        }
        everActive = true
        applyTarget()
    }

    /// Noms des autres apps qui jouent sur cette sortie, nil si aucune.
    private func otherAudio() -> [String]? {
        if #available(macOS 14.2, *) {
            let names = SystemAudio.otherAppsPlaying(on: device).filter { !ignoredApps.contains($0) }
            return names.isEmpty ? nil : names
        }
        // macOS 14.0 / 14.1 : seul test possible avant que Tympan ne joue lui-même.
        if !everActive, !ignoreUnnamed, SystemAudio.isRunningSomewhere(device) {
            return []
        }
        return nil
    }

    private func applyTarget() {
        if !raised {
            raised = true
            Self.writeCrashRecord(device: device, volume: savedVolume, muted: savedMute)
        }
        if let v = SystemAudio.volume(of: device), abs(v - target) > 0.005 {
            SystemAudio.setVolume(target, of: device)
        }
    }

    /// Annule la mise à zéro d'Échap. Si le volume du test était appliqué, applyTarget ou
    /// restoreUserVolume s'en chargent ; sinon (attente d'un autre son), on rend le volume d'avant Échap.
    private func undoZero() {
        guard zeroedByUs else { return }
        zeroedByUs = false
        if !raised, let v = volumeBeforeZero { SystemAudio.setVolume(v, of: device) }
        volumeBeforeZero = nil
    }

    private func restoreUserVolume() {
        guard raised else { return }
        raised = false
        if let v = savedVolume { SystemAudio.setVolume(v, of: device) }
    }

    // MARK: Registre (Échap, fermeture de l'app)

    private static var engaged = NSHashTable<VolumeLock>.weakObjects()
    private static var escMonitor: Any?
    /// Dernier appui sur Échap pendant un verrou.
    private static var lastEsc: Date?

    private static func register(_ lock: VolumeLock) {
        engaged.add(lock)
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // Échap
            // Son déjà coupé : les appuis en rafale (moins d'une seconde après le précédent)
            // sont ignorés, pour qu'un réflexe n'ouvre pas « Quitter ». Après, Échap passe.
            let handled = MainActor.assumeIsolated { () -> Bool in
                let now = Date()
                let burst = VolumeLock.lastEsc.map { now.timeIntervalSince($0) < 1 } ?? false
                VolumeLock.lastEsc = now
                let active = VolumeLock.engaged.allObjects.filter { !$0.emergency }
                active.forEach { $0.emergencyStop() }
                return !active.isEmpty || (burst && !VolumeLock.engaged.allObjects.isEmpty)
            }
            return handled ? nil : event
        }
    }

    private static func unregister(_ lock: VolumeLock) {
        engaged.remove(lock)
        if engaged.allObjects.isEmpty, let m = escMonitor {
            NSEvent.removeMonitor(m)
            escMonitor = nil
        }
    }

    /// Fermeture de l'app : rend le volume d'origine.
    static func releaseAll() {
        engaged.allObjects.forEach { $0.release() }
    }

    // MARK: Plantage : volume rétabli au lancement suivant

    private static let crashKey = "tympan.volumeRestore"

    private static func writeCrashRecord(device: AudioDeviceID, volume: Float?, muted: Bool) {
        guard let uid = SystemAudio.uid(of: device) else { return }
        var record: [String: Any] = ["uid": uid, "muted": muted]
        if let volume { record["volume"] = volume }
        UserDefaults.standard.set(record, forKey: crashKey)
    }

    private static func clearCrashRecord() {
        guard engaged.allObjects.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: crashKey)
    }

    /// À appeler au lancement : si l'app s'est arrêtée pendant un test, remet le volume d'avant.
    static func recoverAfterCrash() {
        guard let record = UserDefaults.standard.dictionary(forKey: crashKey) else { return }
        UserDefaults.standard.removeObject(forKey: crashKey)
        guard let uid = record["uid"] as? String, let device = SystemAudio.device(uid: uid) else { return }
        if let volume = record["volume"] as? Float { SystemAudio.setVolume(volume, of: device) }
        if let muted = record["muted"] as? Bool, muted { SystemAudio.setMuted(true, of: device) }
        audioLog.info("Volume d'origine rétabli après un arrêt inattendu")
    }
}
