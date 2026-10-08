import SwiftUI

/// Page d'accueil de la chasse au moustique : description, résultat de la dernière partie,
/// joueur, casque et Jouer, puis podium en bocaux.
struct MosquitoHomeView: View {
    @Environment(DataStore.self) private var store
    /// Joueur = utilisateur sélectionné dans la barre latérale.
    @Binding var selection: UUID?
    /// Partie qui vient de se terminer, nil à l'arrivée depuis le menu.
    var result: MosquitoResult?
    var onPlay: (MosquitoConfig) -> Void
    var onAddUser: () -> Void

    @State private var headphoneID: UUID?

    private var ranks: [MosquitoRank] { store.mosquitoLeaderboard() }
    /// Le bandeau ne concerne que le joueur qui vient de jouer.
    private var shownResult: MosquitoResult? { result?.userID == selection ? result : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let r = shownResult {
                    banner(r)
                    HearingTipCard(tip: r.tip, color: Neon.pinkSoft)
                }
                GamePlayBar(selection: $selection, headphoneID: $headphoneID, color: Neon.pink,
                            onPlay: play, onAddUser: onAddUser)
                podiumPanel
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Neon.bg)
    }

    /// Lance une partie avec le joueur et le casque choisis.
    private func play() {
        guard let id = selection, store.user(id) != nil, let h = store.headphone(headphoneID) else { return }
        onPlay(MosquitoConfig(userID: id, headphone: h))
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MosquitoIcon()
                    .frame(width: 64, height: 40)
                    .neonGlow(Neon.pink, radius: 4)
                Text("Chasse au moustique").font(.system(size: 30, weight: .semibold))
            }
            Text("Trois bocaux, un seul cache le moustique. Écoute les trois, puis choisis le bon. À chaque bonne réponse, il file vers les aigus. Trois erreurs et la partie s'arrête. Plus tu l'entends haut, plus ton bocal se remplit !")
                .font(.system(size: 15))
                .foregroundStyle(Neon.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 680, alignment: .leading)
        }
    }

    // MARK: Bandeau de résultat

    /// Fin de partie : record atteint, âge des oreilles (pour s'amuser), place au podium. Menthe si nouveau record.
    private func banner(_ r: MosquitoResult) -> some View {
        let color = r.best == nil ? Neon.pink : (r.isNewRecord ? Neon.mint : Neon.pink)
        let place = ranks.firstIndex { $0.user.id == r.userID }
        return GameResultBanner(color: color) {
            MosquitoIcon(color: color)
                .frame(width: 84, height: 50)
                .neonGlow(color, radius: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.won ? LocalizedStringKey("Incroyable, tu l'as suivi jusqu'au bout !") : LocalizedStringKey("Partie terminée"))
                    .font(.system(size: 22, weight: .bold))
                if let best = r.best {
                    Text("Moustique attrapé jusqu'à \(Format.hz(best)) Hz")
                        .font(.system(size: 16))
                        .foregroundStyle(Neon.caption)
                    Text(HearingTips.earAge(for: best))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Neon.pinkSoft)
                    Text("Estimation pour s'amuser, elle dépend beaucoup du casque. Ce n'est pas un test médical.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if r.isNewRecord, let place, place < 3 {
                        Text("Nouveau record, et te voilà sur le podium !")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Neon.mint)
                    } else if r.isNewRecord {
                        Text("Nouveau record perso !")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Neon.mint)
                    } else if let prev = r.previousBest {
                        Text("Ton record : \(Format.hz(prev)) Hz")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Aucun moustique attrapé cette fois. Retente ta chance !")
                        .font(.system(size: 16))
                        .foregroundStyle(Neon.caption)
                }
            }
            Spacer(minLength: 0)
            Button("Rejouer") { play() }
                .buttonStyle(NeonButtonStyle(color: color))
        }
    }

    // MARK: Podium

    private var podiumPanel: some View {
        let top = Array(ranks.prefix(3))
        let highlight = shownResult.flatMap { $0.isNewRecord ? $0.userID : nil }
        return VStack(alignment: .leading, spacing: 18) {
            SectionLabel("Meilleurs chasseurs", color: Neon.pinkSoft)
            JarPodium(ranks: top, highlightUserID: highlight)
                .frame(maxWidth: .infinity)
            selectedLine
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Neon.stage, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Neon.stageBorder))
    }

    /// Record du joueur sélectionné quand il n'est pas sur le podium.
    @ViewBuilder
    private var selectedLine: some View {
        if let id = selection, let user = store.user(id) {
            if let i = ranks.firstIndex(where: { $0.user.id == id }) {
                if i >= 3 {
                    Text("Record de \(user.name) : \(Format.hz(ranks[i].best)) Hz, \(Format.place(i)).")
                        .font(.system(size: 14))
                        .foregroundStyle(Neon.caption)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text("Pas encore de moustique attrapé pour \(user.name). À toi de jouer !")
                    .font(.system(size: 14))
                    .foregroundStyle(Neon.caption)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Podium en bocaux : 2e à gauche, 1er au centre, 3e à droite.
/// Le bocal du 1er déborde de moustiques, le 2e un peu moins, le 3e en a trois.
struct JarPodium: View {
    let ranks: [MosquitoRank]
    var highlightUserID: UUID?

    /// Moustiques, largeur du bocal et hauteur de marche, du 1er au 3e.
    private static let counts = [12, 7, 3]
    private static let jarWidths: [CGFloat] = [150, 128, 118]
    private static let stepHeights: [CGFloat] = [96, 66, 44]

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            slot(1)
            slot(0)
            slot(2)
        }
    }

    /// Une place du podium (index 0 = 1er) ; vide en pointillés s'il n'y a pas assez de joueurs.
    private func slot(_ index: Int) -> some View {
        let rank = index < ranks.count ? ranks[index] : nil
        let highlighted = rank != nil && rank?.user.id == highlightUserID
        let w = Self.jarWidths[index]
        return VStack(spacing: 10) {
            if highlighted {
                Text("Nouveau !")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Neon.mint)
            }
            PodiumJar(count: rank == nil ? 0 : Self.counts[index], empty: rank == nil, highlighted: highlighted)
                .frame(width: w, height: w * 1.25)
            JarLabel(rank: rank, place: index + 1, highlighted: highlighted)
            PodiumStep(place: index + 1, height: Self.stepHeights[index])
                .frame(width: w + 30)
        }
        .frame(width: w + 30)
    }
}

/// Étiquette du bocal : prénom et fréquence record.
private struct JarLabel: View {
    let rank: MosquitoRank?
    let place: Int
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let rank {
                Text(verbatim: rank.user.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: "\(Format.hz(rank.best)) Hz")
                    .font(Theme.mono(13))
                    .foregroundStyle(highlighted ? Neon.mint : Neon.pinkSoft)
            } else {
                Text("Place libre")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Text(verbatim: " ").font(Theme.mono(13))
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

/// Bocal du podium, avec ses moustiques qui volettent.
struct PodiumJar: View {
    let count: Int
    var empty = false
    var highlighted = false

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let v = ViewBox(rect, width: 120, height: 150)
            let color = highlighted ? Neon.mint : (empty ? Neon.off : Theme.secondary)
            ZStack {
                JarShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineJoin: .round, dash: empty ? [6, 5] : []))
                    .shadow(color: highlighted ? Neon.mint.opacity(0.8) : .clear, radius: 6)
                if count > 0 {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<count, id: \.self) { k in
                                MosquitoIcon()
                                    .frame(width: 30 * v.s, height: 18 * v.s)
                                    .scaleEffect(x: k % 2 == 0 ? 1 : -1, y: 1)
                                    .neonGlow(Neon.pink, radius: 2)
                                    .position(Self.position(k, t: t, in: v))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Position d'un moustique dans le corps du bocal (viewBox 120 x 150), avec un léger vol.
    static func position(_ k: Int, t: Double, in v: ViewBox) -> CGPoint {
        let fk = Double(k)
        // Places de base réparties sans motif visible (pas irrationnels), puis petit vol sinusoïdal.
        let bx = 30 + (fk * 0.618 + 0.13).truncatingRemainder(dividingBy: 1) * 60
        let by = 62 + (fk * 0.382 + 0.27).truncatingRemainder(dividingBy: 1) * 62
        let dx = sin(t * (1.3 + fk * 0.17) + fk) * 5
        let dy = cos(t * (1.1 + fk * 0.23) + fk * 2) * 4
        return v.p(CGFloat(bx + dx), CGFloat(by + dy))
    }
}
