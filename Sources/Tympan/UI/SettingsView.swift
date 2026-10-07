import AppKit
import SwiftUI

/// Test ou partie en cours : la langue ne peut pas être changée (l'app redémarre).
@Observable
final class AppActivity {
    var busy = false
}

/// Langue de l'app : celle du système, ou imposée pour Tympan seulement.
enum LanguageChoice: String, CaseIterable, Identifiable {
    case system, fr, en
    var id: String { rawValue }

    private static let key = "AppleLanguages"

    /// Choix enregistré pour Tympan (le réglage global du Mac n'est pas lu ici).
    static var saved: LanguageChoice {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        return LanguageChoice(rawValue: String(first.prefix(2))) ?? .system
    }

    func save() {
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: Self.key)
        case .fr, .en: UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }

    /// Relance Tympan : la nouvelle langue s'applique partout d'un coup (textes, dates, PDF).
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Fenêtre Réglages (menu Tympan > Réglages, ⌘,).
struct SettingsView: View {
    @Environment(AppActivity.self) private var activity
    @State private var choice = LanguageChoice.saved
    private let applied = LanguageChoice.saved

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Langue")
            Picker("Langue", selection: $choice) {
                Text("Suivre le système").tag(LanguageChoice.system)
                Text(verbatim: "Français").tag(LanguageChoice.fr)
                Text(verbatim: "English").tag(LanguageChoice.en)
            }
            .labelsHidden()
            .frame(width: 240)
            HStack(alignment: .center, spacing: 12) {
                Text(activity.busy
                     ? "Termine d'abord le test ou la partie en cours."
                     : "Tympan redémarre pour appliquer la langue.")
                    .font(.system(size: 12))
                    .foregroundStyle(activity.busy ? Theme.accent : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Redémarrer") {
                    choice.save()
                    LanguageChoice.relaunch()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(choice == applied || activity.busy)
                .opacity(choice == applied || activity.busy ? 0.4 : 1)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
