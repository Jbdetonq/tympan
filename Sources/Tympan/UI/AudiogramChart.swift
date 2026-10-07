import Charts
import SwiftUI

/// Audiogramme au format clinique : fréquences en octaves, dB vers le bas.
/// L'axe Y trace -dB pour que les pertes descendent.
struct AudiogramChart: View {
    var session: TestSession?
    var reference: TestSession?
    var plotBackground: Color = Theme.panelDeep
    var gridColor: Color = Theme.border
    /// Épaisseur de la grille.
    var gridWidth: CGFloat = 0.5

    private struct Point: Identifiable {
        let id: String
        let ear: Ear
        let x: Double
        let y: Double
        let noResponse: Bool
    }

    static func x(_ frequency: Int) -> Double { log2(Double(frequency) / 250) }

    private func points(_ s: TestSession?, tag: String) -> [Point] {
        guard let s else { return [] }
        return s.thresholds
            .sorted { ($0.ear.rawValue, $0.frequency) < ($1.ear.rawValue, $1.frequency) }
            .map {
                Point(id: "\(tag)-\($0.ear.rawValue)-\($0.frequency)",
                      ear: $0.ear,
                      x: Self.x($0.frequency),
                      y: -Double($0.level),
                      noResponse: $0.noResponse)
            }
    }

    var body: some View {
        let current = points(session, tag: "c")
        let ref = points(reference, tag: "r")

        Chart {
            // Grille dessinée en marques : AxisGridLine n'apparaît pas à l'export PDF (ImageRenderer).
            ForEach(Analysis.axisFrequencies, id: \.self) { f in
                RuleMark(x: .value("Fréquence", Self.x(f)))
                    .foregroundStyle(gridColor)
                    .lineStyle(StrokeStyle(lineWidth: gridWidth))
            }
            ForEach(Array(stride(from: -90, through: 10, by: 10)), id: \.self) { db in
                RuleMark(y: .value("Seuil", Double(db)))
                    .foregroundStyle(gridColor)
                    .lineStyle(StrokeStyle(lineWidth: gridWidth))
            }
            ForEach(ref) { p in
                LineMark(x: .value("Fréquence", p.x),
                         y: .value("Seuil", p.y),
                         series: .value("Série", "ref-\(p.ear.rawValue)"))
                    .foregroundStyle(Theme.color(for: p.ear).opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            ForEach(current) { p in
                LineMark(x: .value("Fréquence", p.x),
                         y: .value("Seuil", p.y),
                         series: .value("Série", "cur-\(p.ear.rawValue)"))
                    .foregroundStyle(Theme.color(for: p.ear))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(current) { p in
                PointMark(x: .value("Fréquence", p.x), y: .value("Seuil", p.y))
                    .symbol {
                        EarSymbol(ear: p.ear, dimmed: p.noResponse)
                    }
            }
        }
        .chartXScale(domain: -0.3...5.6)
        .chartYScale(domain: -100.0...12.0)
        .chartXAxis {
            AxisMarks(values: Analysis.axisFrequencies.map { Self.x($0) }) { value in
                AxisValueLabel {
                    Text(verbatim: Analysis.frequencyLabel(Analysis.axisFrequencies[value.index]))
                        .font(Theme.mono(11))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(stride(from: -90.0, through: 10.0, by: 10.0))) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(verbatim: "\(Int(-v))").font(Theme.mono(11))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(plotBackground)
        }
    }
}

/// Légende de l'audiogramme.
struct AudiogramLegend: View {
    var showReference = true
    /// Noir sur le PDF (fond blanc).
    var textColor: Color = Theme.secondary

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { EarSymbol(ear: .right); Text("Droite") }
            HStack(spacing: 6) { EarSymbol(ear: .left); Text("Gauche") }
            if showReference {
                HStack(spacing: 6) {
                    Rectangle().fill(Theme.right.opacity(0.6)).frame(width: 18, height: 2)
                        .mask(HStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in Rectangle().frame(width: 3) } })
                    Text("Référence")
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(textColor)
    }
}
