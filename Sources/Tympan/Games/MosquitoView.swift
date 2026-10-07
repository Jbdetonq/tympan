import AppKit
import SwiftUI

struct MosquitoView: View {
    @Environment(DataStore.self) private var store
    var game: MosquitoGame
    let playerName: String
    /// Retour à la page d'accueil du jeu, avec le résultat (nil si la partie a été quittée).
    var onClose: (MosquitoResult?) -> Void

    @State private var keyMonitor: Any?
    @State private var previousBest: Int?
    @State private var saved = false
    @State private var closed = false
    @State private var confirmQuit = false

    var body: some View {
        VStack(spacing: 20) {
            header
            HStack(alignment: .top, spacing: 24) {
                stage
                aside.frame(width: 320)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Neon.bg)
        .onAppear {
            previousBest = store.mosquitoBest(for: game.config.userID)
            game.start()
            installKeyMonitor()
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
            game.cancel()
        }
        .onChange(of: game.phase) {
            if game.phase == .over { finish() }
        }
        .confirmationDialog("Quitter la partie ? Ton meilleur moustique de la partie est gardé.",
                            isPresented: $confirmQuit) {
            Button("Quitter", role: .destructive) {
                game.cancel()
                save()
                close(nil)
            }
        }
    }

    /// Fin de partie : on enregistre, puis retour à la page d'accueil avec le bandeau de résultat.
    private func finish() {
        save()
        let result = MosquitoResult(userID: game.config.userID, best: game.best,
                                    previousBest: previousBest, won: game.won)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            close(result)
        }
    }

    private func close(_ result: MosquitoResult?) {
        guard !closed else { return }
        closed = true
        onClose(result)
    }

    /// Une partie interrompue garde son score si au moins un moustique a été attrapé.
    private func save() {
        guard !saved, game.best != nil else { return }
        store.addMosquitoGame(game.record)
        saved = true
    }

    private func quit() {
        if game.phase == .over || game.errorMessage != nil {
            game.cancel()
            close(nil)
        } else {
            confirmQuit = true
        }
    }

    // 1, 2, 3 (rangée du haut ou pavé numérique) = choisir, R = réécouter.
    private func installKeyMonitor() {
        let g = game
        let jars: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 83: 0, 84: 1, 85: 2]
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.isARepeat { return event }
            if let i = jars[event.keyCode] {
                MainActor.assumeIsolated { g.choose(i) }
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "r" {
                MainActor.assumeIsolated { g.replay() }
                return nil
            }
            return event
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                quit()
            } label: {
                Label("Quitter", systemImage: "chevron.left")
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
            MosquitoIcon()
                .frame(width: 58, height: 36)
                .neonGlow(Neon.pink, radius: 4)
                .padding(.leading, 6)
            Text("Chasse au moustique").font(.system(size: 22, weight: .semibold))
            Spacer()
            HStack(spacing: 4) {
                Text("Joueur :").foregroundStyle(Theme.muted)
                Text(verbatim: playerName).fontWeight(.semibold)
            }
            .font(.system(size: 14))
        }
    }

    // MARK: Scène

    private var stage: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let error = game.errorMessage {
                InfoBanner(verbatim: error)
                Spacer()
            } else if game.phase == .over {
                endScreen
            } else {
                roundHeader
                AudioHoldBanner(lock: game.volumeLock)
                jars
                footer
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Neon.stage, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Neon.stageBorder))
    }

    private var roundHeader: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Manche \(game.round)", color: Neon.pinkSoft)
                Text(title).font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(missed ? Neon.red : Theme.text)
                    .animation(.easeOut(duration: 0.15), value: missed)
                Text(subtitle).font(.system(size: 16)).foregroundStyle(Neon.caption)
            }
            Spacer()
            LivesView(lives: game.lives, total: MosquitoGame.lifeCount)
        }
    }

    private var canAnswer: Bool { game.phase == .listening || game.phase == .choosing }

    private var missed: Bool { game.phase == .feedback && !game.lastCorrect }

    private var title: LocalizedStringKey {
        if game.outputChanged { return "Le casque a été débranché ?" }
        switch game.phase {
        case .starting: return "Prépare tes oreilles…"
        case .listening: return "Écoute bien les trois bocaux"
        case .choosing: return "Dans quel bocal se cache le moustique ?"
        case .feedback:
            return game.lastCorrect ? "Attrapé ! Il file vers les aigus." : "Raté ! Il était dans le bocal \(game.mosquitoJar + 1)."
        case .over: return ""
        }
    }

    private var subtitle: LocalizedStringKey {
        if game.outputChanged { return "Rebranche-le, puis appuie sur Reprendre." }
        switch game.phase {
        case .starting: return "Il se cache dans un seul bocal, jamais le même."
        case .listening: return "Un seul bourdonne. Choisis dès que tu l'entends."
        case .choosing: return "Choisis un bocal. Tu n'entends plus rien ? Arrête la partie en bas."
        case .feedback:
            if game.lastCorrect { return "Manche suivante : encore plus aigu." }
            return game.lives > 0 ? "On recommence avec le même son." : "Plus de vies."
        case .over: return ""
        }
    }

    private var jars: some View {
        HStack(spacing: 24) {
            ForEach(0..<3, id: \.self) { i in
                JarButton(number: i + 1, look: look(for: i)) { game.choose(i) }
                    .allowsHitTesting(game.phase == .listening || game.phase == .choosing)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func look(for i: Int) -> JarLook {
        switch game.phase {
        case .feedback:
            if i == game.mosquitoJar { return game.lastCorrect ? .caught : .revealed }
            return i == game.choice ? .wrong : .heard
        case .choosing:
            return .choosable
        default:
            if game.playingJar == i { return .playing }
            return game.heard.contains(i) ? .heard : .pending
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(game.phase == .choosing || game.phase == .listening
                 ? LocalizedStringKey("Touches 1, 2, 3 pour choisir, R pour réécouter.")
                 : LocalizedStringKey("Volume du casque verrouillé pendant la partie."))
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            Spacer()
            if game.outputChanged {
                Button("Reprendre") { game.resume() }
                    .buttonStyle(NeonButtonStyle())
            } else {
                Button("Je n'entends plus rien") { game.giveUp() }
                    .buttonStyle(SecondaryButtonStyle())
                    .opacity(canAnswer ? 1 : 0.35)
                    .allowsHitTesting(canAnswer)
                Button {
                    game.replay()
                } label: {
                    Label("Réécouter", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .opacity(game.phase == .choosing ? 1 : 0.35)
                .allowsHitTesting(game.phase == .choosing)
            }
        }
    }

    // MARK: Fin de partie

    /// Écran bref avant le retour à la page d'accueil (le résultat s'y affiche en bandeau).
    private var endScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            MosquitoIcon(color: game.won ? Neon.mint : Neon.pink)
                .frame(width: 220, height: 132)
                .neonGlow(game.won ? Neon.mint : Neon.pink, radius: 10)
            Text(game.won ? LocalizedStringKey("Incroyable, tu l'as suivi jusqu'au bout !") : LocalizedStringKey("Partie terminée"))
                .font(.system(size: 40, weight: .bold))
                .multilineTextAlignment(.center)
            if game.gaveUp {
                Text(game.best == nil
                     ? LocalizedStringKey("Le moustique était trop aigu dès le départ.")
                     : LocalizedStringKey("Tu l'as entendu jusqu'à \(Format.hz(game.best ?? 0)) Hz."))
                    .font(.system(size: 18))
                    .foregroundStyle(Neon.caption)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Colonne de droite

    private var aside: some View {
        VStack(spacing: 16) {
            NeonCard {
                SectionLabel("Record de la partie", color: Theme.secondary)
                if let best = game.best {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: Format.hz(best)).font(Theme.mono(36, .semibold))
                        Text(verbatim: "Hz").foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Aucun moustique attrapé")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 8)
                }
                Text("Chaque bonne réponse fait monter le moustique dans les aigus.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LeaderboardCard(ranks: Array(store.mosquitoLeaderboard().prefix(5)), currentUserID: game.config.userID)
            Spacer()
            Text("Volume plafonné pendant le jeu pour protéger les oreilles.")
                .font(.system(size: 12))
                .foregroundStyle(Neon.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: Bocal

enum JarLook { case pending, playing, heard, choosable, caught, revealed, wrong }

private struct JarButton: View {
    let number: Int
    let look: JarLook
    var action: () -> Void
    @State private var hover = false
    @State private var shake: CGFloat = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                ZStack {
                    SoundWaves()
                        .stroke(Neon.pink.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .opacity(look == .playing ? 1 : 0)
                    JarShape()
                        .stroke(jarColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                        .frame(width: 120, height: 150)
                        .shadow(color: glowing ? jarColor.opacity(0.9) : .clear, radius: 5)
                    if look == .caught || look == .revealed {
                        MosquitoIcon()
                            .frame(width: 76, height: 46)
                            .offset(y: 18)
                            .neonGlow(Neon.pink, radius: 4)
                    }
                }
                .frame(width: 200, height: 150)
                Text(verbatim: "\(number)")
                    .font(Theme.mono(28, .semibold))
                    .foregroundStyle(numberColor)
                ZStack {
                    if let caption {
                        Text(caption)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(captionColor)
                    }
                }
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1.5, dash: look == .pending ? [6, 5] : []))
            )
            .shadow(color: look == .playing ? Neon.pink.opacity(0.2) : .clear, radius: 30)
            .shadow(color: look == .wrong ? Neon.red.opacity(0.35) : .clear, radius: 24)
            .opacity(look == .pending ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .modifier(Shake(amount: shake))
            .animation(.easeOut(duration: 0.15), value: look)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onChange(of: look) {
            if look == .wrong {
                withAnimation(.linear(duration: 0.45)) { shake += 1 }
            }
        }
        .accessibilityLabel(Text("Bocal \(number)"))
    }

    private var hot: Bool { (look == .choosable || look == .heard || look == .pending) && hover }
    private var glowing: Bool { look == .playing || look == .caught || look == .revealed || look == .wrong || hot }

    private var jarColor: Color {
        switch look {
        case .pending: return Neon.off
        case .playing, .revealed: return Neon.pink
        case .heard: return Neon.dim
        case .wrong: return Neon.red
        case .choosable: return hot ? Neon.pinkSoft : Theme.secondary
        case .caught: return Neon.mint
        }
    }

    private var borderColor: Color {
        switch look {
        case .pending: return Neon.dashed
        case .playing, .revealed: return Neon.pink
        case .heard: return Neon.heardBorder
        case .wrong: return Neon.red
        case .choosable: return hot ? Neon.pink : Neon.off
        case .caught: return Neon.mint
        }
    }

    private var background: Color {
        switch look {
        case .playing, .revealed: return Neon.pinkBg
        case .caught: return Neon.mintBg
        case .wrong: return Neon.redBg
        default: return Neon.card
        }
    }

    private var numberColor: Color {
        switch look {
        case .pending: return Neon.off
        case .playing, .revealed: return Neon.pinkSoft
        case .choosable: return hot ? Neon.pinkSoft : Theme.text
        case .caught: return Neon.mint
        case .heard: return Neon.dim
        case .wrong: return Neon.red
        }
    }

    private var caption: LocalizedStringKey? {
        switch look {
        case .caught: return "Attrapé !"
        case .revealed: return "Il était là"
        case .wrong: return "Raté"
        default: return nil
        }
    }

    private var captionColor: Color {
        switch look {
        case .caught: return Neon.mint
        case .revealed: return Neon.pinkSoft
        case .wrong: return Neon.red
        default: return Theme.muted
        }
    }
}

private struct LivesView: View {
    let lives: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            SectionLabel("Vies").padding(.trailing, 4)
            ForEach(0..<total, id: \.self) { i in
                LifeDot(alive: i < lives)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(lives) vies restantes"))
    }
}

/// Vie perdue : la pastille vire au rouge, se fait barrer d'une croix tracée, puis reste barrée.
private struct LifeDot: View {
    let alive: Bool
    @State private var strike: CGFloat = 0
    @State private var pop: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(alive ? Neon.pink : Neon.red.opacity(0.18))
                .shadow(color: alive ? Neon.pink : .clear, radius: 4)
            Circle().strokeBorder(alive ? .clear : Neon.red.opacity(0.6), lineWidth: 1.5)
            CrossShape()
                .trim(from: 0, to: strike)
                .stroke(Neon.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .shadow(color: Neon.red, radius: 3)
                .frame(width: 22, height: 22)
        }
        .frame(width: 16, height: 16)
        .scaleEffect(pop)
        .onAppear { strike = alive ? 0 : 1 }
        .onChange(of: alive) {
            if alive {
                strike = 0
            } else {
                pop = 1.6
                withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { pop = 1 }
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) { strike = 1 }
            }
        }
    }
}

/// Croix en deux traits, tracée d'un seul chemin pour l'animation `trim`.
private struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// Secousse horizontale du bocal raté.
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 6), y: 0))
    }
}

struct LeaderboardCard: View {
    let ranks: [MosquitoRank]
    let currentUserID: UUID?

    var body: some View {
        NeonCard {
            SectionLabel("Classement", color: Theme.secondary).padding(.bottom, 6)
            if ranks.isEmpty {
                Text("Pas encore de score. À toi de jouer !")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(Array(ranks.enumerated()), id: \.element.id) { index, rank in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(Theme.mono(14, .semibold))
                        .foregroundStyle(index == 0 ? Neon.yellow : Theme.secondary)
                        .frame(width: 20, alignment: .leading)
                    Text(verbatim: rank.user.name)
                        .font(.system(size: 14, weight: rank.user.id == currentUserID ? .bold : .medium))
                    Spacer()
                    Text(verbatim: Format.hz(rank.best))
                        .font(Theme.mono(14))
                        .foregroundStyle(Neon.pinkSoft)
                }
                .padding(.vertical, 8)
                if index < ranks.count - 1 {
                    Rectangle().fill(Neon.cardBorder).frame(height: 1)
                }
            }
        }
    }
}
