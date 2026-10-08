import SwiftUI

/// Guide « Découvrir Tympan » : affiché au premier lancement, et tant qu'il n'y a aucun utilisateur.
/// Toujours accessible par Aide > Découvrir Tympan (barre latérale et menu Aide).
enum Onboarding {
    private static let key = "tympan.onboardingSeen"

    /// Faux au premier lancement : le guide s'ouvre tout seul.
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// Zones de la barre latérale que le guide fait briller.
enum SidebarZone: Hashable {
    case users, addUser, exercises, audiogram, data
}

/// Étapes du guide. Chacune montre dans la barre latérale où se trouve ce dont elle parle.
enum OnboardingStep: Int, CaseIterable {
    case welcome, users, headphones, exercises, start

    /// Zones à faire briller à cette étape.
    func highlights(hasUsers: Bool) -> Set<SidebarZone> {
        switch self {
        case .welcome: return []
        case .users: return [.users, .data]
        case .headphones: return [.audiogram]
        case .exercises: return [.exercises]
        case .start: return hasUsers ? [.audiogram] : [.addUser]
        }
    }
}

extension View {
    /// Zone de la barre latérale montrée par le guide : cadre ambre lumineux.
    func guideGlow(_ on: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(on ? 0.07 : 0)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accent.opacity(on ? 1 : 0), lineWidth: 1.5)
                    .shadow(color: Theme.accent.opacity(on ? 0.35 : 0), radius: 8)
            )
            .animation(.easeInOut(duration: 0.25), value: on)
    }
}

/// Page du guide : en-tête, étape en cours, navigation (Précédent, points, Suivant).
struct OnboardingView: View {
    /// Étape gardée par ContentView, qui en déduit les zones à faire briller.
    @Binding var step: OnboardingStep
    var hasUsers: Bool
    var onSkip: () -> Void
    /// Dernière étape : créer un profil (aucun utilisateur) ou faire un test.
    var onFinish: () -> Void

    /// Langue choisie sur la première étape ; Redémarrer n'apparaît que si elle change.
    @State private var language = LanguageChoice.saved
    private let appliedLanguage = LanguageChoice.saved

    var body: some View {
        FitOrScroll(minHeight: 600) {
            VStack(alignment: .leading, spacing: 18) {
                header
                stage
                footer
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }

    // MARK: Cadre

    private var header: some View {
        HStack(spacing: 10) {
            SectionLabel("Découvrir Tympan")
            Text("Étape \(step.rawValue + 1) sur \(OnboardingStep.allCases.count)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
            Spacer()
            if step != .start {
                Button("Passer", action: onSkip)
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(height: 32)
    }

    private var stage: some View {
        Group {
            switch step {
            case .welcome: welcome
            case .users: users
            case .headphones: headphones
            case .exercises: exercises
            case .start: start
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .id(step)
        .transition(.opacity)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            HStack {
                if step != .welcome {
                    Button("Précédent") { move(-1) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(width: 160, alignment: .leading)
            Spacer()
            HStack(spacing: 10) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { step = s }
                    } label: {
                        Capsule()
                            .fill(s == step ? Theme.accent : Theme.borderStrong)
                            .frame(width: s == step ? 26 : 8, height: 8)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Aller à l'étape \(s.rawValue + 1)"))
                }
            }
            Spacer()
            HStack {
                if step != .start {
                    Button("Suivant") { move(1) }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 160, alignment: .trailing)
        }
    }

    /// Étape précédente (-1) ou suivante (+1).
    private func move(_ delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    // MARK: Étapes

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            columns {
                TympanLogo(size: 150)
                    .shadow(color: Theme.accent.opacity(0.25), radius: 30)
            } text: {
                title("Bienvenue dans Tympan")
                lead("Tympan suit ton audition dans le temps. Tu fais un test chez toi, avec ton casque, puis tu le refais de temps en temps. L'app te dit si quelque chose a bougé.")
                VStack(alignment: .leading, spacing: 12) {
                    point("**Un suivi, pas un diagnostic.** Tympan ne remplace pas un examen chez un ORL.") {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.accent)
                    }
                    point("**Tout reste sur ton Mac.** Aucun compte, aucune connexion.") {
                        Image(systemName: "lock")
                            .foregroundStyle(Theme.ok)
                    }
                    point("**Échap coupe le son tout de suite.** Pendant un test comme pendant un jeu.") {
                        Text(verbatim: "esc")
                            .font(Theme.mono(10, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.borderStrong))
                    }
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            languageRow
        }
    }

    /// Choix de la langue, comme dans les Réglages : l'app redémarre et le guide se rouvre.
    private var languageRow: some View {
        HStack(spacing: 14) {
            SectionLabel("Langue")
            Picker("Langue", selection: $language) {
                Text("Suivre le système").tag(LanguageChoice.system)
                ForEach(LanguageChoice.available, id: \.self) { code in
                    Text(verbatim: LanguageChoice.displayName(code)).tag(code)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            if language != appliedLanguage {
                Button("Redémarrer") {
                    LanguageChoice.save(language)
                    LanguageChoice.relaunch()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Text("Tympan redémarre pour changer de langue.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var users: some View {
        columns {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    avatar(Theme.accent, Theme.accentBg)
                    avatar(Theme.left, Theme.left.opacity(0.16))
                    avatar(Theme.ok, Theme.okBg)
                }
                MiniAudiogram()
                    .frame(height: 120)
                    .padding(12)
                    .background(Theme.panelDeep, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0x23262C)))
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.accent)
                    Text("Écart à vérifier, oreille droite.")
                        .foregroundStyle(Theme.accentSoft)
                }
                .font(.system(size: 12))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accentBorder))
            }
        } text: {
            title("Un profil par personne")
            lead("Toute la famille peut utiliser le même Mac. Chacun a sa fiche, avec son audiogramme et son historique.")
            VStack(alignment: .leading, spacing: 14) {
                numbered(1, "**Ton premier test Moyen ou Complet devient la référence.** Les tests suivants lui sont comparés.")
                numbered(2, "**Si une fréquence bouge, un bandeau te prévient.** Tu sais alors s'il faut refaire un test ou en parler à un médecin.")
                numbered(3, "**Tu changes de Mac ?** Exporte tes données, puis importe-les sur l'autre.")
            }
        }
    }

    private var headphones: some View {
        columns {
            VStack(spacing: 20) {
                Image(systemName: "headphones")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(Theme.text)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Mon casque").fontWeight(.medium)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                        Text(verbatim: 0.5.formatted(.percent.locale(AppLocale.current)))
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<16, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i < 8 ? Theme.accent : Color(hex: 0x2A2D33))
                                .frame(height: 8)
                        }
                    }
                    Text("Volume verrouillé pendant le test")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(14)
                .background(Theme.panelDeep, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0x23262C)))
            }
        } text: {
            title("Toujours le même casque")
            lead("Tympan ne mesure pas en dB médicaux. Il compare tes tests entre eux, donc le matériel doit rester le même.")
            VStack(alignment: .leading, spacing: 14) {
                numbered(1, "**Un profil casque, c'est un casque et un volume.** Tu le crées au premier test, avec le bip de réglage.")
                numbered(2, "**Pendant le test, ce volume est verrouillé.** Ton volume habituel revient à la fin.")
                numbered(3, "**Seuls les tests faits avec le même profil sont comparés.** Nouveau casque, nouveau suivi.")
            }
        }
    }

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                title("Des exercices pour tous")
                lead("Trois façons de faire travailler tes oreilles, seul ou en famille.")
            }
            HStack(alignment: .top, spacing: 16) {
                gameCard("Mode enfant",
                         "Un vrai test, présenté comme un jeu. Un animal apparaît à chaque son trouvé. Environ 2 minutes.",
                         tag: "Compte dans l'audiogramme",
                         color: Neon.mint, soft: Color(hex: 0x8DFFD0), tagBackground: Neon.mintBg) {
                    AnimalIcon(animal: .cat, color: Neon.mint)
                        .frame(width: 72, height: 72)
                        .neonGlow(Neon.mint, radius: 4)
                }
                gameCard("Chasse au moustique",
                         "Trouve le bocal où se cache le moustique. Il monte dans les aigus jusqu'à ta limite.",
                         tag: "Podium",
                         color: Neon.pink, soft: Neon.pinkSoft, tagBackground: Neon.pinkBg) {
                    ZStack {
                        JarShape()
                            .stroke(Neon.pink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                        MosquitoIcon()
                            .frame(width: 34)
                            .offset(y: 10)
                    }
                    .frame(width: 58, height: 72)
                    .neonGlow(Neon.pink, radius: 4)
                }
                gameCard("La juste note",
                         "Une note sonne, retrouve-la avec le curseur. Trois niveaux, un podium par niveau.",
                         tag: "Podium par niveau",
                         color: Neon.cyan, soft: Neon.cyanSoft, tagBackground: Neon.cyanBg) {
                    TuningForkIcon()
                        .frame(width: 68, height: 68)
                        .neonGlow(Neon.cyan, radius: 4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Text("Les jeux utilisent ton profil casque, à un niveau modéré. Ils ne comptent pas dans l'audiogramme.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var start: some View {
        columns {
            VStack(spacing: 10) {
                recap(1, "Un profil par personne")
                recap(2, "Toujours le même casque")
                recap(3, "Un test de temps en temps")
            }
        } text: {
            title("C'est parti")
            lead(hasUsers
                 ? "Lance un test quand tu veux depuis Exercices, Audiogramme. Prévois un endroit calme et 7 minutes."
                 : "Crée ton profil, puis lance ton premier test. Prévois un endroit calme et 7 minutes.")
            Button(action: onFinish) {
                Text(hasUsers ? "Faire un test" : "Créer mon profil")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
            Text("Pour revoir ce guide : Aide, Découvrir Tympan.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Éléments

    /// Visuel à gauche, texte à droite.
    private func columns<Visual: View, Content: View>(@ViewBuilder visual: () -> Visual,
                                                      @ViewBuilder text: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 36) {
            visual()
                .frame(width: 230)
            VStack(alignment: .leading, spacing: 16) {
                text()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    /// Titre, chapeau, puce à icône et liste numérotée : la typographie commune des étapes.
    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lead(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 16))
            .lineSpacing(3)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func point<Icon: View>(_ text: LocalizedStringKey, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon()
                .font(.system(size: 14))
                .frame(width: 22, height: 18)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numbered(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(n)")
                .font(Theme.mono(14, .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pastille de personne (étape Utilisateurs).
    private func avatar(_ color: Color, _ background: Color) -> some View {
        Image(systemName: "person.fill")
            .font(.system(size: 16))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(background, in: Circle())
    }

    /// Rappel numéroté de la dernière étape.
    private func recap(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(n)")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.ok)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.ok, lineWidth: 1.5))
            Text(text)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.panelDeep, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0x23262C)))
    }

    /// Carte néon d'un exercice (étape Exercices).
    private func gameCard<Icon: View>(_ name: LocalizedStringKey, _ text: LocalizedStringKey,
                                      tag: LocalizedStringKey, color: Color, soft: Color,
                                      tagBackground: Color,
                                      @ViewBuilder icon: () -> Icon) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            icon()
                .frame(height: 84)
                .frame(maxWidth: .infinity)
            Text(name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(soft)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            SectionLabel(tag, color: soft)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tagBackground, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Neon.stage, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Neon.cardBorder))
    }
}

/// Petit audiogramme d'exemple : droite en rouge, gauche en bleu, référence en pointillés,
/// zone d'écart encadrée en ambre. Purement illustratif.
private struct MiniAudiogram: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 300
            let sy = size.height / 150
            let xs: [CGFloat] = [20, 70, 120, 170, 210, 245, 280]
            func line(_ ys: [CGFloat]) -> Path {
                var p = Path()
                p.addLines(zip(xs, ys).map { CGPoint(x: $0 * sx, y: $1 * sy) })
                return p
            }
            for y in [15, 55, 95, 135] as [CGFloat] {
                var g = Path()
                g.move(to: CGPoint(x: 0, y: y * sy))
                g.addLine(to: CGPoint(x: size.width, y: y * sy))
                ctx.stroke(g, with: .color(Color(hex: 0x23262C)), lineWidth: 1)
            }
            let zone = Path(roundedRect: CGRect(x: 196 * sx, y: 36 * sy, width: 64 * sx, height: 70 * sy),
                            cornerRadius: 6)
            ctx.fill(zone, with: .color(Theme.accent.opacity(0.08)))
            ctx.stroke(zone, with: .color(Theme.accent.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Ordonnées dans un repère 300 x 150 : l'oreille droite passe nettement sous la référence dans les aigus.
            let reference: [CGFloat] = [50, 50, 46, 50, 60, 68, 64]
            let left: [CGFloat] = [46, 46, 40, 48, 58, 70, 66]
            let right: [CGFloat] = [56, 50, 50, 56, 74, 92, 80]
            ctx.stroke(line(reference), with: .color(Theme.right.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            ctx.stroke(line(left), with: .color(Theme.left), lineWidth: 2)
            ctx.stroke(line(right), with: .color(Theme.right), lineWidth: 2.2)
            for (x, y) in zip(xs, right) {
                let dot = Path(ellipseIn: CGRect(x: x * sx - 4.5, y: y * sy - 4.5, width: 9, height: 9))
                ctx.fill(dot, with: .color(Theme.panelDeep))
                ctx.stroke(dot, with: .color(Theme.right), lineWidth: 2)
            }
        }
        .accessibilityLabel(Text("Exemple d'audiogramme : oreille droite en rouge, gauche en bleu, référence en pointillés"))
    }
}
