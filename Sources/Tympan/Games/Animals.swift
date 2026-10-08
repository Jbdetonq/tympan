import SwiftUI

/// Mode enfant : un animal par fréquence, du plus gros (cri grave) au plus petit (cri aigu).
enum Animal: Int, CaseIterable, Identifiable {
    case elephant, cat, rabbit, bird, mouse
    var id: Int { rawValue }

    /// Fréquence testée (Hz) : les 5 fréquences du format Enfant.
    var frequency: Int {
        switch self {
        case .elephant: return 500
        case .cat: return 1000
        case .rabbit: return 2000
        case .bird: return 4000
        case .mouse: return 8000
        }
    }

    /// Animal d'une fréquence, nil si aucune.
    static func forFrequency(_ f: Int?) -> Animal? {
        allCases.first { $0.frequency == f }
    }

    /// Couleur propre de l'animal (page d'accueil). Pendant le test, il prend la couleur de l'oreille.
    var color: Color {
        switch self {
        case .elephant: return Neon.orange
        case .cat: return Neon.pink
        case .rabbit: return Neon.mint
        case .bird: return Neon.yellow
        case .mouse: return Neon.cyan
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .elephant: return "Éléphant"
        case .cat: return "Chat"
        case .rabbit: return "Lapin"
        case .bird: return "Oiseau"
        case .mouse: return "Souris"
        }
    }

    /// Phrases complètes (accords du genre selon la langue) : seuil trouvé, ou aucune réponse.
    var found: LocalizedStringKey {
        switch self {
        case .elephant: return "Bravo, tu as trouvé l'éléphant !"
        case .cat: return "Bravo, tu as trouvé le chat !"
        case .rabbit: return "Bravo, tu as trouvé le lapin !"
        case .bird: return "Bravo, tu as trouvé l'oiseau !"
        case .mouse: return "Bravo, tu as trouvé la souris !"
        }
    }

    var asleep: LocalizedStringKey {
        switch self {
        case .elephant: return "L'éléphant fait la sieste"
        case .cat: return "Le chat fait la sieste"
        case .rabbit: return "Le lapin fait la sieste"
        case .bird: return "L'oiseau fait la sieste"
        case .mouse: return "La souris fait la sieste"
        }
    }

    /// Taille du dessin (viewBox).
    var box: CGSize {
        switch self {
        case .elephant: return CGSize(width: 54, height: 44)
        case .rabbit: return CGSize(width: 48, height: 48)
        default: return CGSize(width: 48, height: 44)
        }
    }
}

/// Contour d'un animal.
struct AnimalShape: Shape {
    let animal: Animal

    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: animal.box.width, height: animal.box.height)
        var p = Path()
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { p.addEllipse(in: v.r(x - r, y - r, 2 * r, 2 * r)) }
        func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) { p.move(to: v.p(a.0, a.1)); p.addLine(to: v.p(b.0, b.1)) }
        switch animal {
        case .elephant:
            p.addEllipse(in: v.r(20, 10, 30, 22))           // corps
            circle(15, 17, 10)                              // tête
            p.addEllipse(in: v.r(17, 8, 12, 18))            // oreille
            p.move(to: v.p(7, 21))                          // trompe
            p.addQuadCurve(to: v.p(5, 36), control: v.p(2, 28))
            p.addQuadCurve(to: v.p(10, 37), control: v.p(7, 41))
            for x: CGFloat in [26, 33, 40, 46] { line((x, 31), (x, 40)) }
            p.move(to: v.p(50, 19)); p.addQuadCurve(to: v.p(52, 28), control: v.p(54, 23))
        case .cat:
            p.move(to: v.p(9, 16)); p.addLine(to: v.p(10, 3)); p.addLine(to: v.p(20, 11))
            p.addLine(to: v.p(28, 11)); p.addLine(to: v.p(38, 3)); p.addLine(to: v.p(39, 16))
            circle(24, 25, 16)
            line((2, 28), (14, 29)); line((2, 34), (14, 32)); line((46, 28), (34, 29)); line((46, 34), (34, 32))
        case .rabbit:
            p.move(to: v.p(19, 22)); p.addQuadCurve(to: v.p(17, 3), control: v.p(11, 8))
            p.addQuadCurve(to: v.p(23, 21), control: v.p(24, 6))
            p.move(to: v.p(29, 21)); p.addQuadCurve(to: v.p(33, 3), control: v.p(26, 6))
            p.addQuadCurve(to: v.p(33, 22), control: v.p(40, 8))
            circle(25, 33, 13)
            p.move(to: v.p(23, 36)); p.addLine(to: v.p(25, 38)); p.addLine(to: v.p(27, 36))
        case .bird:
            p.move(to: v.p(6, 28)); p.addQuadCurve(to: v.p(26, 14), control: v.p(10, 12))
            p.addQuadCurve(to: v.p(40, 24), control: v.p(38, 14))
            p.addQuadCurve(to: v.p(14, 34), control: v.p(30, 36)); p.closeSubpath()
            p.move(to: v.p(40, 20)); p.addLine(to: v.p(47, 22)); p.addLine(to: v.p(40, 25))
            p.move(to: v.p(16, 24)); p.addQuadCurve(to: v.p(30, 22), control: v.p(22, 16))
        case .mouse:
            circle(12, 14, 9); circle(36, 14, 9)
            p.addEllipse(in: v.r(10, 15, 28, 24))
            line((4, 30), (16, 31)); line((44, 30), (32, 31))
        }
        return p
    }
}

/// Yeux et nez (pleins). Les yeux se ferment quand l'animal dort.
struct AnimalDots: Shape {
    let animal: Animal

    func path(in rect: CGRect) -> Path {
        let v = ViewBox(rect, width: animal.box.width, height: animal.box.height)
        var p = Path()
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { p.addEllipse(in: v.r(x - r, y - r, 2 * r, 2 * r)) }
        switch animal {
        case .elephant: dot(11, 15, 1.6)
        case .cat: dot(18, 23, 2); dot(30, 23, 2)
        case .rabbit: dot(20, 31, 1.8); dot(30, 31, 1.8)
        case .bird: dot(34, 19, 1.8)
        case .mouse: dot(19, 25, 1.8); dot(29, 25, 1.8); dot(24, 31, 1.6)
        }
        return p
    }
}

/// Animal néon : contour et yeux, gris et yeux fermés quand il dort.
struct AnimalIcon: View {
    let animal: Animal
    /// Couleur imposée (celle de l'oreille), sinon celle de l'animal.
    var color: Color? = nil
    var asleep = false

    var body: some View {
        let c = asleep ? Neon.dim : (color ?? animal.color)
        GeometryReader { geo in
            let s = min(geo.size.width / animal.box.width, geo.size.height / animal.box.height)
            let width = min(6, max(2, 2.5 * s))
            ZStack {
                AnimalShape(animal: animal)
                    .stroke(c, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                if !asleep {
                    AnimalDots(animal: animal).fill(c)
                }
            }
        }
        .aspectRatio(animal.box.width / animal.box.height, contentMode: .fit)
    }
}
