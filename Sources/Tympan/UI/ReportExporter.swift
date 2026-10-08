import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Export PDF A4 d'un audiogramme, lisible à l'impression (fond blanc).
enum ReportExporter {
    /// Demande où enregistrer, dessine la page en PDF puis l'ouvre.
    @MainActor
    static func export(user: UserProfile, session: TestSession, reference: TestSession?, headphone: HeadphoneProfile?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let day = Format.day.string(from: session.date)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        panel.nameFieldStringValue = String(localized: "Audiogramme \(user.name) \(day).pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let page = ReportPage(user: user, session: session, reference: reference, headphone: headphone)
            .frame(width: 595, height: 842)
            .environment(\.colorScheme, .light)
        // Rendu vectoriel : le texte reste net et sélectionnable dans le PDF.
        let renderer = ImageRenderer(content: page)
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        NSWorkspace.shared.open(url)
    }
}

/// Page A4 (595 x 842 points) : en-tête, audiogramme, tableau des seuils, fiabilité, avertissement.
private struct ReportPage: View {
    let user: UserProfile
    let session: TestSession
    let reference: TestSession?
    let headphone: HeadphoneProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Tympan").font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray)
                Spacer()
                Text(verbatim: Format.long.string(from: session.date)).font(.system(size: 13)).foregroundStyle(.gray)
            }
            Text("Audiogramme · \(user.name)").font(.system(size: 24, weight: .semibold))
            Text("Né(e) en \(String(user.birthYear)) · casque : \(headphone?.name ?? "?") (volume \(Int((headphone?.volume ?? 0) * 100)) %)")
                .font(.system(size: 12)).foregroundStyle(.gray)
            Text(verbatim: formatLine)
                .font(.system(size: 12)).foregroundStyle(.gray)

            AudiogramChart(session: session, reference: reference,
                           plotBackground: .white, gridColor: Color(white: 0.78), gridWidth: 0.75)
                .frame(height: 360)
            AudiogramLegend(showReference: reference != nil, textColor: .black)

            table
            if hasNoResponse {
                Text("« > \(session.format.maxLevel) » : rien entendu, même au niveau maximum de l'app. « - » : fréquence non testée.")
                    .font(.system(size: 11)).foregroundStyle(.gray)
            }
            if let note = session.note {
                Text("Commentaire : \(note)")
                    .font(.system(size: 12))
            }
            if let r = session.reliability {
                let percent = Int((r * 100).rounded())
                Text(session.noisy
                     ? LocalizedStringKey("Essais pièges ignorés : \(percent) % · appuis sans bip : \(session.spuriousPresses) · pièce bruyante")
                     : LocalizedStringKey("Essais pièges ignorés : \(percent) % · appuis sans bip : \(session.spuriousPresses)"))
                    .font(.system(size: 11)).foregroundStyle(.gray)
            }
            Spacer()
            Text("Valeurs en dB relatifs à l'application, comparables uniquement avec le même casque au même volume. Outil de suivi personnel : ne remplace pas un audiogramme réalisé par un professionnel de santé.")
                .font(.system(size: 10)).foregroundStyle(.gray)
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    /// « Test Moyen · deux oreilles », « Mode enfant (plafond 70 dB) · deux oreilles ».
    private var formatLine: String {
        let ears: String
        switch session.earMode {
        case .both: ears = String(localized: "deux oreilles")
        case .right: ears = String(localized: "oreille droite seule")
        case .left: ears = String(localized: "oreille gauche seule")
        }
        if session.kidMode || session.format == .kid {
            return String(localized: "Mode enfant (plafond \(session.format.maxLevel) dB) · \(ears)")
        }
        let name: String
        switch session.format {
        case .quick: name = String(localized: "Rapide")
        case .standard: name = String(localized: "Moyen")
        case .full: name = String(localized: "Complet")
        case .kid: name = String(localized: "Enfant")
        }
        return String(localized: "Test \(name) · \(ears)")
    }

    private var hasNoResponse: Bool { session.thresholds.contains(where: \.noResponse) }

    /// Seuil en dB, « > 90 » si rien entendu au maximum, « - » si non testé.
    private func cell(_ ear: Ear, _ f: Int) -> String {
        guard let t = session.threshold(ear, f) else { return "-" }
        return t.noResponse ? "> \(session.format.maxLevel)" : "\(t.level)"
    }

    /// Fréquences présentes dans la session (colonnes du tableau).
    private var measured: [Int] {
        Array(Set(session.thresholds.map(\.frequency))).sorted()
    }

    private var table: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text(verbatim: "Hz").foregroundStyle(.gray)
                ForEach(measured, id: \.self) { f in
                    Text(verbatim: Analysis.frequencyLabel(f)).foregroundStyle(.gray)
                }
            }
            ForEach(session.earMode.ears) { ear in
                GridRow {
                    Text(ear.label).foregroundStyle(Theme.color(for: ear))
                    ForEach(measured, id: \.self) { f in
                        Text(verbatim: cell(ear, f))
                    }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
