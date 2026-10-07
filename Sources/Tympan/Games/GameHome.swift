import SwiftUI

// Éléments communs aux pages d'accueil des jeux (moustique, juste note)
// et au mode enfant : choix du joueur, du casque, bandeau de résultat.

/// Résultat d'une partie de chasse au moustique, affiché en bandeau au retour sur la page d'accueil.
struct MosquitoResult: Equatable {
    let userID: UUID
    let best: Int?
    let previousBest: Int?
    let won: Bool
    /// Conseil tiré à la fin de la partie, fixe tant que le bandeau est affiché.
    var tip = HearingTips.random()

    var isNewRecord: Bool {
        guard let best else { return false }
        return previousBest.map { best > $0 } ?? true
    }
}

/// Résultat d'une partie complète de « La juste note ».
struct PitchResult: Equatable {
    let userID: UUID
    let level: PitchLevel
    let stars: Int
    let meanError: Double?
    let meanBias: Double?
    let previousBest: PitchRecord?
    let isNewRecord: Bool
    var tip = HearingTips.random()
}

/// Joueur = utilisateur sélectionné dans la barre latérale, modifiable sur place.
struct PlayerPicker: View {
    @Environment(DataStore.self) private var store
    @Binding var selection: UUID?

    var body: some View {
        if !store.data.users.isEmpty {
            HStack(spacing: 8) {
                Text("Joueur").foregroundStyle(Theme.muted)
                Picker("Joueur", selection: $selection) {
                    ForEach(store.data.users) { u in
                        Text(verbatim: u.name).tag(Optional(u.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .font(.system(size: 14))
        }
    }
}

/// Profil casque du jeu (le jeu reprend son volume) et sortie audio active.
struct GameHeadphoneField: View {
    @Environment(DataStore.self) private var store
    let userID: UUID?
    @Binding var headphoneID: UUID?
    @State private var deviceName = ""
    @State private var onSpeaker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Profil casque")
            if store.data.headphones.isEmpty {
                Text("Crée d'abord un profil casque en lançant un test : le jeu reprend son volume.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Profil casque", selection: $headphoneID) {
                    ForEach(store.data.headphones) { h in
                        Text("\(h.name) · volume \(Int(h.volume * 100)) %").tag(Optional(h.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 340)
            }
            status
        }
        .onAppear {
            if let d = SystemAudio.defaultOutputDevice() {
                deviceName = SystemAudio.name(of: d)
                onSpeaker = SystemAudio.isBuiltInSpeaker(d)
            }
            if store.headphone(headphoneID) == nil { pickDefault() }
        }
        .onChange(of: userID) { pickDefault() }
    }

    /// Casque du dernier test du joueur, sinon le premier profil.
    private func pickDefault() {
        let last = userID.flatMap { store.user($0) }?.sortedSessions.first?.headphoneID
        headphoneID = last ?? store.data.headphones.first?.id
    }

    @ViewBuilder
    private var status: some View {
        if onSpeaker {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.accent)
                Text("Aucun casque détecté : branche ton casque.")
                    .foregroundStyle(Theme.accent)
            }
            .font(.system(size: 13))
        } else if !deviceName.isEmpty {
            HStack(spacing: 8) {
                Circle().fill(Theme.ok).frame(width: 8, height: 8)
                Text("Sortie active : \(deviceName)")
                    .foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 13))
        }
    }
}

/// Bandeau de fin de partie, en haut de la page d'accueil du jeu.
struct GameResultBanner<Content: View>: View {
    var color: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 20) { content }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.55), lineWidth: 1.5))
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Marche de podium numérotée.
struct PodiumStep: View {
    let place: Int
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Neon.card)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Neon.cardBorder))
            .overlay(
                Text(verbatim: "\(place)")
                    .font(Theme.mono(place == 1 ? 30 : 24, .semibold))
                    .foregroundStyle(place == 1 ? Neon.yellow : Theme.secondary)
            )
            .frame(height: height)
    }
}

/// Bas de page d'un jeu : joueur, casque, bouton Jouer.
struct GamePlayBar: View {
    @Environment(DataStore.self) private var store
    @Binding var selection: UUID?
    @Binding var headphoneID: UUID?
    var color: Color
    var onPlay: () -> Void
    var onAddUser: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            if store.data.users.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Joueur")
                    Button("Ajouter un utilisateur") { onAddUser() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Joueur")
                    Picker("Joueur", selection: $selection) {
                        ForEach(store.data.users) { u in
                            Text(verbatim: u.name).tag(Optional(u.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }
            GameHeadphoneField(userID: selection, headphoneID: $headphoneID)
            Spacer(minLength: 0)
            Button {
                onPlay()
            } label: {
                Label("Jouer", systemImage: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }
            .buttonStyle(NeonButtonStyle(color: color))
            .keyboardShortcut(.defaultAction)
            .disabled(!canPlay)
            .opacity(canPlay ? 1 : 0.4)
        }
        .padding(22)
        .background(Neon.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Neon.cardBorder))
    }

    private var canPlay: Bool {
        selection.flatMap { store.user($0) } != nil && store.headphone(headphoneID) != nil
    }
}
