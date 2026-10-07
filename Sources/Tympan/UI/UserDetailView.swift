import Charts
import SwiftUI

struct UserDetailView: View {
    @Environment(DataStore.self) private var store
    let user: UserProfile
    /// Ouvre un nouveau test, avec éventuellement un format suggéré.
    var onNewTest: (TestLength?) -> Void
    /// Ouvre la page d'accueil d'un jeu.
    var onOpenGame: (AppPage) -> Void = { _ in }
    /// Ouvre la page « Lire un audiogramme ».
    var onReadingGuide: () -> Void = {}

    @State private var selectedSessionID: UUID?
    @State private var evoFrequency = 4000
    @State private var evoEar: Ear = .right

    private var displayed: TestSession? {
        user.sessions.first { $0.id == selectedSessionID } ?? user.sortedSessions.first
    }

    /// Référence tracée seulement si elle est comparable à la session affichée.
    private var comparableReference: TestSession? {
        guard let s = displayed, let r = user.reference, r.id != s.id, r.headphoneID == s.headphoneID else { return nil }
        return r
    }

    private var degradations: [Analysis.Degradation] {
        guard let s = displayed, let r = user.reference else { return [] }
        return Analysis.degradations(latest: s, reference: r)
    }

    var body: some View {
        ScrollView {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ForEach(degradations) { d in
                DegradationBanner(degradation: d, referenceDate: user.reference?.date) {
                    onNewTest(.standard)
                }
            }
            if let s = displayed, s.noisy {
                InfoBanner(text: "Session faite dans un environnement bruyant : exclue des comparaisons.")
            }
            if user.sessions.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 20) {
                    audiogramPanel
                    VStack(spacing: 20) {
                        EvolutionPanel(user: user, headphoneID: displayed?.headphoneID,
                                       frequency: $evoFrequency, ear: $evoEar)
                        SessionsPanel(user: user, selectedID: displayed?.id) { selectedSessionID = $0 }
                    }
                    .frame(width: 300)
                }
            }
            gamesPanel
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Jeux

    private var gamesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Jeux", color: Theme.secondary)
            HStack(alignment: .top, spacing: 20) {
                MosquitoScoreCard(user: user) { onOpenGame(.mosquito) }
                PitchScoreCard(user: user) { onOpenGame(.pitch) }
            }
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: user.name).font(.system(size: 28, weight: .semibold))
                HStack(spacing: 6) {
                    Text("Né(e) en \(String(user.birthYear))") + Text(verbatim: " · ") + Text("\(user.sessions.count) session(s)")
                    if let h = store.headphone(displayed?.headphoneID) {
                        Text("· \(h.name) · vol \(Int(h.volume * 100)) %")
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            }
            Spacer()
            if let s = displayed {
                Button("Exporter PDF") {
                    ReportExporter.export(user: user, session: s, reference: comparableReference,
                                          headphone: store.headphone(s.headphoneID))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button("Nouveau test") { onNewTest(nil) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var audiogramPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let s = displayed {
                        SectionLabel("Audiogramme · \(Format.long.string(from: s.date))", color: Theme.secondary)
                    }
                    Spacer()
                    AudiogramLegend(showReference: comparableReference != nil)
                }
                AudiogramChart(session: displayed, reference: comparableReference)
                    .frame(minHeight: 280)
                HStack {
                    Text("dB relatifs à l'app, valables pour ce profil casque")
                    Spacer()
                    Text(verbatim: "Hz")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                if let s = displayed {
                    ResultSummaryView(lines: Analysis.summary(session: s, reference: user.reference),
                                      onHelp: onReadingGuide)
                    SessionNoteEditor(userID: user.id, session: s)
                        .id(s.id)
                }
            }
        }
    }

    private var emptyState: some View {
        Panel(padding: 40) {
            VStack(spacing: 14) {
                Image(systemName: "ear")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent)
                Text("Pas encore de test").font(.system(size: 20, weight: .semibold))
                Text("Branche ton casque, installe-toi au calme et lance un premier test (environ 7 minutes).")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button("Lancer le premier test") { onNewTest(.standard) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct DegradationBanner: View {
    let degradation: Analysis.Degradation
    let referenceDate: Date?
    var onVerify: () -> Void

    private var title: String {
        switch (degradation.confirmed, degradation.ear) {
        case (true, .right): return String(localized: "Baisse à signaler, oreille droite.") + " "
        case (true, .left): return String(localized: "Baisse à signaler, oreille gauche.") + " "
        case (false, .right): return String(localized: "Écart à vérifier, oreille droite.") + " "
        case (false, .left): return String(localized: "Écart à vérifier, oreille gauche.") + " "
        }
    }

    private var detail: String {
        let parts = degradation.items.map { item -> String in
            let f = Analysis.frequencyLabel(item.frequency)
            return item.noResponse ? String(localized: "\(f)Hz rien entendu") : "\(f)Hz +\(item.delta) dB"
        }
        let list = parts.joined(separator: ", ")
        var text = referenceDate.map {
            String(localized: "\(list) par rapport à la référence (\(Format.long.string(from: $0))).")
        } ?? "\(list)."
        if degradation.confirmed {
            text += " " + String(localized: "Tympan ne pose pas de diagnostic : montre ce résultat à ton médecin ou à un ORL.")
        }
        return text
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.accent)
            (Text(verbatim: title)
                .foregroundColor(Theme.accentSoft).bold()
             + Text(verbatim: detail).foregroundColor(Color(hex: 0xE3D6BD)))
                .font(.system(size: 14))
            Spacer()
            if !degradation.confirmed {
                Button("Faire un test Moyen") { onVerify() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accentBorder))
    }
}

struct InfoBanner: View {
    let text: Text

    init(text: LocalizedStringKey) { self.text = Text(text) }
    /// Texte déjà traduit (message d'erreur).
    init(verbatim: String) { self.text = Text(verbatim: verbatim) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2")
                .foregroundStyle(Theme.accent)
            text.font(.system(size: 14)).foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EvolutionPanel: View {
    let user: UserProfile
    let headphoneID: UUID?
    @Binding var frequency: Int
    @Binding var ear: Ear

    private struct Sample: Identifiable {
        let id: UUID
        let date: Date
        let level: Int
    }

    private var samples: [Sample] {
        guard let headphoneID else { return [] }
        return Analysis.comparableSessions(user, headphoneID: headphoneID).compactMap { s in
            s.level(ear, frequency).map { Sample(id: s.id, date: s.date, level: $0) }
        }
    }

    private var deltaFromReference: Int? {
        guard let last = samples.last, let ref = user.reference, ref.headphoneID == headphoneID,
              let r = ref.level(ear, frequency) else { return nil }
        return last.level - r
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel("Évolution \(Analysis.frequencyLabel(frequency))Hz", color: Theme.secondary)
                    Spacer()
                    Picker("Oreille", selection: $ear) {
                        ForEach(Ear.allCases) { e in Text(e.label).tag(e) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: samples.last.map { "\($0.level)" } ?? "--")
                        .font(Theme.mono(34, .semibold))
                    Text(verbatim: "dB").foregroundStyle(Theme.muted)
                    Spacer()
                    if let d = deltaFromReference {
                        Text("\(d >= 0 ? "+" : "")\(d) depuis réf.")
                            .font(Theme.mono(13))
                            .foregroundStyle(d >= 10 ? Theme.accent : Theme.muted)
                    }
                }
                if samples.count >= 2 {
                    Chart(samples) { s in
                        LineMark(x: .value("Date", s.date), y: .value("dB", -s.level))
                            .foregroundStyle(Theme.color(for: ear))
                        PointMark(x: .value("Date", s.date), y: .value("dB", -s.level))
                            .foregroundStyle(Theme.color(for: ear))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Theme.border)
                            AxisValueLabel {
                                if let v = value.as(Int.self) { Text(verbatim: "\(-v)").font(Theme.mono(10)) }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel(format: .dateTime.month(.twoDigits).year(.twoDigits))
                        }
                    }
                    .frame(height: 100)
                } else {
                    Text("L'évolution s'affiche à partir de 2 tests comparables.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .frame(height: 40, alignment: .leading)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(Analysis.frequencies, id: \.self) { f in
                        Button {
                            frequency = f
                        } label: {
                            Text(verbatim: Analysis.frequencyLabel(f))
                                .font(Theme.mono(12))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .foregroundStyle(f == frequency ? Theme.accent : Theme.muted)
                                .background(f == frequency ? Theme.accentBg : Theme.raised,
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SessionsPanel: View {
    @Environment(DataStore.self) private var store
    let user: UserProfile
    let selectedID: UUID?
    var onSelect: (UUID) -> Void
    @State private var sessionToDelete: TestSession?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Sessions", color: Theme.secondary).padding(.bottom, 6)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(user.sortedSessions) { s in
                            row(s)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .confirmationDialog("Supprimer cette session ? Elle disparaît de l'historique.",
                            isPresented: Binding(get: { sessionToDelete != nil },
                                                 set: { if !$0 { sessionToDelete = nil } }),
                            presenting: sessionToDelete) { s in
            Button("Supprimer la session du \(Format.long.string(from: s.date))", role: .destructive) {
                store.deleteSession(s.id, of: user.id)
            }
        }
    }

    private func row(_ s: TestSession) -> some View {
        Button {
            onSelect(s.id)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: Format.day.string(from: s.date))
                    .font(Theme.mono(13))
                    .foregroundStyle(s.noisy ? Theme.muted : Theme.text)
                if s.earMode != .both {
                    Text(s.earMode == .right ? "D" : "G")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }
                if let note = s.note {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .help(Text(verbatim: note))
                }
                Spacer()
                status(s)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(s.id == selectedID ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Définir comme référence") { store.setReference(s.id, for: user.id) }
            Button("Supprimer la session…", role: .destructive) { sessionToDelete = s }
        }
    }

    @ViewBuilder
    private func status(_ s: TestSession) -> some View {
        if s.id == user.referenceSessionID {
            Text("Référence").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        } else if s.noisy {
            Text("Bruyant, exclue").font(.system(size: 12)).foregroundStyle(Theme.accent)
        } else if let r = s.reliability {
            Text("Fiable \(Int((r * 100).rounded())) %")
                .font(.system(size: 12))
                .foregroundStyle(r >= 0.8 ? Theme.ok : Theme.accent)
        } else {
            Text(verbatim: "")
        }
    }
}

// MARK: Scores aux jeux

private func placeText(_ index: Int) -> String { Format.place(index) }

/// Carte cliquable d'un jeu dans la fiche (ouvre sa page d'accueil).
private struct GameScoreCard<Icon: View, Content: View>: View {
    let title: LocalizedStringKey
    var action: () -> Void
    @ViewBuilder var icon: Icon
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    icon
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hover ? Theme.text : Theme.muted)
                }
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(Neon.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hover ? Theme.borderStrong : Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Chasse au moustique : record, place, et fréquence max au fil des parties.
/// Purement indicatif : le jeu n'est pas une session de test, il ne déclenche aucune alerte.
private struct MosquitoScoreCard: View {
    @Environment(DataStore.self) private var store
    let user: UserProfile
    var action: () -> Void

    var body: some View {
        let games = store.mosquitoGames(for: user.id)
        let points = games.filter { $0.bestFrequency != nil }
        let place = store.mosquitoLeaderboard().firstIndex { $0.user.id == user.id }
        GameScoreCard(title: "Chasse au moustique", action: action) {
            MosquitoIcon().frame(width: 38, height: 23).neonGlow(Neon.pink, radius: 2)
        } content: {
            if let best = store.mosquitoBest(for: user.id) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: Format.hz(best)).font(Theme.mono(28, .semibold))
                    Text(verbatim: "Hz").foregroundStyle(Theme.muted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let place {
                            Text(placeText(place))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(place == 0 ? Neon.yellow : Theme.secondary)
                        }
                        Text("\(games.count) partie(s)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                if points.count >= 2 {
                    Chart(points) { g in
                        LineMark(x: .value("Date", g.date), y: .value("Hz", g.bestFrequency ?? 0))
                            .foregroundStyle(Neon.pink)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", g.date), y: .value("Hz", g.bestFrequency ?? 0))
                            .foregroundStyle(Neon.pink)
                            .symbolSize(18)
                    }
                    .chartYScale(domain: yDomain(points))
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(Theme.border)
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text(verbatim: "\(v / 1000) k").font(.system(size: 10))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .frame(height: 96)
                }
                Text("Indicatif : le jeu n'est pas un test (niveau fixe), il ne déclenche aucune alerte.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Pas encore de moustique attrapé.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Text("Jouer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Neon.pinkSoft)
            }
        }
    }

    private func yDomain(_ points: [MosquitoRecord]) -> ClosedRange<Int> {
        let values = points.compactMap(\.bestFrequency)
        let lo = max(0, (values.min() ?? 8000) - 1000)
        let hi = min(21000, (values.max() ?? 20000) + 1000)
        return lo...max(hi, lo + 2000)
    }
}

/// La juste note : record et place par niveau.
private struct PitchScoreCard: View {
    @Environment(DataStore.self) private var store
    let user: UserProfile
    var action: () -> Void

    var body: some View {
        let count = store.pitchGames(for: user.id).count
        GameScoreCard(title: "La juste note", action: action) {
            TuningForkIcon().frame(width: 24, height: 24).neonGlow(Neon.cyan, radius: 2)
        } content: {
            if count == 0 {
                Text("Pas encore de partie complète.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Text("Jouer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Neon.cyanSoft)
            } else {
                VStack(spacing: 0) {
                    ForEach(PitchLevel.allCases) { level in
                        row(level)
                        if level != PitchLevel.allCases.last {
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                    }
                }
                Text("\(count) partie(s) complète(s)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func row(_ level: PitchLevel) -> some View {
        let best = store.pitchBest(for: user.id, level: level)
        let place = store.pitchLeaderboard(level: level).firstIndex { $0.user.id == user.id }
        return HStack(spacing: 10) {
            Text(level.title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 70, alignment: .leading)
            if let best {
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Neon.yellow)
                Text(verbatim: "\(best.stars)/30").font(Theme.mono(13))
                Text("\(Int(best.meanError.rounded())) cents")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if let place {
                    Text(placeText(place))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(place == 0 ? Neon.yellow : Theme.secondary)
                }
            } else {
                Text("pas encore joué")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
}
