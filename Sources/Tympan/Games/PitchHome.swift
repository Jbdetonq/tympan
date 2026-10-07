import SwiftUI

/// Page d'accueil de « La juste note » : description, podium par niveau (sur une portée),
/// Jouer, réglages de la partie (le son dépend du niveau).
struct PitchHomeView: View {
    @Environment(DataStore.self) private var store
    @Binding var selection: UUID?
    var result: PitchResult?
    var onPlay: (PitchConfig) -> Void
    var onAddUser: () -> Void

    @AppStorage("pitchLevel") private var levelRaw = PitchLevel.easy.rawValue
    @State private var headphoneID: UUID?

    private var level: PitchLevel { PitchLevel(rawValue: levelRaw) ?? .easy }
    private var ranks: [PitchRank] { store.pitchLeaderboard(level: level) }
    private var shownResult: PitchResult? { result?.userID == selection ? result : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let r = shownResult {
                    banner(r)
                    HearingTipCard(tip: r.tip, color: Neon.cyanSoft)
                }
                GamePlayBar(selection: $selection, headphoneID: $headphoneID, color: Neon.cyan,
                            onPlay: play, onAddUser: onAddUser)
                podiumPanel
                settingsPanel
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Neon.bg)
        .onAppear {
            if let r = result { levelRaw = r.level.rawValue } else { openOnLastLevel() }
        }
        .onChange(of: selection) { openOnLastLevel() }
    }

    /// Le podium s'ouvre sur le dernier niveau joué par le joueur.
    private func openOnLastLevel() {
        guard let id = selection, let last = store.pitchGames(for: id).last else { return }
        levelRaw = last.level.rawValue
    }

    private func play() {
        guard let id = selection, store.user(id) != nil, let h = store.headphone(headphoneID) else { return }
        onPlay(PitchConfig(userID: id, headphone: h, level: level, timbre: level.timbre))
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TuningForkIcon()
                    .frame(width: 40, height: 40)
                    .neonGlow(Neon.cyan, radius: 4)
                Text("La juste note").font(.system(size: 30, weight: .semibold))
            }
            Text("Une note sonne, puis disparaît. Retrouve-la au curseur, rien qu'à l'oreille. Plus tu es proche, plus tu gagnes d'étoiles : trois étoiles à moins de 10 cents (un dixième de demi-ton). Une partie compte 10 manches.")
                .font(.system(size: 15))
                .foregroundStyle(Neon.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 680, alignment: .leading)
        }
    }

    // MARK: Bandeau de résultat

    private func title(_ r: PitchResult) -> LocalizedStringKey {
        if r.stars >= 25 { return "Superbe oreille !" }
        if r.stars >= 15 { return "Belle partie" }
        return "Partie terminée"
    }

    private func banner(_ r: PitchResult) -> some View {
        let color = r.isNewRecord ? Neon.mint : Neon.cyan
        let place = store.pitchLeaderboard(level: r.level).firstIndex { $0.user.id == r.userID }
        return GameResultBanner(color: color) {
            TuningForkIcon(color: color)
                .frame(width: 54, height: 54)
                .neonGlow(color, radius: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(r)).font(.system(size: 22, weight: .bold))
                HStack(spacing: 8) {
                    Image(systemName: "star.fill").foregroundStyle(Neon.yellow)
                    Text("\(r.stars) étoiles sur \(PitchGame.roundCount * 3)")
                    if let e = r.meanError {
                        Text(verbatim: "·").foregroundStyle(Theme.muted)
                        Text("écart moyen \(Int(e.rounded())) cents")
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(Neon.caption)
                if let b = r.meanBias, abs(b) >= 8 {
                    Text(b > 0
                         ? LocalizedStringKey("Tu vises plutôt un peu aigu (\(PitchView.signedCents(b)) en moyenne).")
                         : LocalizedStringKey("Tu vises plutôt un peu grave (\(PitchView.signedCents(b)) en moyenne)."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
                if r.isNewRecord, let place, place < 3 {
                    Text("Nouveau record en \(r.level.titleText), et te voilà sur le podium !")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Neon.mint)
                } else if r.isNewRecord {
                    Text("Nouveau record perso en \(r.level.titleText) !")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Neon.mint)
                } else if let prev = r.previousBest {
                    Text("Ton record : \(prev.stars) étoiles, \(Int(prev.meanError.rounded())) cents")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            Button("Rejouer") {
                levelRaw = r.level.rawValue
                play()
            }
            .buttonStyle(NeonButtonStyle(color: color))
        }
    }

    // MARK: Podium

    private var podiumPanel: some View {
        let highlight = shownResult.flatMap { $0.isNewRecord && $0.level == level ? $0.userID : nil }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionLabel("Meilleures oreilles", color: Neon.cyanSoft)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(PitchLevel.allCases) { l in
                        Button {
                            levelRaw = l.rawValue
                        } label: {
                            Text(l.title)
                                .font(.system(size: 13, weight: l == level ? .semibold : .regular))
                                .foregroundStyle(l == level ? Neon.cyanSoft : Theme.muted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(l == level ? Neon.cyanBg : .clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(l == level ? Neon.cyan : Neon.dashed))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            StaffPodium(ranks: Array(ranks.prefix(3)), highlightUserID: highlight)
            selectedLine
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Neon.stage, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Neon.stageBorder))
    }

    @ViewBuilder
    private var selectedLine: some View {
        if let id = selection, let user = store.user(id) {
            if let i = ranks.firstIndex(where: { $0.user.id == id }) {
                if i >= 3 {
                    Text("Record de \(user.name) en \(level.titleText) : \(ranks[i].record.stars) étoiles, \(Format.place(i)).")
                        .font(.system(size: 14))
                        .foregroundStyle(Neon.caption)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text("Pas encore de partie complète pour \(user.name) en \(level.titleText). À toi de jouer !")
                    .font(.system(size: 14))
                    .foregroundStyle(Neon.caption)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Réglages de la partie

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Niveau")
                HStack(spacing: 14) {
                    ForEach(PitchLevel.allCases) { l in levelCard(l) }
                }
            }
        }
    }

    private func levelRows(_ l: PitchLevel) -> [(LocalizedStringKey, LocalizedStringKey)] {
        switch l {
        case .easy:
            return [("Son", "voix"), ("Écoute", "3 s, réécoute 1 fois"), ("Curseur", "note et Hz affichés"), ("Étendue", "1 octave, graduée")]
        case .medium:
            return [("Son", "flûte"), ("Écoute", "2 s"), ("Curseur", "rien d'affiché"), ("Étendue", "1,5 octave")]
        case .hard:
            return [("Son", "piano"), ("Écoute", "1 s puis 3 s de silence"), ("Curseur", "rien d'affiché"), ("Étendue", "2 octaves")]
        }
    }

    private func levelCard(_ l: PitchLevel) -> some View {
        let on = l == level
        let rows = levelRows(l)
        return Button {
            levelRaw = l.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(on ? Neon.cyanSoft : Theme.text)
                    Spacer()
                    Circle()
                        .strokeBorder(on ? Neon.cyan : Neon.heardBorder, lineWidth: 2)
                        .background(Circle().fill(on ? Neon.cyan : .clear).padding(4))
                        .frame(width: 16, height: 16)
                }
                ForEach(rows.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Rectangle().fill(Neon.cardBorder).frame(height: 1)
                        HStack(alignment: .top) {
                            Text(rows[i].0).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(rows[i].1).foregroundStyle(Theme.text).multilineTextAlignment(.trailing)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(on ? Neon.cyanBg : Neon.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? Neon.cyan : Neon.heardBorder, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

}

/// Podium sur une portée : plus on est haut sur la portée, meilleur on est.
/// 2e à gauche, 1er au centre (note la plus haute), 3e à droite.
struct StaffPodium: View {
    let ranks: [PitchRank]
    var highlightUserID: UUID?

    /// Colonnes de gauche à droite : indices de classement.
    private static let order = [1, 0, 2]
    /// Hauteur de la tête de note sur la portée, par place.
    private static let noteY: [CGFloat] = [52, 97, 142]
    private static let stepHeights: [CGFloat] = [72, 50, 34]
    private static let lineYs: [CGFloat] = (0..<5).map { 37 + CGFloat($0) * 30 }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    ForEach(Self.lineYs, id: \.self) { y in
                        Rectangle()
                            .fill(Neon.cardBorder)
                            .frame(width: w, height: 1.5)
                            .position(x: w / 2, y: y)
                    }
                    ForEach(0..<3, id: \.self) { col in
                        let idx = Self.order[col]
                        let rank = idx < ranks.count ? ranks[idx] : nil
                        NoteGlyph(place: idx + 1, empty: rank == nil,
                                  highlighted: rank != nil && rank?.user.id == highlightUserID)
                            .position(x: w * (CGFloat(col) * 2 + 1) / 6, y: Self.noteY[idx] - NoteGlyph.headOffset)
                    }
                }
            }
            .frame(height: 190)
            HStack(alignment: .bottom, spacing: 22) {
                ForEach(0..<3, id: \.self) { col in
                    let idx = Self.order[col]
                    let rank = idx < ranks.count ? ranks[idx] : nil
                    VStack(spacing: 10) {
                        NoteLabel(rank: rank, highlighted: rank != nil && rank?.user.id == highlightUserID)
                        PodiumStep(place: idx + 1, height: Self.stepHeights[idx])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Note sur la portée (tête + hampe), dans un cadre 60 x 100.
private struct NoteGlyph: View {
    let place: Int
    let empty: Bool
    let highlighted: Bool
    /// Décalage vertical entre le centre du cadre et la tête de note.
    static let headOffset: CGFloat = 36

    @State private var pulse = false

    private var color: Color {
        if highlighted { return Neon.mint }
        if empty { return Neon.off }
        return place == 1 ? Neon.yellow : Neon.cyan
    }

    var body: some View {
        ZStack {
            if empty {
                Ellipse()
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 34, height: 24)
                    .rotationEffect(.degrees(-20))
                    .offset(y: Self.headOffset)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 70)
                    .offset(x: 15, y: 0)
                Ellipse()
                    .fill(color)
                    .frame(width: 34, height: 24)
                    .rotationEffect(.degrees(-20))
                    .offset(y: Self.headOffset)
            }
        }
        .frame(width: 60, height: 100)
        .neonGlow(empty ? .clear : color, radius: highlighted ? 6 : 3)
        .scaleEffect(highlighted && pulse ? 1.12 : 1)
        .animation(highlighted ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
        .onAppear { if highlighted { pulse = true } }
    }
}

/// Étiquette sous la note : prénom, étoiles, écart moyen.
private struct NoteLabel: View {
    let rank: PitchRank?
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 3) {
            if let rank {
                Text(verbatim: rank.user.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Neon.yellow)
                    Text(verbatim: "\(rank.record.stars)/30")
                        .font(Theme.mono(13))
                        .foregroundStyle(highlighted ? Neon.mint : Neon.cyanSoft)
                }
                Text("\(Int(rank.record.meanError.rounded())) cents")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Place libre")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 96)
        .background(Neon.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(highlighted ? Neon.mint : (rank == nil ? Neon.dashed : Neon.heardBorder), lineWidth: 1.2))
    }
}
