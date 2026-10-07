import AppKit
import SwiftUI

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
        }

        // Menu Tympan > Réglages (⌘,) : choix de la langue.
        Settings {
            SettingsView()
                .environment(activity)
        }
    }
}
