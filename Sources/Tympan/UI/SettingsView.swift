import AppKit
import SwiftUI

/// Test ou partie en cours : la langue ne peut pas être changée (l'app redémarre).
@Observable
final class AppActivity {
    var busy = false
}

/// Langue de l'app : celle du système, ou imposée pour Tympan seulement.
/// Les langues proposées sont celles livrées dans l'app (dossiers xx.lproj) :
/// ajouter une traduction ne demande aucun changement de code.
enum LanguageChoice {
    /// Code de langue (« fr », « en »…), "" pour suivre le système.
    static let system = ""

    private static let key = "AppleLanguages"

    /// Langues livrées, triées par leur nom dans leur propre langue.
    static var available: [String] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
    }

    /// Nom de la langue dans sa propre langue : « Français », « English », « Deutsch ».
    static func displayName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Choix enregistré pour Tympan (le réglage global du Mac n'est pas lu ici).
    static var saved: String {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        guard let first = (domain?[key] as? [String])?.first else { return system }
        let code = available.first { first == $0 || first.hasPrefix($0 + "-") }
        return code ?? system
    }

    static func save(_ code: String) {
        if code == system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([code], forKey: key)
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
                ForEach(LanguageChoice.available, id: \.self) { code in
                    Text(verbatim: LanguageChoice.displayName(code)).tag(code)
                }
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
                    LanguageChoice.save(choice)
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
