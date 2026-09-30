import SwiftUI

/// Champ de commentaire court attaché à une session (ex. « otite en cours »).
struct SessionNoteField: View {
    @Binding var text: String
    var onCommit: () -> Void = {}
    /// Couleurs : thème sombre de l'app par défaut, néon en mode enfant.
    var background: Color = Theme.raised
    var border: Color = Theme.border

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 13))
                .foregroundStyle(focused ? Theme.accent : Theme.muted)
            TextField("Commentaire (ex. : otite en cours, enfant pas concentré)", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit { focused = false; onCommit() }
                .onChange(of: text) { _, new in
                    if new.count > TestSession.noteLimit { text = String(new.prefix(TestSession.noteLimit)) }
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { onCommit() }
                }
            if focused {
                Text(verbatim: "\(text.count)/\(TestSession.noteLimit)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Theme.accentBorder : border))
    }
}

/// Commentaire d'une session de la fiche, modifiable sur place. Enregistré à la validation ou en quittant le champ.
struct SessionNoteEditor: View {
    @Environment(DataStore.self) private var store
    let userID: UUID
    let session: TestSession
    @State private var text: String

    init(userID: UUID, session: TestSession) {
        self.userID = userID
        self.session = session
        _text = State(initialValue: session.note ?? "")
    }

    var body: some View {
        SessionNoteField(text: $text) { save() }
            .onDisappear { save() }
    }

    private func save() {
        store.setNote(text, session: session.id, of: userID)
    }
}
