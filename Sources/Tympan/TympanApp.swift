import AppKit
import SwiftUI

/// Point d'entrée : une fenêtre (barre de titre masquée, thème sombre), les menus et les Réglages.
@main
struct TympanApp: App {
    @NSApplicationDelegateAdaptor(TympanAppDelegate.self) private var appDelegate
    @State private var store = DataStore()
    @State private var activity = AppActivity()

    var body: some Scene {
        WindowGroup("Tympan") {
            ContentView()
                .environment(store)
                .environment(activity)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // Min seul (pas de max) : la fenêtre ne peut pas rétrécir sous la taille
                // réellement demandée par le contenu, sinon tout déborde en haut et en bas.
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // Les menus passent par des notifications : ContentView affiche la page demandée.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ajouter un utilisateur…") {
                    NotificationCenter.default.post(name: .tympanAddUser, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(replacing: .importExport) {
                Button("Exporter les données…") {
                    NotificationCenter.default.post(name: .tympanExport, object: nil)
                }
                .keyboardShortcut("e")
                Button("Importer des données…") {
                    NotificationCenter.default.post(name: .tympanImport, object: nil)
                }
                .keyboardShortcut("i")
            }
            // Menu Aide : le guide, la lecture d'un audiogramme et la FAQ.
            CommandGroup(replacing: .help) {
                Button("Découvrir Tympan") {
                    NotificationCenter.default.post(name: .tympanOnboarding, object: nil)
                }
                Divider()
                Button("Lire un audiogramme") {
                    NotificationCenter.default.post(name: .tympanReadingGuide, object: nil)
                }
                Button("Questions fréquentes") {
                    NotificationCenter.default.post(name: .tympanFAQ, object: nil)
                }
            }
        }

        // Menu Tympan > Réglages (⌘,) : choix de la langue.
        Settings {
            SettingsView()
                .environment(activity)
        }
    }
}
