import CoreAudio
import SwiftUI

/// Configuration avant un audiogramme, en page. En mode enfant, sert aussi
/// de page d'accueil du jeu (sans podium : c'est un vrai test).
struct NewTestPage: View {
    @Environment(DataStore.self) private var store
    let user: UserProfile
    /// Format imposé par un bandeau de la fiche ; sinon celui du dernier test.
    var suggestedLength: TestLength? = nil
    var kidMode = false
    /// Utilisateur sélectionné (le mode enfant permet d'en changer sur place).
    @Binding var selection: UUID?
    /// Retour à la fiche ; nil quand la page est une entrée du menu.
    var onCancel: (() -> Void)?
    var onStart: (TestConfig) -> Void

    @State private var earMode: EarMode = .both
    @State private var length: TestLength = .standard
    @State private var headphoneID: UUID?
    /// Formulaire de nouveau profil casque ouvert.
    @State private var creatingProfile = false
    @State private var newName = ""
    @State private var newVolume: Double = 0.5
    /// Sortie audio active au moment d'ouvrir la page.
    @State private var deviceName = ""
    @State private var onSpeaker = false
    /// Générateur du bip de réglage (distinct de celui du test).
    @State private var preview = ToneGenerator()
    /// État de la sortie avant le premier bip de réglage, rendu en quittant la page.
    @State private var originalVolume: Float?
    @State private var originalMuted = false
    @State private var previewDevice: AudioDeviceID?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewError: String?

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(kidGame ? Neon.bg : Theme.bg)
        .onAppear(perform: setup)
        .onDisappear(perform: stopPreview)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            if kidGame {
                kidHeader
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nouveau test · \(user.name)").font(.system(size: 28, weight: .semibold))
                    Text("Durée estimée : environ \(effectiveLength.estimatedMinutes(ears: earMode.ears.count)) min")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }

            if !kidGame {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Durée")
                    HStack(spacing: 12) {
                        ForEach(TestLength.adultCases) { l in lengthCard(l) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Oreilles testées")
                HStack(spacing: 12) {
                    modeCard(.both, title: "Les deux, mélangées",
                             detail: "L'oreille change au hasard à chaque bip. Recommandé.")
                    modeCard(.right, title: "Droite seule", detail: "Pour suivre une oreille précise.")
                    modeCard(.left, title: "Gauche seule", detail: "Pour suivre une oreille précise.")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Profil casque")
                if creatingProfile || store.data.headphones.isEmpty {
                    newProfileForm
                } else {
                    HStack(spacing: 12) {
                        Picker("Profil casque", selection: $headphoneID) {
                            ForEach(store.data.headphones) { h in
                                Text("\(h.name) · volume \(Int(h.volume * 100)) %").tag(Optional(h.id))
                            }
                        }
                        .labelsHidden()
                        Button {
                            if let h = store.headphone(headphoneID) { playPreview(volume: h.volume) }
                        } label: {
                            Label("Écouter", systemImage: "speaker.wave.2")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(store.headphone(headphoneID) == nil)
                        Button("Nouveau profil…") {
                            newName = deviceName
                            creatingProfile = true
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                deviceStatus
            }

            HStack(spacing: 12) {
                if let onCancel {
                    Button("Retour") { onCancel() }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if kidGame {
                    Button {
                        start()
                    } label: {
                        Label("Jouer", systemImage: "play.fill")
                    }
                    .buttonStyle(NeonButtonStyle(color: Neon.mint))
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.headphone(headphoneID) == nil || creatingProfile)
                } else {
                    Button("Lancer le test") { start() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(store.headphone(headphoneID) == nil || creatingProfile)
                }
            }
        }
    }

    // MARK: Mode enfant

    private var kidHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Neon.mint)
                    .neonGlow(Neon.mint, radius: 3)
                Text("Mode enfant").font(.system(size: 28, weight: .semibold))
                Spacer()
                PlayerPicker(selection: $selection)
            }
            Text("Cinq animaux se cachent derrière des petits bips, du plus grave au plus aigu. Dès que tu entends un bip, appuie sur la barre espace ou clique. Chaque animal trouvé se réveille !")
                .font(.system(size: 15))
                .foregroundStyle(Neon.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ForEach(Animal.allCases) { a in
                    VStack(spacing: 8) {
                        AnimalIcon(animal: a)
                            .frame(width: 60, height: 48)
                            .neonGlow(a.color, radius: 3)
                        Text(a.name).font(.system(size: 14, weight: .semibold))
                        Text(verbatim: "\(Format.hz(a.frequency)) Hz")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Neon.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Neon.cardBorder))
                }
            }
            Text("C'est un vrai test : il s'ajoute à l'audiogramme de \(user.name). Pas de classement ici.")
                .font(.system(size: 12))
                .foregroundStyle(Neon.footnote)
        }
    }

    /// Bip de réglage : 1 kHz, niveau modéré, droite puis gauche (vérifie aussi le câblage G/D).
    private func playPreview(volume: Float) {
        guard let d = SystemAudio.defaultOutputDevice() else { return }
        // Jamais monter le volume si un autre son joue : il sortirait fort lui aussi.
        if let others = otherAudio(on: d) {
            previewError = others.isEmpty
                ? String(localized: "Un autre son joue sur le Mac. Coupe-le avant le bip de réglage.")
                : String(localized: "Un autre son joue sur le Mac (\(others.joined(separator: ", "))). Coupe-le avant le bip de réglage.")
            return
        }
        if previewDevice != d {
            // Première écoute, ou sortie changée depuis : on rend l'ancienne et on mémorise la nouvelle.
            restoreOutput()
            previewDevice = d
            originalVolume = SystemAudio.volume(of: d)
            originalMuted = SystemAudio.isMuted(d)
        }
        if SystemAudio.isMuted(d) { SystemAudio.setMuted(false, of: d) }
        SystemAudio.setVolume(volume, of: d)
        do {
            try preview.startEngine()
            previewError = nil
        } catch {
            previewError = String(localized: "Audio indisponible : \(error.localizedDescription)")
            return
        }
        previewTask?.cancel()
        let tone = preview
        previewTask = Task {
            tone.play(frequency: 1000, level: 70, ear: .right, duration: 0.6, pulsed: false)
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            tone.play(frequency: 1000, level: 70, ear: .left, duration: 0.6, pulsed: false)
        }
    }

    /// Autres apps qui jouent sur la sortie (nil si aucune, liste vide si inconnue).
    private func otherAudio(on d: AudioDeviceID) -> [String]? {
        if #available(macOS 14.2, *) {
            let names = SystemAudio.otherAppsPlaying(on: d)
            return names.isEmpty ? nil : names
        }
        return !preview.isRunning && SystemAudio.isRunningSomewhere(d) ? [] : nil
    }

    /// Coupe le bip de réglage et rend la sortie dans son état d'origine.
    private func stopPreview() {
        previewTask?.cancel()
        preview.stopEngine()
        restoreOutput()
    }

    /// Rend à la sortie modifiée par le bip de réglage son volume et son muet d'origine.
    private func restoreOutput() {
        guard let d = previewDevice else { return }
        if let v = originalVolume { SystemAudio.setVolume(v, of: d) }
        if originalMuted { SystemAudio.setMuted(true, of: d) }
        previewDevice = nil
        originalVolume = nil
        originalMuted = false
    }

    /// Carte de choix du format (Rapide, Moyen, Complet) avec sa durée estimée.
    private func lengthCard(_ l: TestLength) -> some View {
        let selected = length == l
        return Button {
            length = l
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                    Text(l.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(verbatim: "~\(l.estimatedMinutes(ears: earMode.ears.count)) min")
                        .font(Theme.mono(13, .semibold))
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                }
                Text(l.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.secondary : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(selected ? Color(hex: 0x1C1A15) : Theme.panelDeep, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Carte de choix des oreilles testées.
    private func modeCard(_ mode: EarMode, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        let selected = earMode == mode
        return Button {
            earMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                    Text(title).font(.system(size: 14, weight: .semibold))
                }
                HStack(spacing: 18) {
                    EarSymbol(ear: .right, dimmed: mode == .left)
                    EarSymbol(ear: .left, dimmed: mode == .right)
                }
                .padding(.leading, 4)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.secondary : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(selected ? Color(hex: 0x1C1A15) : Theme.panelDeep, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Création d'un profil casque : nom et volume, réglé à l'oreille avec le bip de réglage.
    private var newProfileForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Nom du casque", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Text("Volume").foregroundStyle(Theme.secondary)
                Slider(value: $newVolume, in: 0.1...1.0, step: 0.05, onEditingChanged: { editing in
                    if !editing { playPreview(volume: Float(newVolume)) }
                })
                Text("\(Int(newVolume * 100)) %")
                    .font(Theme.mono(13))
                    .frame(width: 48, alignment: .trailing)
                Button {
                    playPreview(volume: Float(newVolume))
                } label: {
                    Label("Écouter", systemImage: "speaker.wave.2")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Text("Un bip de réglage sonne dans l'oreille droite puis la gauche à chaque changement. Il doit être net et confortable, jamais fort. Ce volume sera ensuite imposé à chaque test avec ce casque : c'est ce qui rend les tests comparables.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !store.data.headphones.isEmpty {
                    Button("Annuler") { creatingProfile = false }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Créer le profil") {
                    let p = store.addHeadphone(name: newName.trimmingCharacters(in: .whitespaces),
                                               volume: Float(newVolume))
                    headphoneID = p.id
                    creatingProfile = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(Theme.panelDeep, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Sortie audio active, alerte si c'est le haut-parleur du Mac, erreur du bip de réglage.
    @ViewBuilder
    private var deviceStatus: some View {
        if let previewError {
            Text(verbatim: previewError).font(.system(size: 13)).foregroundStyle(Theme.accent)
        }
        if onSpeaker {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.accent)
                Text("Aucun casque détecté : le son sortirait par les haut-parleurs du Mac. Branche ton casque.")
                    .foregroundStyle(Theme.accent)
            }
            .font(.system(size: 13))
        } else if !deviceName.isEmpty {
            HStack(spacing: 8) {
                Circle().fill(Theme.ok).frame(width: 8, height: 8)
                Text("Sortie active : \(deviceName)")
                    .foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 13))
        }
    }

    /// Valeurs de départ : sortie active, dernier casque et dernier format adulte de l'utilisateur.
    private func setup() {
        if let d = SystemAudio.defaultOutputDevice() {
            deviceName = SystemAudio.name(of: d)
            onSpeaker = SystemAudio.isBuiltInSpeaker(d)
            if let v = SystemAudio.volume(of: d) { newVolume = Double(max(0.1, v)) }
        }
        newName = deviceName
        headphoneID = user.sortedSessions.first?.headphoneID ?? store.data.headphones.first?.id
        let last = user.sortedSessions.first { $0.format != .kid }?.length
        length = suggestedLength ?? last ?? .standard
    }

    private var kidGame: Bool { kidMode }
    private var effectiveLength: TestLength { kidGame ? .kid : length }

    /// Lance le test : le bip de réglage s'arrête avant.
    private func start() {
        guard let h = store.headphone(headphoneID) else { return }
        stopPreview()
        onStart(TestConfig(userID: user.id, earMode: earMode, headphone: h, length: effectiveLength, kidMode: kidGame))
    }
}
