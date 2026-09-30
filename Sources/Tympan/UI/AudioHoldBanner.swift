import SwiftUI

/// Bandeau affiché quand un test ou un jeu attend pour protéger les oreilles :
/// son coupé (Échap ou touche muet) ou autre son en cours sur le Mac.
struct AudioHoldBanner: View {
    let lock: VolumeLock?

    var body: some View {
        if let lock, let hold = lock.hold {
            HStack(spacing: 12) {
                Image(systemName: icon(hold))
                    .foregroundStyle(Theme.accent)
                message(hold)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                switch hold {
                case .muted:
                    Button("Reprendre") { lock.resumeSound() }
                        .buttonStyle(SecondaryButtonStyle())
                case .otherAudio:
                    Button("Continuer quand même") { lock.ignoreOtherAudio() }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Si l'app citée ne joue en fait aucun son audible.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func icon(_ hold: VolumeLock.Hold) -> String {
        switch hold {
        case .muted: return "speaker.slash"
        case .otherAudio: return "music.note"
        }
    }

    private func message(_ hold: VolumeLock.Hold) -> Text {
        switch hold {
        case .muted(let emergency):
            return emergency
                ? Text("Son coupé (Échap). Rien n'est compté pendant l'attente. Reprendre quand tu es prêt.")
                : Text("Le son du Mac est coupé. Tout attend : réactive le son ou appuie sur Reprendre.")
        case .otherAudio(let names):
            if names.isEmpty {
                return Text("Un autre son joue sur le Mac. Coupe-le : Tympan attend et reprend tout seul. Ton volume habituel est rétabli en attendant.")
            }
            let list = names.joined(separator: ", ")
            return Text("Un autre son joue sur le Mac (\(list)). Coupe-le : Tympan attend et reprend tout seul. Ton volume habituel est rétabli en attendant.")
        }
    }
}
