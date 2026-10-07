import AppKit
import SwiftUI

extension PitchLevel {
    var title: LocalizedStringKey {
        switch self {
        case .easy: return "Facile"
        case .medium: return "Moyen"
        case .hard: return "Difficile"
        }
    }
}

extension Timbre {
    var title: LocalizedStringKey {
        switch self {
        case .flute: return "Flûte"
        case .piano: return "Piano"
        case .voice: return "Voix"
        }
    }
}

extension TimbreChoice {
    var title: LocalizedStringKey {
        switch self {
        case .flute: return "Flûte"
        case .piano: return "Piano"
        case .voice: return "Voix"
        case .random: return "Au hasard"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .flute: return "douce et stable"
        case .piano: return "attaque, puis s'éteint"
        case .voice: return "un « ah » chanté"
        case .random: return "change à chaque manche"
        }
    }
}

// MARK: Écran de jeu

struct PitchView: View {
    @Environment(DataStore.self) private var store
    var game: PitchGame
    let playerName: String
    /// Retour à la page d'accueil du jeu, avec le résultat (nil si la partie a été quittée).
    var onClose: (PitchResult?) -> Void

    @State private var keyMonitor: Any?
    @State private var previousBest: PitchRecord?
    @State private var saved = false
    @State private var closed = false
    @State private var confirmQuit = false

    var body: some View {
        VStack(spacing: 20) {
            header
            HStack(alignment: .top, spacing: 24) {
                stage
                aside.frame(width: 300)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Neon.bg)
        .onAppear {
            previousBest = store.pitchBest(for: game.config.userID, level: game.config.level)
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
        .confirmationDialog("Quitter la partie ? Une partie incomplète n'est pas enregistrée.",
                            isPresented: $confirmQuit) {
            Button("Quitter", role: .destructive) {
                game.cancel()
                close(nil)
            }
        }
    }

    /// Fin de partie : on enregistre, puis retour à la page d'accueil avec le bandeau de résultat.
    private func finish() {
        save()
        let result = PitchResult(userID: game.config.userID, level: game.config.level,
                                 stars: game.totalStars, meanError: game.meanError, meanBias: game.meanBias,
                                 previousBest: previousBest, isNewRecord: isNewRecord)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            close(result)
        }
    }

    private func close(_ result: PitchResult?) {
        guard !closed else { return }
        closed = true
        onClose(result)
    }

    /// Seule une partie complète (10 manches) est enregistrée.
    private func save() {
        guard !saved, let record = game.record else { return }
        store.addPitchGame(record)
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

    // Flèches = affiner, Espace = rejouer ma note, Entrée = valider / suivante,
    // R = réécouter le modèle, C = comparer.
    private func installKeyMonitor() {
        let g = game
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode
            let shift = event.modifierFlags.contains(.shift)
            let isRepeat = event.isARepeat
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let handled: Bool = MainActor.assumeIsolated { () -> Bool in
                if code == 123 || code == 124 {
                    guard g.phase == .searching else { return false }
                    let step: Double = shift ? 100 : 5
                    g.nudge(cents: code == 123 ? -step : step)
                    return true
                }
                if isRepeat { return false }
                switch code {
                case 49:
                    guard g.phase == .searching else { return false }
                    g.playMine()
                    return true
                case 36, 76:
                    if g.phase == .searching { g.validate(); return true }
                    if g.phase == .feedback { g.next(); return true }
                    return false
                default:
                    break
                }
                if chars == "r" && g.phase == .searching {
                    g.replayModel()
                    return true
                }
                if chars == "c" && g.phase == .feedback {
                    g.compare()
                    return true
                }
                return false
            }
            return handled ? nil : event
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
            TuningForkIcon()
                .frame(width: 36, height: 36)
                .neonGlow(Neon.cyan, radius: 4)
                .padding(.leading, 6)
            Text("La juste note").font(.system(size: 22, weight: .semibold))
            PitchChip(text: game.config.level.title, on: true)
            PitchChip(text: game.timbre.title, on: false)
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
        VStack(alignment: .leading, spacing: 22) {
            if let error = game.errorMessage {
                InfoBanner(verbatim: error)
                Spacer()
            } else if game.phase == .over {
                endScreen
            } else {
                roundHeader
                AudioHoldBanner(lock: game.volumeLock)
                ribbonPanel
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
                SectionLabel("Manche \(game.roundNumber) sur \(PitchGame.roundCount)", color: Neon.cyanSoft)
                Text(title).font(.system(size: 30, weight: .semibold))
                Text(subtitle).font(.system(size: 16)).foregroundStyle(Neon.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            PhaseSteps(level: game.config.level, phase: game.phase)
        }
    }

    private var title: LocalizedStringKey {
        if game.outputChanged { return "Le casque a été débranché ?" }
        switch game.phase {
        case .starting: return "Prépare tes oreilles…"
        case .listening: return "Écoute bien la note"
        case .silence: return "Garde-la en tête…"
        case .searching: return "À toi : retrouve la note"
        case .feedback:
            guard let r = game.results.last else { return "" }
            let e = abs(r.cents)
            if e < 10 { return "Pile dessus !" }
            if e < 25 { return "Très proche" }
            if e < 50 { return "Presque" }
            if e < 100 { return r.cents > 0 ? "Un peu trop aigu" : "Un peu trop grave" }
            return r.cents > 0 ? "Trop aigu" : "Trop grave"
        case .over: return ""
        }
    }

    private var subtitle: LocalizedStringKey {
        if game.outputChanged { return "Rebranche-le, puis appuie sur Reprendre." }
        switch game.phase {
        case .starting: return "Une note va sonner. Retiens sa hauteur."
        case .listening: return "Retiens sa hauteur, tu vas devoir la retrouver."
        case .silence: return "Quelques secondes de silence avant de chercher."
        case .searching:
            return game.config.level.showsNote
                ? "Glisse le curseur, le son suit ta main. Valide quand c'est la même note."
                : "Glisse le curseur, le son suit ta main. Rien n'est affiché : fie-toi à ton oreille."
        case .feedback: return "Écoute les deux pour comparer, puis passe à la suite."
        case .over: return ""
        }
    }

    private var ribbonPanel: some View {
        VStack(spacing: 10) {
            ribbonTop.frame(height: 56)
            PitchRibbon(window: game.window,
                        cursor: game.phase == .feedback ? (game.results.last?.answer ?? game.cursor) : game.cursor,
                        target: game.phase == .feedback ? game.results.last?.target : nil,
                        showsLabels: game.config.level.showsNote,
                        interactive: game.phase == .searching,
                        sounding: game.sounding,
                        cursorLabel: game.phase == .feedback ? game.results.last.map { Self.signedCents($0.cents) } : nil,
                        highlight: game.comparePart,
                        onDrag: { game.setCursor($0) },
                        onEnd: { game.endDrag() })
                .padding(.horizontal, 20)
            ribbonBottom.frame(minHeight: 40)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Neon.well, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Neon.stageBorder))
    }

    @ViewBuilder
    private var ribbonTop: some View {
        switch game.phase {
        case .searching:
            if game.config.level.showsNote {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: PitchMath.noteName(game.cursor))
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Neon.cyan)
                    .shadow(color: Neon.cyan.opacity(0.45), radius: 10)
                Text(verbatim: "\(Self.hz(game.cursor)) Hz")
                    .font(Theme.mono(20))
                    .foregroundStyle(Theme.muted)
            }
            }
        case .feedback:
            if let r = game.results.last {
                HStack(spacing: 28) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Neon.yellow)
                        Text("La note").foregroundStyle(Theme.secondary)
                        Text(verbatim: "\(PitchMath.noteName(r.target)) · \(Self.hz(r.target)) Hz")
                            .font(Theme.mono(15, .semibold))
                            .foregroundStyle(Neon.yellow)
                    }
                    HStack(spacing: 8) {
                        Circle().strokeBorder(Neon.cyan, lineWidth: 3).frame(width: 13, height: 13)
                        Text("Ton choix").foregroundStyle(Theme.secondary)
                        Text(verbatim: "\(Self.hz(r.answer)) Hz")
                            .font(Theme.mono(15, .semibold))
                            .foregroundStyle(Neon.cyan)
                    }
                }
            }
        case .listening:
            Label("Écoute", systemImage: "speaker.wave.2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Neon.cyanSoft)
        case .silence:
            Label("Silence", systemImage: "speaker.slash")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.muted)
        default:
            Color.clear
        }
    }

    @ViewBuilder
    private var ribbonBottom: some View {
        switch game.phase {
        case .searching:
            Text("Flèches ← → pour affiner · Maj + flèche : un demi-ton · Espace : rejouer ta note")
                .font(.system(size: 13))
                .foregroundStyle(Neon.footnote)
        case .feedback:
            if let r = game.results.last {
                VStack(spacing: 8) {
                    StarsView(filled: r.stars, size: 28, spacing: 6)
                    Text(Self.describe(r.cents))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
        default:
            Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            RoundDots(results: game.results,
                      current: game.phase == .feedback ? nil : game.results.count)
            Spacer()
            if game.outputChanged {
                Button("Reprendre") { game.resume() }
                    .buttonStyle(NeonButtonStyle(color: Neon.cyan))
            } else if game.phase == .searching {
                if game.config.level.modelReplays > 0 {
                    Button {
                        game.replayModel()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Réécouter le modèle")
                            Text("R · \(game.replaysLeft) fois")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(game.replaysLeft == 0)
                    .opacity(game.replaysLeft == 0 ? 0.4 : 1)
                }
                Button {
                    game.validate()
                } label: {
                    HStack(spacing: 8) {
                        Text("Valider")
                        Text("Entrée").font(Theme.mono(12)).opacity(0.7)
                    }
                }
                .buttonStyle(NeonButtonStyle(color: Neon.cyan))
            } else if game.phase == .feedback {
                Button {
                    game.compare()
                } label: {
                    HStack(spacing: 8) {
                        Text("Comparer les deux")
                        Text(verbatim: "C").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(game.comparePart != nil)
                Button {
                    game.next()
                } label: {
                    HStack(spacing: 8) {
                        Text(game.isComplete ? LocalizedStringKey("Voir le résultat") : LocalizedStringKey("Manche suivante"))
                        Text("Entrée").font(Theme.mono(12)).opacity(0.7)
                    }
                }
                .buttonStyle(NeonButtonStyle(color: Neon.cyan))
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: Fin de partie

    private var isNewRecord: Bool {
        guard let r = game.record else { return false }
        return previousBest.map { r.beats($0) } ?? true
    }

    private var endTitle: LocalizedStringKey {
        let s = game.totalStars
        if s >= 25 { return "Superbe oreille !" }
        if s >= 15 { return "Belle partie" }
        return "Partie terminée"
    }

    /// Écran bref avant le retour à la page d'accueil (le détail s'y affiche en bandeau).
    private var endScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            TuningForkIcon(color: game.totalStars >= 25 ? Neon.mint : Neon.cyan)
                .frame(width: 120, height: 120)
                .neonGlow(game.totalStars >= 25 ? Neon.mint : Neon.cyan, radius: 10)
            Text(endTitle)
                .font(.system(size: 40, weight: .bold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "star.fill").foregroundStyle(Neon.yellow)
                Text("\(game.totalStars) étoiles sur \(PitchGame.roundCount * 3)")
            }
            .font(.system(size: 22, weight: .semibold))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Colonne de droite

    private var aside: some View {
        VStack(spacing: 16) {
            NeonCard {
                SectionLabel("Partie en cours", color: Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(game.totalStars)").font(Theme.mono(36, .semibold))
                    if game.results.isEmpty {
                        Text("étoiles").foregroundStyle(Theme.muted)
                    } else {
                        Text("étoiles sur \(game.results.count * 3)").foregroundStyle(Theme.muted)
                    }
                }
                Rectangle().fill(Neon.cardBorder).frame(height: 1).padding(.vertical, 4)
                HStack {
                    Text("Écart moyen").foregroundStyle(Neon.caption)
                    Spacer()
                    if let e = game.meanError {
                        Text(verbatim: "\(Int(e.rounded())) cents").font(Theme.mono(14))
                    } else {
                        Text("pas encore").foregroundStyle(Theme.muted)
                    }
                }
                .font(.system(size: 14))
                Rectangle().fill(Neon.cardBorder).frame(height: 1).padding(.vertical, 4)
                StarScaleRow(stars: 3, text: "moins de 10 cents")
                StarScaleRow(stars: 2, text: "moins de 25 cents")
                StarScaleRow(stars: 1, text: "moins de 50 cents")
                Text("100 cents = un demi-ton, quelle que soit la hauteur.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            PitchLeaderboardCard(level: game.config.level,
                                 ranks: Array(store.pitchLeaderboard(level: game.config.level).prefix(5)),
                                 currentUserID: game.config.userID)
            Spacer()
            Text("Volume du casque verrouillé pendant la partie. Niveau modéré et fixe.")
                .font(.system(size: 12))
                .foregroundStyle(Neon.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Formats

    static func hz(_ midi: Double) -> String {
        Format.hz(Int(PitchMath.frequency(midi).rounded()))
    }

    static func signedCents(_ c: Double) -> String {
        let v = Int(c.rounded())
        return v > 0 ? "+\(v) cents" : "\(v) cents"
    }

    static func describe(_ cents: Double) -> LocalizedStringKey {
        let e = abs(cents)
        let up = cents > 0
        if e < 1 { return "Exactement la même note" }
        if e < 100 {
            let v = Int(e.rounded())
            return up ? "\(v) cents au-dessus (100 cents = un demi-ton)" : "\(v) cents en dessous (100 cents = un demi-ton)"
        }
        let st = Format.decimal(e / 100, trim: false)
        return up ? "\(st) demi-tons au-dessus" : "\(st) demi-tons en dessous"
    }
}

extension PitchLevel {
    /// Pour les phrases où le niveau est inséré dans un texte.
    var titleText: String {
        switch self {
        case .easy: return String(localized: "Facile")
        case .medium: return String(localized: "Moyen")
        case .hard: return String(localized: "Difficile")
        }
    }
}

// MARK: Curseur de hauteur

/// Ruban horizontal : échelle en demi-tons (logarithmique en Hz), comme un clavier.
struct PitchRibbon: View {
    let window: ClosedRange<Double>
    let cursor: Double
    var target: Double?
    var showsLabels: Bool
    var interactive: Bool
    var sounding: Bool
    var cursorLabel: String?
    var highlight: Int?
    var onDrag: (Double) -> Void
    var onEnd: () -> Void

    let pad: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in onDrag(value(at: v.location.x, width: geo.size.width)) }
                    .onEnded { _ in onEnd() }
            )
            .allowsHitTesting(interactive)
        }
        .frame(height: 150)
        .opacity(interactive || target != nil ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel(Text("Curseur de hauteur"))
    }

    private var span: Double { max(1, window.upperBound - window.lowerBound) }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let w = max(1, width - 2 * pad)
        let frac = min(max(Double((x - pad) / w), 0), 1)
        return window.lowerBound + frac * span
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width - 2 * pad
        let low = window.lowerBound
        let sp = span
        func x(_ m: Double) -> CGFloat { pad + CGFloat((m - low) / sp) * w }
        func line(_ x: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x, y: y1))
            p.addLine(to: CGPoint(x: x, y: y2))
            return p
        }

        // Rail
        let track = Path(roundedRect: CGRect(x: pad, y: 70, width: w, height: 10), cornerRadius: 5)
        ctx.fill(track, with: .color(Neon.track))
        ctx.stroke(track, with: .color(Neon.heardBorder), lineWidth: 1)

        // Graduations : une par demi-ton, touches noires plus courtes, noms en Facile.
        var n = Int(low.rounded(.up))
        while Double(n) <= window.upperBound {
            let xx = x(Double(n))
            let black = PitchMath.black(n)
            if showsLabels {
                ctx.stroke(line(xx, black ? 64 : 58, black ? 86 : 92),
                           with: .color(black ? Neon.blackKey : Neon.off), lineWidth: 1.5)
                if !black {
                    ctx.draw(Text(verbatim: PitchMath.noteName(Double(n), spaced: false))
                                .font(.system(size: 13))
                                .foregroundStyle(Neon.footnote),
                             at: CGPoint(x: xx, y: 116), anchor: .center)
                }
            } else {
                ctx.stroke(line(xx, 64, 86), with: .color(Neon.heardBorder), lineWidth: 1.5)
            }
            n += 1
        }

        // La note (révélée après validation)
        if let target {
            let tx = x(target)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: Neon.yellow.opacity(0.8), radius: highlight == 0 ? 10 : 5))
                l.stroke(line(tx, 44, 104), with: .color(Neon.yellow),
                         style: StrokeStyle(lineWidth: 2.5, dash: [4, 4]))
                var tri = Path()
                tri.move(to: CGPoint(x: tx - 9, y: 34))
                tri.addLine(to: CGPoint(x: tx + 9, y: 34))
                tri.addLine(to: CGPoint(x: tx, y: 44))
                tri.closeSubpath()
                l.fill(tri, with: .color(Neon.yellow))
            }
        }

        // Curseur
        let cx = x(cursor)
        let col = Neon.cyan
        if sounding && interactive {
            for (i, r) in [CGFloat(20), 34].enumerated() {
                var arc = Path()
                arc.move(to: CGPoint(x: cx - r, y: 50))
                arc.addQuadCurve(to: CGPoint(x: cx + r, y: 50), control: CGPoint(x: cx, y: 50 - r * 0.9))
                ctx.stroke(arc, with: .color(col.opacity(i == 0 ? 0.5 : 0.3)), lineWidth: 2)
            }
        }
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: col.opacity(0.8), radius: highlight == 1 ? 12 : 7))
            l.stroke(line(cx, 52, 98), with: .color(col), lineWidth: 3)
            let knob = Path(ellipseIn: CGRect(x: cx - 14, y: 61, width: 28, height: 28))
            l.fill(knob, with: .color(Neon.stage))
            l.stroke(knob, with: .color(col), lineWidth: 3)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 4, y: 71, width: 8, height: 8)), with: .color(col))

        if let cursorLabel {
            let lx = min(max(cx, pad + 40), size.width - pad - 40)
            ctx.draw(Text(verbatim: cursorLabel)
                        .font(Theme.mono(14, .semibold))
                        .foregroundStyle(col),
                     at: CGPoint(x: lx, y: 20), anchor: .center)
        }
    }
}

// MARK: Petits éléments

private struct PitchChip: View {
    let text: LocalizedStringKey
    let on: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Neon.cyanSoft : Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(on ? Neon.cyan : Neon.dashed))
    }
}

struct StarsView: View {
    let filled: Int
    var size: CGFloat = 12
    var spacing: CGFloat = 1

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i < filled ? Neon.yellow : Neon.off)
                    .shadow(color: i < filled ? Neon.yellow.opacity(0.6) : .clear, radius: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(filled) étoiles sur 3"))
    }
}

private struct StarScaleRow: View {
    let stars: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            StarsView(filled: stars, size: 10)
            Text(text).font(.system(size: 13)).foregroundStyle(Neon.caption)
        }
    }
}

private struct RoundDots: View {
    let results: [PitchRound]
    /// Manche en cours (index), nil pendant le résultat.
    let current: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<PitchGame.roundCount, id: \.self) { i in
                VStack(spacing: 6) {
                    if i < results.count {
                        StarsView(filled: results[i].stars, size: 7, spacing: 0)
                    } else {
                        Color.clear.frame(width: 1, height: 9)
                    }
                    Capsule()
                        .fill(color(i))
                        .frame(width: 22, height: 4)
                        .shadow(color: i == current ? Neon.cyan : .clear, radius: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(results.count) manches jouées sur \(PitchGame.roundCount)"))
    }

    private func color(_ i: Int) -> Color {
        if i < results.count { return Neon.cyan.opacity(0.7) }
        if i == current { return Neon.cyan }
        return Neon.heardBorder
    }
}

private struct PhaseSteps: View {
    let level: PitchLevel
    let phase: PitchGame.Phase

    private var steps: [(LocalizedStringKey, String?)] {
        var s: [(LocalizedStringKey, String?)] = [("Écoute", "\(Int(level.listenDuration)) s")]
        if level.silence > 0 { s.append(("Silence", "\(Int(level.silence)) s")) }
        s.append(("Cherche", nil))
        return s
    }

    private var activeIndex: Int {
        switch phase {
        case .starting: return -1
        case .listening: return 0
        case .silence: return 1
        case .searching: return steps.count - 1
        case .feedback, .over: return steps.count
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 6) {
                    Text(step.0)
                    if let d = step.1 {
                        Text(verbatim: d).font(Theme.mono(12)).opacity(0.8)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(i == activeIndex ? Neon.cyanSoft : (i < activeIndex ? Theme.muted : Neon.dim))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(i == activeIndex ? Neon.cyan.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(i == activeIndex ? Neon.cyan : (i < activeIndex ? Neon.dashed : Neon.heardBorder)))
                if i < steps.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Neon.off)
                }
            }
        }
    }
}

struct PitchLeaderboardCard: View {
    let level: PitchLevel
    let ranks: [PitchRank]
    let currentUserID: UUID?

    var body: some View {
        NeonCard {
            HStack(spacing: 6) {
                SectionLabel("Classement", color: Theme.secondary)
                SectionLabel(level.title, color: Neon.cyanSoft)
            }
            .padding(.bottom, 6)
            if ranks.isEmpty {
                Text("Pas encore de partie complète. À toi de jouer !")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text(verbatim: "\(rank.record.stars)/30")
                        .font(Theme.mono(14))
                        .foregroundStyle(Neon.cyanSoft)
                }
                .padding(.vertical, 8)
                if index < ranks.count - 1 {
                    Rectangle().fill(Neon.cardBorder).frame(height: 1)
                }
            }
        }
    }
}
