import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Page affichée à droite de la barre latérale. Plus aucune feuille modale :
/// tout s'affiche en page, seules les confirmations restent en dialogue.
enum AppPage: Hashable {
    case user, addUser, newTest, kidMode, mosquito, pitch, faq, readingGuide, onboarding
}

struct ContentView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppActivity.self) private var activity
    @State private var page: AppPage = Onboarding.seen ? .user : .onboarding
    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var selectedUserID: UUID?
    @State private var runner: TestRunner?
    @State private var suggestedLength: TestLength?
    @State private var mosquito: MosquitoGame?
    @State private var mosquitoResult: MosquitoResult?
    @State private var pitch: PitchGame?
    @State private var pitchResult: PitchResult?

    var body: some View {
        Group {
            // Test ou partie en cours : plein écran, barre latérale repliée.
            if isBusy {
                FitOrScroll { fullScreenPage }
            } else {
                // Mise en page simple (pas de NavigationSplitView) : la barre latérale et
                // la page défilent chacune et ne forcent jamais la hauteur de la fenêtre.
                HStack(spacing: 0) {
                    SidebarView(selection: sidebarSelection,
                                active: shownPage,
                                highlights: shownPage == .onboarding
                                    ? onboardingStep.highlights(hasUsers: !store.data.users.isEmpty) : [],
                                onAddUser: { page = .addUser },
                                onAudiogram: { openNewTest(length: nil) },
                                onKidMode: { open(.kidMode) },
                                onMosquito: { open(.mosquito) },
                                onPitch: { open(.pitch) },
                                onOnboarding: { openOnboarding() },
                                onFAQ: { page = .faq },
                                onReadingGuide: { page = .readingGuide })
                        .frame(width: 240)
                        .frame(maxHeight: .infinity)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(Theme.bg)
        .onReceive(NotificationCenter.default.publisher(for: .tympanAddUser)) { _ in
            if !isBusy { page = .addUser }
        }
        // Menu Aide de macOS.
        .onReceive(NotificationCenter.default.publisher(for: .tympanOnboarding)) { _ in
            if !isBusy { openOnboarding() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tympanReadingGuide)) { _ in
            if !isBusy { page = .readingGuide }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tympanFAQ)) { _ in
            if !isBusy { page = .faq }
        }
        .onChange(of: page) { old, _ in
            mosquitoResult = nil
            pitchResult = nil
            // Quitter le guide (Passer, fin, ou clic dans la barre latérale) : il ne revient plus seul.
            if old == .onboarding { Onboarding.markSeen() }
        }
        .onChange(of: store.data.users.map(\.id)) {
            // Utilisateur supprimé : on bascule sur le premier restant.
            if selectedUser == nil { selectedUserID = store.data.users.first?.id }
        }
        .onAppear {
            if selectedUserID == nil { selectedUserID = store.data.users.first?.id }
        }
        // Les Réglages bloquent le changement de langue (redémarrage) pendant un test ou une partie.
        .onChange(of: isBusy) { activity.busy = isBusy }
    }

    /// Page réellement affichée : sans utilisateur, la fiche et les tests laissent place au guide.
    private var shownPage: AppPage {
        switch page {
        case .user, .newTest, .kidMode:
            return selectedUser == nil ? .onboarding : page
        default:
            return page
        }
    }

    /// Test ou partie en cours.
    private var isBusy: Bool { runner != nil || mosquito != nil || pitch != nil }

    /// Test ou partie en cours (plein écran).
    @ViewBuilder
    private var fullScreenPage: some View {
        if let runner {
            if runner.config.kidMode {
                KidTestView(runner: runner,
                            userName: store.user(runner.config.userID)?.name ?? "",
                            onClose: { session in closeTest(runner: runner, session: session) })
            } else {
                TestView(runner: runner,
                         userName: store.user(runner.config.userID)?.name ?? "",
                         onClose: { session in closeTest(runner: runner, session: session) })
            }
        } else if let mosquito {
            MosquitoView(game: mosquito,
                         playerName: store.user(mosquito.config.userID)?.name ?? "",
                         onClose: { result in
                             mosquitoResult = result
                             selectedUserID = mosquito.config.userID
                             self.mosquito = nil
                         })
                .id(ObjectIdentifier(mosquito))
        } else if let pitch {
            PitchView(game: pitch,
                      playerName: store.user(pitch.config.userID)?.name ?? "",
                      onClose: { result in
                          pitchResult = result
                          selectedUserID = pitch.config.userID
                          self.pitch = nil
                      })
                .id(ObjectIdentifier(pitch))
        }
    }

    /// La liste des utilisateurs n'est surlignée que sur la fiche : ailleurs,
    /// c'est l'entrée du menu qui l'est. Cliquer un utilisateur ouvre sa fiche.
    private var sidebarSelection: Binding<UUID?> {
        Binding(
            get: { page == .user ? selectedUserID : nil },
            set: { id in
                guard let id else { return }
                selectedUserID = id
                page = .user
            }
        )
    }

    private var selectedUser: UserProfile? {
        selectedUserID.flatMap { store.user($0) }
    }

    @ViewBuilder
    private var detail: some View {
        switch shownPage {
        case .onboarding:
            onboarding
        case .faq:
            FAQView()
        case .readingGuide:
            ReadingGuideView(onBack: selectedUser == nil ? nil : { page = .user })
        case .addUser:
            AddUserPage(canCancel: !store.data.users.isEmpty,
                        onCreate: { name, year in
                            selectedUserID = store.addUser(name: name, birthYear: year)
                            page = .user
                        },
                        onCancel: { page = .user })
        case .newTest:
            if let user = selectedUser {
                NewTestPage(user: user, suggestedLength: suggestedLength, kidMode: false,
                            selection: $selectedUserID,
                            onCancel: { page = .user },
                            onStart: { config in runner = TestRunner(config: config) })
                    .id(user.id)
            } else {
                onboarding
            }
        case .kidMode:
            if let user = selectedUser {
                NewTestPage(user: user, kidMode: true,
                            selection: $selectedUserID,
                            onCancel: nil,
                            onStart: { config in runner = TestRunner(config: config) })
                    .id(user.id)
            } else {
                onboarding
            }
        case .mosquito:
            MosquitoHomeView(selection: $selectedUserID,
                             result: mosquitoResult,
                             onPlay: { config in
                                 mosquitoResult = nil
                                 mosquito = MosquitoGame(config: config)
                             },
                             onAddUser: { page = .addUser })
        case .pitch:
            PitchHomeView(selection: $selectedUserID,
                          result: pitchResult,
                          onPlay: { config in
                              pitchResult = nil
                              pitch = PitchGame(config: config)
                          },
                          onAddUser: { page = .addUser })
        case .user:
            if let user = selectedUser {
                UserDetailView(user: user,
                               onNewTest: { length in openNewTest(length: length) },
                               onOpenGame: { open($0) },
                               onReadingGuide: { page = .readingGuide })
                    .id(user.id)
            } else {
                onboarding
            }
        }
    }

    /// Guide Découvrir Tympan. Passer ou finir le marque comme vu ; sans utilisateur, on va le créer.
    private var onboarding: some View {
        OnboardingView(step: $onboardingStep,
                       hasUsers: !store.data.users.isEmpty,
                       onSkip: {
                           Onboarding.markSeen()
                           page = store.data.users.isEmpty ? .addUser : .user
                       },
                       onFinish: {
                           Onboarding.markSeen()
                           if store.data.users.isEmpty {
                               page = .addUser
                           } else {
                               openNewTest(length: nil)
                           }
                       })
    }

    private func openOnboarding() {
        onboardingStep = .welcome
        page = .onboarding
    }

    private func open(_ target: AppPage) {
        if selectedUserID == nil { selectedUserID = store.data.users.first?.id }
        page = target
    }

    /// Configuration d'un audiogramme pour l'utilisateur sélectionné.
    private func openNewTest(length: TestLength?) {
        if selectedUserID == nil { selectedUserID = store.data.users.first?.id }
        guard selectedUser != nil else {
            page = .addUser
            return
        }
        suggestedLength = length
        page = .newTest
    }

    private func closeTest(runner: TestRunner, session: TestSession?) {
        if let session {
            store.add(session, to: runner.config.userID)
            selectedUserID = runner.config.userID
            page = .user
        }
        self.runner = nil
    }
}

struct SidebarView: View {
    @Environment(DataStore.self) private var store
    @Binding var selection: UUID?
    var active: AppPage
    /// Zones mises en avant par le guide Découvrir Tympan.
    var highlights: Set<SidebarZone> = []
    var onAddUser: () -> Void
    var onAudiogram: () -> Void
    var onKidMode: () -> Void
    var onMosquito: () -> Void
    var onPitch: () -> Void
    var onOnboarding: () -> Void
    var onFAQ: () -> Void
    var onReadingGuide: () -> Void
    @State private var userToDelete: UserProfile?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            // En-tête : logo + nom (sous les boutons de fenêtre).
            HStack(spacing: 10) {
                TympanLogo(size: 28)
                Text(verbatim: "Tympan").font(.system(size: 19, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)
            .padding(.bottom, 10)

            // Menu : défile si la fenêtre est trop petite.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        header("Utilisateurs")
                        ForEach(store.data.users) { user in
                            userRow(user)
                        }
                        Button {
                            onAddUser()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(Theme.muted.opacity(0.6),
                                                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                                Text("Ajouter un utilisateur")
                                    .foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .guideGlow(highlights.contains(.addUser))
                    }
                    .padding(4)
                    .guideGlow(highlights.contains(.users))

                    VStack(alignment: .leading, spacing: 2) {
                        header("Exercices")
                        menuItem("Audiogramme", icon: "waveform.path.ecg", page: .newTest, action: onAudiogram)
                            .help("Nouveau test pour l'utilisateur sélectionné")
                            .guideGlow(highlights.contains(.audiogram))
                        menuItem("Mode enfant", icon: "sparkles", page: .kidMode, action: onKidMode)
                            .help("Test de l'utilisateur sélectionné, présenté en jeu")
                        menuItem("Chasse au moustique", icon: "ant", page: .mosquito, action: onMosquito)
                        menuItem("La juste note", icon: "music.note", page: .pitch, action: onPitch)
                    }
                    .padding(4)
                    .guideGlow(highlights.contains(.exercises))

                    VStack(alignment: .leading, spacing: 2) {
                        header("Aide")
                        menuItem("Découvrir Tympan", icon: "safari", page: .onboarding, action: onOnboarding)
                        menuItem("Lire un audiogramme", icon: "chart.xyaxis.line", page: .readingGuide, action: onReadingGuide)
                        menuItem("Questions fréquentes", icon: "questionmark.circle", page: .faq, action: onFAQ)
                    }
                    .padding(4)

                    VStack(alignment: .leading, spacing: 2) {
                        header("Données")
                        plainItem("Exporter les données…", icon: "square.and.arrow.up", action: exportData)
                        plainItem("Importer des données…", icon: "square.and.arrow.down", action: importData)
                    }
                    .padding(4)
                    .guideGlow(highlights.contains(.data))
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Pied : toujours visible en bas.
            VStack(alignment: .leading, spacing: 6) {
                if let error = store.lastError {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(verbatim: error)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        Button("OK") { store.lastError = nil }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .padding(10)
                    .background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accentBorder))
                }
                if let message {
                    Text(verbatim: message).font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                Text("Outil de suivi personnel. Ne remplace pas un examen chez un ORL.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: AppInfo.versionLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.muted.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .tympanExport)) { _ in exportData() }
        .onReceive(NotificationCenter.default.publisher(for: .tympanImport)) { _ in importData() }
        .confirmationDialog("Supprimer cet utilisateur et tout son historique ?",
                            isPresented: Binding(get: { userToDelete != nil }, set: { if !$0 { userToDelete = nil } }),
                            presenting: userToDelete) { user in
            Button("Supprimer \(user.name)", role: .destructive) {
                if selection == user.id { selection = nil }
                store.deleteUser(user.id)
            }
        }
    }

    private func header(_ text: LocalizedStringKey) -> some View {
        SectionLabel(text)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    /// Ligne utilisateur, surlignée quand sa fiche est affichée.
    private func userRow(_ user: UserProfile) -> some View {
        let on = selection == user.id
        return Button {
            selection = user.id
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: user.initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accentBg, in: Circle())
                Text(verbatim: user.name)
                    .foregroundStyle(on ? Theme.accent : Theme.text)
                    .fontWeight(on ? .semibold : .regular)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Supprimer…", role: .destructive) { userToDelete = user }
        }
    }

    private func plainItem(_ title: LocalizedStringKey, icon: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Entrée du menu, surlignée quand sa page est affichée.
    private func menuItem(_ title: LocalizedStringKey, icon: String, page: AppPage,
                          action: @escaping () -> Void) -> some View {
        let on = active == page
        return Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(on ? Theme.accent : Theme.text)
                .fontWeight(on ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(on ? Theme.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tympan-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = String(localized: "Export terminé.")
        } catch {
            message = String(localized: "Échec de l'export : \(error.localizedDescription)")
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try store.importFile(from: url)
            message = String(localized: "\(n) session(s) importée(s).")
        } catch {
            message = String(localized: "Fichier non reconnu.")
        }
    }
}

/// Création d'un utilisateur, en page (plus de feuille modale).
struct AddUserPage: View {
    var canCancel: Bool
    var onCreate: (String, Int) -> Void
    var onCancel: () -> Void
    @State private var name = ""
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 30
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nouvel utilisateur").font(.system(size: 28, weight: .semibold))
                Text("Chaque utilisateur a son historique d'audiogrammes et ses scores aux jeux.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            Panel(padding: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Prénom")
                        TextField("Prénom", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                            .focused($nameFocused)
                            .onSubmit(create)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Année de naissance")
                        TextField("Année", value: $birthYear, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Text("Figure seulement sur le rapport PDF.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: 560)
            HStack(spacing: 12) {
                if canCancel {
                    Button("Retour") { onCancel() }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Button("Créer") { create() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, birthYear)
    }
}

/// Page plein écran : remplit la fenêtre, et défile si la fenêtre est trop petite
/// au lieu d'imposer sa hauteur à la fenêtre (ce qui faisait déborder tout le contenu).
struct FitOrScroll<Content: View>: View {
    var minHeight: CGFloat = 720
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                content
                    .frame(width: geo.size.width, height: max(geo.size.height, minHeight))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
