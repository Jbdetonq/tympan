import AppKit
import SwiftUI

struct TestView: View {
    var runner: TestRunner
    let userName: String
    var onClose: (TestSession?) -> Void

    @State private var keyMonitor: Any?
    @State private var confirmStop = false
    @State private var pressFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if let error = runner.errorMessage {
                InfoBanner(text: LocalizedStringKey(error))
                Spacer()
            } else if runner.phase == .finished, let session = runner.result {
                TestSummaryView(session: session) { note in
                    var saved = session
                    saved.note = TestSession.cleanNote(note)
                    onClose(saved)
                }
            } else {
                chain
                AudioHoldBanner(lock: runner.volumeLock)
                if runner.noisy {
                    InfoBanner(text: "Pièce bruyante : le test continue, mais cette session sera exclue des comparaisons.")
                }
                if runner.outputChanged {
                    InfoBanner(text: "La sortie audio a changé (casque débranché ?). Rebranche-le puis appuie sur Reprendre.")
                }
                if runner.headphonesOnSpeaker {
                    InfoBanner(text: "Le son sort par les haut-parleurs du Mac. Branche ton casque puis relance le test.")
                }
                HStack(alignment: .top, spacing: 24) {
                    timePanel
                    sidePanel.frame(width: 280)
                }
                respondButton
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .onAppear {
            runner.start()
            installKeyMonitor()
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
        }
        .onChange(of: runner.pressCount) {
            // Retour visuel de chaque appui (sans jamais dire s'il y avait un bip).
            pressFlash = true
            Task {
                try? await Task.sleep(for: .milliseconds(160))
                pressFlash = false
            }
        }
        .confirmationDialog("Arrêter le test ? Les résultats ne seront pas enregistrés.", isPresented: $confirmStop) {
            Button("Arrêter", role: .destructive) {
                runner.cancel()
                onClose(nil)
            }
        }
    }

    // Espace = j'entends, P = pause.
    private func installKeyMonitor() {
        let r = runner
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Test fini : le clavier sert au commentaire (espace, P...).
            if MainActor.assumeIsolated({ r.phase == .finished }) { return event }
            if event.keyCode == 49 {
                if !event.isARepeat {
                    MainActor.assumeIsolated { r.respond() }
                }
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "p" {
                MainActor.assumeIsolated { r.togglePause() }
                return nil
            }
            return event
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Test en cours · \(userName)").font(.system(size: 24, weight: .semibold))
                Text("Appuie dès que tu entends un bip, même très faible.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if runner.phase != .finished {
                Button(runner.isPaused ? "Reprendre" : "Pause") { runner.togglePause() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Arrêter") {
                    if runner.phase >= .measuring { confirmStop = true } else { runner.cancel(); onClose(nil) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Chaîne de modules

    private enum StepState { case done, active, pending }

    private func state(for phase: TestRunner.Phase) -> StepState {
        if runner.phase == phase { return .active }
        return runner.phase > phase ? .done : .pending
    }

    private var chain: some View {
        HStack(spacing: 0) {
            step(title: "Casque", state: state(for: .headphones)) {
                Text(verbatim: runner.config.headphone.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(verbatim: "Volume verrouillé \(Int(runner.config.headphone.volume * 100)) %")
                    .font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            arrow(active: runner.phase == .ambient)
            step(title: "Bruit ambiant", state: state(for: .ambient)) {
                NoiseMeterBar(level: runner.ambientLevel, threshold: TestRunner.noisyThreshold)
                Text(verbatim: noiseCaption).font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            arrow(active: runner.phase == .measuring)
            step(title: "Mesure", state: state(for: .measuring)) {
                Text(runner.phase == .measuring ? "En cours" : (runner.phase > .measuring ? "Terminée" : "En attente"))
                    .font(.system(size: 14, weight: .semibold))
                ProgressBar(value: runner.phase >= .measuring ? runner.measureProgress : 0)
            }
            arrow(active: runner.phase == .verifying)
            step(title: "Vérification", state: runner.config.length.includesRetest ? state(for: .verifying) : .pending) {
                Text(runner.config.length.includesRetest ? "Contrôle de cohérence" : "Non incluse (test rapide)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(runner.phase >= .verifying ? Theme.text : Theme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var noiseCaption: String {
        if runner.micUnavailable { return "Micro indisponible" }
        guard let l = runner.ambientLevel else { return runner.phase == .ambient ? "Écoute de la pièce..." : "" }
        return "\(runner.noisy ? "Bruyant" : "Calme") · \(Int(l)) dB rel."
    }

    private func step<Content: View>(title: LocalizedStringKey, state: StepState,
                                     @ViewBuilder content: () -> Content) -> some View {
        let border: Color = state == .active ? Theme.accent : (state == .done ? Color(hex: 0x1F5A3A) : Theme.border)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title, color: state == .active ? Theme.accent : Theme.muted)
                Spacer()
                if state == .done {
                    Circle().fill(Theme.ok).frame(width: 8, height: 8)
                }
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(state == .active ? Color(hex: 0x1C1A15) : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border))
    }

    private func arrow(active: Bool) -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Theme.accent : Theme.borderStrong)
            .frame(width: 36)
    }

    // MARK: Temps écoulé

    private var timePanel: some View {
        Panel(padding: 28) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SectionLabel("Temps écoulé", color: Theme.secondary)
                    Spacer()
                    if runner.isPaused {
                        Text("En pause").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(verbatim: Format.minutes(Date().timeIntervalSince(runner.startDate)))
                            .font(Theme.mono(110, .semibold))
                            .monospacedDigit()
                    }
                    Text("min").font(.system(size: 20)).foregroundStyle(Theme.muted)
                }
                StepsProgress(runner: runner)
                HStack(spacing: 10) {
                    Image(systemName: "pause.circle").foregroundStyle(Theme.muted)
                    Text("Pause : touche P. Couper le son tout de suite : Échap.")
                        .foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 14))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panelDeep, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var sidePanel: some View {
        VStack(spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Essais pièges")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(runner.catchTotal - runner.catchFalseAlarms)/\(runner.catchTotal)")
                            .font(Theme.mono(30, .semibold))
                        Text("ignorés").foregroundStyle(runner.catchFalseAlarms == 0 ? Theme.ok : Theme.accent)
                    }
                    Text(verbatim: runner.spuriousPresses == 0
                         ? "Aucun appui dans le vide"
                         : "\(runner.spuriousPresses) appui(s) sans bip")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("C'est normal")
                    Text("Certains bips sont trop faibles pour être entendus : le test cherche ta limite. N'appuie que si tu entends vraiment quelque chose.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Astuce")
                    Text("Les bips arrivent au hasard, à droite ou à gauche. Garde les yeux fermés si ça t'aide à te concentrer.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var respondButton: some View {
        Button {
            runner.respond()
        } label: {
            HStack(spacing: 20) {
                Text("J'entends").font(.system(size: 30, weight: .semibold))
                Keycap(text: "ESPACE")
            }
            .frame(maxWidth: .infinity, minHeight: 104)
        }
        .buttonStyle(BigRespondStyle(flash: pressFlash))
        .disabled(runner.phase < .measuring || runner.isPaused)
    }
}

/// Gros bouton "J'entends" : il s'enfonce et passe au vert à chaque appui (souris ou Espace).
struct BigRespondStyle: ButtonStyle {
    var flash = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let down = flash || configuration.isPressed
        let fill = down ? Theme.ok : Theme.accent
        return configuration.label
            .foregroundStyle(Theme.onAccent)
            .background(fill.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: fill.opacity(isEnabled ? (down ? 0.35 : 0.18) : 0), radius: down ? 28 : 20)
            .scaleEffect(down ? 0.98 : 1)
            .offset(y: down ? 3 : 0)
            .animation(.easeOut(duration: 0.1), value: down)
            .contentShape(Rectangle())
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

struct NoiseMeterBar: View {
    let level: Double?
    let threshold: Double

    var body: some View {
        // 10 segments de 30 à 60 dB relatifs.
        let lit = level.map { Int((($0 - 30) / 3).rounded(.down)) + 1 } ?? 0
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: i, lit: lit))
                    .frame(height: 12)
            }
        }
    }

    private func color(for i: Int, lit: Int) -> Color {
        let segmentLevel = 30 + Double(i) * 3
        if i < lit {
            return segmentLevel >= threshold ? Theme.accent : Theme.ok
        }
        return segmentLevel >= threshold ? Color(hex: 0x3A2F16) : Theme.border
    }
}

struct StepsProgress: View {
    var runner: TestRunner

    var body: some View {
        let setupDone = runner.phase > .headphones
        let noiseDone = runner.phase > .ambient
        let measure = runner.phase >= .measuring ? runner.measureProgress : 0
        VStack(spacing: 10) {
            GeometryReader { geo in
                let unit = (geo.size.width - 18) / 18
                HStack(spacing: 6) {
                    segment(fill: setupDone ? 1 : 0.4, color: setupDone ? Theme.ok : Theme.accent, width: unit)
                    segment(fill: noiseDone ? 1 : (setupDone ? 0.4 : 0), color: noiseDone ? Theme.ok : Theme.accent, width: unit)
                    segment(fill: measure, color: runner.phase == .finished ? Theme.ok : Theme.accent, width: unit * 16)
                }
            }
            .frame(height: 14)
            GeometryReader { geo in
                let unit = (geo.size.width - 18) / 18
                HStack(spacing: 6) {
                    SectionLabel("Casque").frame(width: unit, alignment: .leading).lineLimit(1)
                    SectionLabel("Bruit").frame(width: unit, alignment: .leading).lineLimit(1)
                    SectionLabel("Mesure", color: runner.phase >= .measuring ? Theme.accent : Theme.muted)
                        .frame(width: unit * 16, alignment: .leading)
                }
            }
            .frame(height: 16)
        }
    }

    private func segment(fill: Double, color: Color, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Theme.border)
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: width * min(max(fill, 0), 1))
        }
        .frame(width: max(width, 0))
    }
}

struct TestSummaryView: View {
    let session: TestSession
    /// Reçoit le commentaire saisi.
    var onDone: (String) -> Void
    @State private var note = ""

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Panel(padding: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Résultat", color: Theme.secondary)
                    AudiogramChart(session: session)
                        .frame(minHeight: 320)
                    AudiogramLegend(showReference: false)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("Test terminé").font(.system(size: 28, weight: .semibold))
                if let r = session.reliability {
                    summaryLine(ok: r >= 0.8,
                                text: "Essais pièges ignorés : \(Int((r * 100).rounded())) %")
                }
                if session.spuriousPresses > 3 {
                    summaryLine(ok: false, text: "\(session.spuriousPresses) appuis sans bip : résultat moins fiable")
                }
                if let shift = session.retestShift {
                    summaryLine(ok: shift <= 10,
                                text: shift <= 10 ? "Vérification 1 kHz cohérente" : "Vérification 1 kHz : écart de \(shift) dB")
                }
                if session.noisy {
                    summaryLine(ok: false, text: "Pièce bruyante : session exclue des comparaisons")
                }
                Spacer()
                SessionNoteField(text: $note)
                Button("Enregistrer et voir l'historique") { onDone(note) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: 320)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func summaryLine(ok: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(ok ? Theme.ok : Theme.accent)
            Text(verbatim: text).foregroundStyle(Theme.secondary)
        }
        .font(.system(size: 14))
    }
}
