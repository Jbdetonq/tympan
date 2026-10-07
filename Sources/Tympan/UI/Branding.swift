import AppKit
import SwiftUI

/// Version affichée dans l'app, lue dans Info.plist.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static var versionLabel: String { "Tympan \(version) (\(build))" }
}

/// Logo Tympan : l'icône de l'app (oreille ambre sur fond sombre).
/// Lu dans le bundle ; dessiné en vectoriel si l'app tourne hors bundle.
struct TympanLogo: View {
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image = TympanLogo.bundleImage {
                // L'icns a une marge transparente de 10 % : on la compense.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 1.24, height: size * 1.24)
                    .frame(width: size, height: size)
            } else {
                TympanLogoShape()
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    static let bundleImage: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()
}

/// Même dessin que Support/AppIcon.svg (repère 824 x 824, carré arrondi).
struct TympanLogoShape: View {
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 824
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 100) * k, y: (y - 100) * k) }
            let rect = CGRect(origin: .zero, size: size)
            let bg = Path(roundedRect: rect, cornerRadius: 185 * k, style: .continuous)
            ctx.fill(bg, with: .linearGradient(Gradient(colors: [Color(hex: 0x23262C), Color(hex: 0x0E0F12)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let amber = Color(hex: 0xFFB020)
            let line = StrokeStyle(lineWidth: max(1.5, 34 * k), lineCap: .round, lineJoin: .round)
            // Oreille (même tracé que le SVG, décalé de -60 en x).
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { p(x - 60, y) }
            var outer = Path()
            outer.move(to: q(395, 440))
            outer.addCurve(to: q(585, 235), control1: q(395, 310), control2: q(485, 235))
            outer.addCurve(to: q(775, 430), control1: q(700, 235), control2: q(775, 320))
            outer.addCurve(to: q(685, 615), control1: q(775, 520), control2: q(715, 565))
            outer.addCurve(to: q(620, 765), control1: q(655, 665), control2: q(665, 720))
            outer.addCurve(to: q(495, 785), control1: q(585, 800), control2: q(530, 805))
            var inner = Path()
            inner.move(to: q(495, 450))
            inner.addCurve(to: q(590, 335), control1: q(495, 380), control2: q(540, 335))
            inner.addCurve(to: q(680, 430), control1: q(645, 335), control2: q(680, 380))
            inner.addCurve(to: q(610, 530), control1: q(680, 485), control2: q(635, 495))
            inner.addCurve(to: q(575, 600), control1: q(595, 552), control2: q(600, 580))
            ctx.stroke(outer, with: .color(amber), style: line)
            ctx.stroke(inner, with: .color(amber), style: line)
            let r = 38 * k
            for c in [q(495, 785), q(575, 600)] {
                let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(dot, with: .color(Color(hex: 0x16120A)))
                ctx.stroke(dot, with: .color(amber), lineWidth: max(1, 20 * k))
            }
        }
    }
}

extension Notification.Name {
    static let tympanAddUser = Notification.Name("tympan.addUser")
    static let tympanExport = Notification.Name("tympan.export")
    static let tympanImport = Notification.Name("tympan.import")
    static let tympanOnboarding = Notification.Name("tympan.onboarding")
    static let tympanReadingGuide = Notification.Name("tympan.readingGuide")
    static let tympanFAQ = Notification.Name("tympan.faq")
}

/// Liens publics du projet (contact par tickets GitHub, sans adresse personnelle).
enum AppLinks {
    static let repository = URL(string: "https://github.com/Jbdetonq/tympan")!
    static let newIssue = URL(string: "https://github.com/Jbdetonq/tympan/issues/new/choose")!
}

/// Force l'icône du Dock au lancement (macOS garde parfois l'ancienne en cache).
@MainActor
final class TympanAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Arrêt inattendu pendant un test (plantage, arrêt forcé) : on rend le volume d'avant.
        VolumeLock.recoverAfterCrash()
        if let image = TympanLogo.bundleImage {
            NSApp.applicationIconImage = image
        }
    }

    /// Cmd+Q pendant un test ou un jeu : le volume d'origine est rendu avant de quitter.
    func applicationWillTerminate(_ notification: Notification) {
        VolumeLock.releaseAll()
    }

    /// Fermer la fenêtre quitte l'app : pas de test qui continue sans fenêtre.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
