import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Export PDF A4 d'un audiogramme, lisible à l'impression (fond blanc).
enum ReportExporter {
    @MainActor
    static func export(user: UserProfile, session: TestSession, reference: TestSession?, headphone: HeadphoneProfile?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Audiogramme \(user.name) \(Format.day.string(from: session.date).replacingOccurrences(of: "/", with: "-")).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let page = ReportPage(user: user, session: session, reference: reference, headphone: headphone)
            .frame(width: 595, height: 842)
            .environment(\.colorScheme, .light)
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
            Text(verbatim: "Audiogramme · \(user.name)").font(.system(size: 24, weight: .semibold))
            Text(verbatim: "Né(e) en \(String(user.birthYear)) · casque : \(headphone?.name ?? "?") (volume \(Int((headphone?.volume ?? 0) * 100)) %)")
                .font(.system(size: 12)).foregroundStyle(.gray)

            AudiogramChart(session: session, reference: reference,
                           plotBackground: .white, gridColor: Color(white: 0.78), gridWidth: 0.75)
                .frame(height: 360)
            AudiogramLegend(showReference: reference != nil)
                .foregroundStyle(.black)

            table
            if let note = session.note {
                Text(verbatim: "Commentaire : \(note)")
                    .font(.system(size: 12))
            }
            if let r = session.reliability {
                Text(verbatim: "Essais pièges ignorés : \(Int((r * 100).rounded())) % · appuis sans bip : \(session.spuriousPresses)"
                     + (session.noisy ? " · pièce bruyante" : ""))
                    .font(.system(size: 11)).foregroundStyle(.gray)
            }
            Spacer()
            Text(verbatim: "Valeurs en dB relatifs à l'application, comparables uniquement avec le même casque au même volume. Outil de suivi personnel : ne remplace pas un audiogramme réalisé par un professionnel de santé.")
                .font(.system(size: 10)).foregroundStyle(.gray)
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(.black)
    }

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
            ForEach(Ear.allCases) { ear in
                GridRow {
                    Text(ear.label).foregroundStyle(Theme.color(for: ear))
                    ForEach(measured, id: \.self) { f in
                        Text(verbatim: session.level(ear, f).map { "\($0)" } ?? "-")
                    }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
