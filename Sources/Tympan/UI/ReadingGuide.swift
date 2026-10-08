import SwiftUI

/// Résumé en phrases simples sous l'audiogramme de la fiche.
/// Lignes calculées par `Analysis.summary`.
struct ResultSummaryView: View {
    let lines: [Analysis.SummaryLine]
    /// Ouvre la page « Lire un audiogramme ».
    var onHelp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("En clair", color: Theme.secondary)
                Spacer()
                Button(action: onHelp) {
                    Label("Comment lire un audiogramme ?", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
            }
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: icon(line.tone))
                        .foregroundStyle(color(line.tone))
                        .font(.system(size: 13))
                    Text(verbatim: line.text)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelDeep, in: RoundedRectangle(cornerRadius: 10))
    }

    private func icon(_ tone: Analysis.SummaryLine.Tone) -> String {
        switch tone {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        }
    }

    private func color(_ tone: Analysis.SummaryLine.Tone) -> Color {
        switch tone {
        case .ok: return Theme.ok
        case .info: return Theme.secondary
        case .warn: return Theme.accent
        }
    }
}

/// Page « Lire un audiogramme » : un exemple commenté, sans jargon.
struct ReadingGuideView: View {
    /// Retour vers la fiche (nil si on vient de la barre latérale sans utilisateur).
    var onBack: (() -> Void)?

    /// Repère numéroté sous l'exemple.
    private struct Tip: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let tips: [Tip] = [
        Tip(id: 1, title: "Chaque point",
            text: "C'est le son le plus faible que tu as entendu à cette hauteur. Plus le point est haut, plus tu entends les sons doux."),
        Tip(id: 2, title: "De gauche à droite",
            text: "Des graves aux aigus. La voix se situe surtout entre 500 Hz et 4 kHz ; les consonnes comme s, f ou ch sont dans les aigus."),
        Tip(id: 3, title: "Les couleurs",
            text: "Rouge (O) : oreille droite. Bleu (X) : oreille gauche. Un symbole grisé : rien entendu, même au niveau maximum."),
        Tip(id: 4, title: "Les pointillés",
            text: "Ta référence, en général ton premier test. Si la courbe passe nettement sous les pointillés, tu entends moins bien qu'avant à cet endroit."),
        Tip(id: 5, title: "Les chiffres",
            text: "Ce sont des dB propres à Tympan et à ton casque. On compare seulement avec toi-même, même casque et même volume. Pas avec une autre personne, ni avec un audiogramme fait chez un ORL."),
        Tip(id: 6, title: "Ce qui est habituel",
            text: "5 dB d'écart d'un test à l'autre (fatigue, attention, casque un peu déplacé). Des aigus qui baissent doucement avec les années."),
        Tip(id: 7, title: "Quand consulter",
            text: "Un bandeau « Baisse à signaler », une oreille nettement moins bonne que l'autre test après test, ou une baisse brutale (ORL sous 48 h)."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                example
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                          alignment: .leading, spacing: 16) {
                    ForEach(tips) { tip in card(tip) }
                }
                Text("Sous chaque audiogramme, la fiche résume aussi le résultat en quelques phrases. Tympan suit ton audition dans le temps, il ne pose pas de diagnostic.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Label("Retour", systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Lire un audiogramme").font(.system(size: 28, weight: .semibold))
                Text("Un exemple, et ce qu'il faut regarder.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    /// Audiogramme fictif, avec le sens des axes en clair (graves / aigus, sons doux / forts).
    private var example: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Exemple", color: Theme.secondary)
                    Spacer()
                    AudiogramLegend(showReference: true)
                }
                HStack(spacing: 10) {
                    VStack {
                        axisCaption("Sons doux", systemImage: "arrow.up")
                        Spacer()
                        axisCaption("Sons forts", systemImage: "arrow.down")
                    }
                    .frame(width: 84)
                    AudiogramChart(session: Self.sample, reference: Self.sampleReference)
                        .frame(minHeight: 260)
                }
                HStack {
                    axisCaption("Graves", systemImage: "arrow.left")
                    Spacer()
                    Text("Hauteur du son (Hz)")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Aigus")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 94)
            }
        }
    }

    private func axisCaption(_ text: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.secondary)
    }

    private func card(_ tip: Tip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(tip.id)")
                .font(Theme.mono(13, .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 24, height: 24)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title).font(.system(size: 15, weight: .semibold))
                Text(tip.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    // MARK: Données d'exemple (fictives)

    /// Session fictive : un niveau par fréquence du format Complet, pour chaque oreille.
    private static func session(_ right: [Int], _ left: [Int]) -> TestSession {
        var s = TestSession(headphoneID: UUID(), earMode: .both)
        let freqs = TestLength.full.frequencies
        s.thresholds = freqs.indices.flatMap { i in
            [Threshold(ear: .right, frequency: freqs[i], level: right[i], noResponse: false),
             Threshold(ear: .left, frequency: freqs[i], level: left[i], noResponse: false)]
        }
        return s
    }

    // 250, 500, 1k, 2k, 3k, 4k, 6k, 8k, 10k : aigus en légère baisse, un peu moins bons que la référence.
    private static let sample = session([15, 10, 10, 15, 20, 25, 35, 40, 50],
                                        [10, 10, 5, 10, 20, 30, 40, 45, 55])
    private static let sampleReference = session([15, 10, 10, 10, 15, 20, 25, 30, 40],
                                                 [10, 5, 5, 10, 15, 20, 30, 35, 45])
}
