import SwiftUI

/// Univers des jeux : même fond sombre, dessins au néon façon écran de console.
enum Neon {
    static let bg = Color(hex: 0x0A0B0E)
    static let stage = Color(hex: 0x0D0F13)
    static let stageBorder = Color(hex: 0x1A1D23)
    static let card = Color(hex: 0x111317)
    static let cardBorder = Color(hex: 0x1F2228)
    static let mint = Color(hex: 0x3DFFB0)
    static let mintBg = Color(hex: 0x0F1A17)
    static let pink = Color(hex: 0xFF4FD8)
    static let pinkSoft = Color(hex: 0xFF8AE6)
    static let pinkBg = Color(hex: 0x160D15)
    static let cyan = Color(hex: 0x3DE0FF)
    static let cyanSoft = Color(hex: 0x8AEEFF)
    static let cyanBg = Color(hex: 0x0C1417)
    static let well = Color(hex: 0x0A0C10)
    static let track = Color(hex: 0x15181D)
    static let blackKey = Color(hex: 0x262930)
    static let yellow = Color(hex: 0xFFE14D)
    static let orange = Color(hex: 0xFF9A3D)
    static let red = Color(hex: 0xFF3B4A)
    static let redBg = Color(hex: 0x1C0B0E)
    static let dim = Color(hex: 0x5A5F6A)
    static let off = Color(hex: 0x3A3E46)
    static let dashed = Color(hex: 0x2A2D33)
    static let heardBorder = Color(hex: 0x23262C)
    static let caption = Color(hex: 0x9AA0AB)
    static let footnote = Color(hex: 0x6E737D)
}

extension View {
    /// Halo néon (deux ombres superposées).
    func neonGlow(_ color: Color, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.9), radius: radius * 0.6)
            .shadow(color: color.opacity(0.45), radius: radius * 2)
    }
}

/// Dessin à partir de coordonnées de maquette (viewBox SVG), mis à l'échelle du cadre.
struct ViewBox {
    let s: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(_ rect: CGRect, width: CGFloat, height: CGFloat) {
        s = min(rect.width / width, rect.height / height)
        ox = rect.minX + (rect.width - width * s) / 2
        oy = rect.minY + (rect.height - height * s) / 2
    }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: ox + x * s, y: oy + y * s)
    }

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s)
    }
}

/// Bocal (viewBox 120 x 150).
struct JarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 120, height: 150)
        var p = Path()
        p.addRoundedRect(in: v.r(30, 8, 60, 16), cornerSize: CGSize(width: 4 * v.s, height: 4 * v.s))
        p.move(to: v.p(34, 24))
        p.addLine(to: v.p(34, 34))
        p.addQuadCurve(to: v.p(14, 70), control: v.p(14, 44))
        p.addLine(to: v.p(14, 128))
        p.addQuadCurve(to: v.p(28, 142), control: v.p(14, 142))
        p.addLine(to: v.p(92, 142))
        p.addQuadCurve(to: v.p(106, 128), control: v.p(106, 142))
        p.addLine(to: v.p(106, 70))
        p.addQuadCurve(to: v.p(86, 34), control: v.p(106, 44))
        p.addLine(to: v.p(86, 24))
        return p
    }
}

/// Ondes de part et d'autre d'un bocal qui sonne (viewBox 200 x 150).
struct SoundWaves: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 200, height: 150)
        var p = Path()
        p.move(to: v.p(26, 60)); p.addQuadCurve(to: v.p(26, 90), control: v.p(16, 75))
        p.move(to: v.p(12, 50)); p.addQuadCurve(to: v.p(12, 100), control: v.p(-2, 75))
        p.move(to: v.p(174, 60)); p.addQuadCurve(to: v.p(174, 90), control: v.p(184, 75))
        p.move(to: v.p(188, 50)); p.addQuadCurve(to: v.p(188, 100), control: v.p(202, 75))
        return p
    }
}

/// Moustique de profil (viewBox 200 x 120) : aile, abdomen, thorax, tête.
struct MosquitoBody: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 200, height: 120)
        var p = Path()
        // Aile
        p.move(to: v.p(100, 48))
        p.addCurve(to: v.p(180, 18), control1: v.p(120, 10), control2: v.p(170, 6))
        p.addCurve(to: v.p(100, 50), control1: v.p(172, 34), control2: v.p(132, 44))
        p.closeSubpath()
        // Abdomen incliné de 16 degrés
        let c = v.p(136, 72)
        let abdomen = Path(ellipseIn: CGRect(x: c.x - 36 * v.s, y: c.y - 8 * v.s, width: 72 * v.s, height: 16 * v.s))
        let t = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: .pi * 16 / 180)
            .translatedBy(x: -c.x, y: -c.y)
        p.addPath(abdomen, transform: t)
        // Thorax et tête
        p.addEllipse(in: v.r(81, 47, 28, 22))
        p.addEllipse(in: v.r(69, 48, 14, 14))
        return p
    }
}

struct MosquitoHead: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 200, height: 120)
        return Path(ellipseIn: v.r(69, 48, 14, 14))
    }
}

/// Trompe et pattes.
struct MosquitoLegs: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 200, height: 120)
        var p = Path()
        p.move(to: v.p(70, 58)); p.addLine(to: v.p(26, 72))
        p.move(to: v.p(90, 67)); p.addQuadCurve(to: v.p(60, 112), control: v.p(72, 82))
        p.move(to: v.p(96, 69)); p.addQuadCurve(to: v.p(90, 116), control: v.p(94, 92))
        p.move(to: v.p(102, 68)); p.addQuadCurve(to: v.p(134, 114), control: v.p(122, 88))
        return p
    }
}

struct MosquitoIcon: View {
    var color: Color = Neon.pink

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 200, geo.size.height / 120)
            let style = StrokeStyle(lineWidth: max(1.2, 3 * s), lineCap: .round, lineJoin: .round)
            ZStack {
                MosquitoBody().fill(color.opacity(0.22))
                MosquitoHead().fill(color)
                MosquitoBody().stroke(color, style: style)
                MosquitoLegs().stroke(color, style: style)
            }
        }
        .aspectRatio(200.0 / 120.0, contentMode: .fit)
    }
}

/// Bouton plein néon (Rejouer, Jouer).
struct NeonButtonStyle: ButtonStyle {
    var color: Color = Neon.pink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .foregroundStyle(Color(hex: 0x16060F))
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: color.opacity(0.35), radius: 14)
            .contentShape(Rectangle())
    }
}

/// Module sombre des jeux.
struct NeonCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Neon.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Neon.cardBorder))
    }
}

/// Diapason (viewBox 40 x 40), icône de « La juste note ».
struct TuningForkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 40, height: 40)
        var p = Path()
        p.move(to: v.p(14, 4))
        p.addLine(to: v.p(14, 18))
        p.addQuadCurve(to: v.p(20, 25), control: v.p(14, 25))
        p.addQuadCurve(to: v.p(26, 18), control: v.p(26, 25))
        p.addLine(to: v.p(26, 4))
        p.move(to: v.p(20, 25))
        p.addLine(to: v.p(20, 37))
        return p
    }
}

struct TuningForkWaves: Shape {
    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: 40, height: 40)
        var p = Path()
        p.move(to: v.p(31, 10)); p.addQuadCurve(to: v.p(31, 18), control: v.p(35, 14))
        p.move(to: v.p(9, 10)); p.addQuadCurve(to: v.p(9, 18), control: v.p(5, 14))
        return p
    }
}

struct TuningForkIcon: View {
    var color: Color = Neon.cyan

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 40
            let style = StrokeStyle(lineWidth: max(1.2, 2.5 * s), lineCap: .round, lineJoin: .round)
            ZStack {
                TuningForkShape().stroke(color, style: style)
                TuningForkWaves().stroke(color.opacity(0.6), style: style)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
