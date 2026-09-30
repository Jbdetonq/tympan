import AppKit
import SwiftUI

/// Écran de test en mode enfant : même TestRunner, présentation en jeu.
/// Un animal apparaît à chaque bip entendu ; un appui dans le vide ne fait rien de visible.
struct KidTestView: View {
    var runner: TestRunner
    let userName: String
    var onClose: (TestSession?) -> Void

    /// Un seuil trouvé = un animal trouvé, dans la couleur de l'oreille (rouge droite, bleu gauche).
    enum Moment: Equatable { case found(Animal, Ear), asleep(Animal, Ear) }
    enum SlotStatus { case hidden, found, asleep }

    @State private var keyMonitor: Any?
    @State private var confirmStop = false
    @State private var moment: Moment?
    @State private var momentToken = 0
    @State private var parentNote = ""
    @State private var announced: Set<String> = []

    var body: some View {
        VStack(spacing: 20) {
            header
            if let error = runner.errorMessage {
                InfoBanner(text: LocalizedStringKey(error))
                Spacer()
            } else {
                banners
                stage
                collection
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Neon.bg)
        .onAppear {
            runner.start()
            installKeyMonitor()
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
        }
        .onChange(of: runner.doneCount) { announceNewThresholds() }
        .confirmationDialog("Arrêter le test ? Les résultats ne seront pas enregistrés.", isPresented: $confirmStop) {
            Button("Arrêter", role: .destructive) {
                runner.cancel()
                onClose(nil)
            }
        }
    }

    /// Un bip entendu ne montre rien : seul un seuil trouvé fait apparaître l'animal.
    /// Aucune réponse jusqu'à 70 dB : l'animal arrive endormi, le jeu continue.
    private func announceNewThresholds() {
        for t in runner.tracks where t.isDone {
            let key = "\(t.ear.rawValue)-\(t.frequency)"
            guard !announced.contains(key), let a = Animal.forFrequency(t.frequency) else { continue }
            announced.insert(key)
            show(t.noResponse ? .asleep(a, t.ear) : .found(a, t.ear))
        }
    }

    private func show(_ m: Moment) {
        moment = m
        momentToken += 1
        let token = momentToken
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if momentToken == token { moment = nil }
        }
    }

    private func status(_ a: Animal, _ ear: Ear) -> SlotStatus {
        guard let t = runner.tracks.first(where: { $0.frequency == a.frequency && $0.ear == ear }), t.isDone else {
            return .hidden
        }
        return t.noResponse ? .asleep : .found
    }

    private var ears: [Ear] { runner.config.earMode.ears }

    // Espace = j'entends, P = pause.
    private func installKeyMonitor() {
        let r = runner
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Test fini : le clavier sert au commentaire (espace, P...).
            if MainActor.assumeIsolated({ r.phase == .finished }) { return event }
            if event.keyCode == 49 {
                if !event.isARepeat {
                    MainActor.assumeIsolated { r.respond() }
                }
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "p" {
                MainActor.assumeIsolated { r.togglePause() }
                return nil
            }
            return event
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 16) {
            Text("Mode enfant")
                .font(.system(size: 13, weight: .semibold).width(.condensed))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Neon.mint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: 0x0F2A22), in: RoundedRectangle(cornerRadius: 6))
            Text(verbatim: userName).font(.system(size: 18, weight: .semibold))
            Spacer()
            if runner.phase != .finished {
                progressBar
                Button(runner.isPaused ? "Reprendre" : "Pause") { runner.togglePause() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Arrêter") {
                    if runner.phase >= .measuring { confirmStop = true } else { runner.cancel(); onClose(nil) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var progressBar: some View {
        let value = runner.phase >= .measuring ? runner.measureProgress : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(Neon.mint)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
                    .shadow(color: Neon.mint, radius: 4)
            }
        }
        .frame(width: 140, height: 6)
        .accessibilityLabel(Text("Progression"))
    }

    @ViewBuilder
    private var banners: some View {
        AudioHoldBanner(lock: runner.volumeLock)
        if runner.outputChanged {
            InfoBanner(text: "La sortie audio a changé (casque débranché ?). Rebranche-le puis appuie sur Reprendre.")
        }
        if runner.headphonesOnSpeaker {
            InfoBanner(text: "Le son sort par les haut-parleurs du Mac. Branche le casque puis relance le test.")
        }
        if runner.noisy {
            InfoBanner(text: "Pièce bruyante : le test continue, mais cette session sera exclue des comparaisons.")
        }
    }

    // MARK: Grande zone à taper

    @ViewBuilder
    private var stage: some View {
        if runner.phase == .finished {
            stageFrame { endContent }
        } else {
            Button {
                runner.respond()
            } label: {
                stageFrame { playContent }
            }
            .buttonStyle(SilentButtonStyle())
            .accessibilityLabel(Text("J'entends le bruit"))
        }
    }

    private func stageFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            StarField()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Neon.stage, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Neon.stageBorder))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private var playContent: some View {
        VStack(spacing: 18) {
            switch moment {
            case .found(let a, let ear):
                AnimalIcon(animal: a, color: Theme.color(for: ear))
                    .frame(width: 240, height: 220)
                    .neonGlow(Theme.color(for: ear), radius: 10)
                    .id(momentToken)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                Text(a.found)
                    .font(.system(size: 44, weight: .bold))
                    .shadow(color: Theme.color(for: ear).opacity(0.45), radius: 18)
                    .multilineTextAlignment(.center)
                Text("Continue, d'autres animaux se cachent.")
                    .font(.system(size: 20))
                    .foregroundStyle(Neon.caption)
            case .asleep(let a, _):
                ZStack(alignment: .topTrailing) {
                    AnimalIcon(animal: a, asleep: true)
                        .frame(width: 240, height: 220)
                    Text(verbatim: "z z z")
                        .font(Theme.mono(28, .semibold))
                        .foregroundStyle(Neon.dim)
                }
                .id(momentToken)
                .transition(.opacity)
                Text(a.asleep)
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("On continue avec les autres !")
                    .font(.system(size: 20))
                    .foregroundStyle(Neon.caption)
            case nil:
                Image(systemName: "ear")
                    .font(.system(size: 90, weight: .light))
                    .foregroundStyle(Neon.mint.opacity(0.35))
                    .neonGlow(Neon.mint.opacity(0.3), radius: 8)
                Text(idleTitle)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(idleSubtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(Neon.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: momentToken)
        .animation(.easeOut(duration: 0.3), value: moment)
    }

    private var idleTitle: LocalizedStringKey {
        if runner.isPaused { return "Pause" }
        switch runner.phase {
        case .headphones, .ambient: return "Chut… on écoute la pièce"
        default: return "Des animaux se cachent dans les bruits"
        }
    }

    private var idleSubtitle: LocalizedStringKey {
        if runner.isPaused { return "Appuie sur Reprendre quand tu veux continuer." }
        switch runner.phase {
        case .headphones, .ambient: return "Reste bien silencieux quelques secondes."
        default: return "Tape dès que tu entends le petit bruit, même tout doux."
        }
    }

    private var foundCount: Int {
        Animal.allCases.reduce(0) { n, a in n + ears.filter { status(a, $0) == .found }.count }
    }
    private var totalCount: Int { Animal.allCases.count * ears.count }
    private var hasAsleep: Bool {
        Animal.allCases.contains { a in ears.contains { status(a, $0) == .asleep } }
    }

    private var endContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ForEach(Animal.allCases) { a in
                    AnimalPair(animal: a, ears: ears, size: 56) { status(a, $0) }
                }
            }
            Text("Bravo, c'est fini !")
                .font(.system(size: 44, weight: .bold))
            Text(foundCount <= 1 ? LocalizedStringKey("Tu as trouvé \(foundCount) animal sur \(totalCount).")
                                 : LocalizedStringKey("Tu as trouvé \(foundCount) animaux sur \(totalCount)."))
                .font(.system(size: 20))
                .foregroundStyle(Neon.caption)
            if let session = runner.result {
                Text("Pour les parents : rouge = oreille droite, bleu = oreille gauche.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                if hasAsleep {
                    Text("Animal endormi : pas de réponse à 70 dB. À vérifier avec un test adulte, et chez un ORL au moindre doute.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                } else if needsCheck(session) {
                    Text("Résultat à confirmer (appuis au hasard ou pièce bruyante).")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                SessionNoteField(text: $parentNote, background: Neon.card)
                    .frame(maxWidth: 480)
                    .padding(.top, 6)
                Button("Enregistrer et voir l'historique") {
                    var saved = session
                    saved.note = TestSession.cleanNote(parentNote)
                    onClose(saved)
                }
                    .buttonStyle(NeonButtonStyle(color: Neon.mint))
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 8)
            }
        }
        .padding(40)
    }

    private func needsCheck(_ s: TestSession) -> Bool {
        s.noisy || (s.reliability.map { $0 < 0.8 } ?? false) || s.spuriousPresses > 3
    }

    // MARK: Collection

    private var collection: some View {
        HStack(spacing: 14) {
            SectionLabel("Ma collection").frame(width: 110, alignment: .leading)
            HStack(spacing: 12) {
                ForEach(Animal.allCases) { a in
                    AnimalPair(animal: a, ears: ears, size: 40, highlight: highlightedEar(a)) { status(a, $0) }
                        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(highlightedEar(a).map { Theme.color(for: $0) } ?? Neon.dashed,
                                              style: StrokeStyle(lineWidth: highlightedEar(a) == nil ? 1 : 1.5,
                                                                 dash: highlightedEar(a) == nil ? [5, 4] : []))
                        )
                        .scaleEffect(highlightedEar(a) == nil ? 1 : 1.06)
                        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: highlightedEar(a))
                }
            }
        }
    }

    private func highlightedEar(_ a: Animal) -> Ear? {
        if case .found(let m, let ear) = moment, m == a { return ear }
        return nil
    }
}

/// Un animal par oreille : rouge (droite), bleu (gauche), gris endormi, "?" pas encore trouvé.
private struct AnimalPair: View {
    let animal: Animal
    let ears: [Ear]
    let size: CGFloat
    var highlight: Ear? = nil
    let status: (Ear) -> KidTestView.SlotStatus

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ears) { ear in
                Group {
                    switch status(ear) {
                    case .hidden:
                        Text(verbatim: "?")
                            .font(.system(size: size * 0.55, weight: .bold))
                            .foregroundStyle(Neon.off)
                    case .found:
                        AnimalIcon(animal: animal, color: Theme.color(for: ear))
                            .neonGlow(Theme.color(for: ear), radius: highlight == ear ? 6 : 3)
                    case .asleep:
                        AnimalIcon(animal: animal, asleep: true)
                    }
                }
                .frame(width: size, height: size * 0.9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(animal.name))
    }
}

/// Ciel étoilé et vague discrète en fond de la zone de jeu.
private struct StarField: View {
    private let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.10, 0.14, 1.5), (0.25, 0.25, 1), (0.82, 0.16, 1.5), (0.92, 0.39, 1), (0.17, 0.75, 1),
        (0.72, 0.84, 1.5), (0.87, 0.71, 1), (0.35, 0.11, 1), (0.60, 0.07, 1.2), (0.05, 0.54, 1.2),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(stars.indices, id: \.self) { i in
                    let s = stars[i]
                    Circle().fill(Color.white.opacity(0.5))
                        .frame(width: s.2 * 2, height: s.2 * 2)
                        .position(x: s.0 * w, y: s.1 * h)
                }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.84))
                    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.84), control: CGPoint(x: w * 0.25, y: h * 0.75))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.82), control: CGPoint(x: w * 0.75, y: h * 0.93))
                }
                .stroke(Neon.cyan.opacity(0.18), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Aucun retour visuel à l'appui : seul un bip réellement entendu fait apparaître un animal.
struct SilentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
