import SwiftUI

/// Phrases de prévention auditive et « Le savais-tu ? », affichées sous le bandeau de fin
/// de tous les exercices. Une phrase est tirée au hasard à chaque fin de partie.
struct HearingTip: Equatable {
    /// Conseil de prévention ou anecdote (« Le savais-tu ? »).
    enum Kind { case prevention, fact }
    /// Source citée sous la phrase, avec un lien.
    enum Source: Equatable { case agiSon }

    /// Texte français, qui sert aussi de clé de traduction (en.lproj). Pas de % dans les
    /// traductions : le texte est chargé dynamiquement.
    let text: String
    let kind: Kind
    var source: Source?
}

/// Toutes les phrases, et l'« âge des oreilles » de la chasse au moustique.
enum HearingTips {
    static let all: [HearingTip] = [
        // Prévention
        .init(text: "Au casque, pense à la règle 60/60 : 60 % du volume, 60 minutes, puis une pause.", kind: .prevention),
        .init(text: "Les cellules de ton oreille interne ne repoussent pas. Prends-en soin.", kind: .prevention),
        .init(text: "Tes oreilles sifflent après une soirée ? Elles te demandent du repos.", kind: .prevention),
        .init(text: "Si tu dois crier pour parler à quelqu'un à un mètre, le bruit est dangereux.", kind: .prevention),
        .init(text: "Les aigus sont les premiers à s'en aller, avec l'âge comme avec le bruit.", kind: .prevention),
        .init(text: "Teste-toi de temps en temps. Si tu perds beaucoup d'aigus d'un coup, parles-en à un ORL.", kind: .prevention),
        .init(text: "Baisser le son de 3 dB, c'est pouvoir écouter deux fois plus longtemps sans risque.", kind: .prevention),
        .init(text: "À 100 dB, le niveau d'un concert, l'oreille tient environ 15 minutes par jour sans risque.", kind: .prevention),
        .init(text: "En France, un concert ne doit pas dépasser 102 dB en moyenne sur 15 minutes.", kind: .prevention),
        .init(text: "Avec un casque à réduction de bruit, tu écoutes moins fort dans le train ou le métro.", kind: .prevention),
        .init(text: "Après un concert, une journée au calme aide tes oreilles à récupérer.", kind: .prevention),
        .init(text: "Un sifflement qui ne part pas s'appelle un acouphène. Parles-en à un ORL.", kind: .prevention),
        .init(text: "Une baisse d'audition brutale, c'est une urgence : consulte vite.", kind: .prevention),
        .init(text: "Le coton-tige pousse le cérumen au fond de l'oreille. Le coin d'une serviette suffit.", kind: .prevention),
        .init(text: "L'usure de l'audition avec l'âge a un nom : la presbyacousie.", kind: .prevention),
        // AGI-SON, campagne Ear We Are (earweare.org)
        .init(text: "Pour que la musique reste un plaisir, préservons notre audition.", kind: .prevention, source: .agiSon),
        .init(text: "En concert, fais des pauses.", kind: .prevention, source: .agiSon),
        .init(text: "Évite d'enchaîner les expositions à des volumes sonores élevés.", kind: .prevention, source: .agiSon),
        .init(text: "Éloigne-toi des enceintes.", kind: .prevention, source: .agiSon),
        .init(text: "Pense aux bouchons d'oreilles, et retire-les au calme.", kind: .prevention, source: .agiSon),
        .init(text: "Protège les enfants : casque, pauses et loin des enceintes.", kind: .prevention, source: .agiSon),
        .init(text: "Sifflements ou bourdonnements : ce sont des acouphènes.", kind: .prevention, source: .agiSon),
        .init(text: "Forte douleur au moindre son : c'est de l'hyperacousie.", kind: .prevention, source: .agiSon),
        .init(text: "Du mal à suivre une conversation ? C'est peut-être de la surdité.", kind: .prevention, source: .agiSon),
        .init(text: "Des symptômes encore là après un concert et une nuit de repos ? Va aux urgences ORL dans les 24 h.", kind: .prevention, source: .agiSon),
        .init(text: "Plus tôt on s'expose, plus tôt on risque de moins bien entendre !", kind: .prevention, source: .agiSon),
        // Le savais-tu ?
        .init(text: "Un vrai moustique bourdonne entre 400 et 700 Hz, bien plus grave que celui du jeu.", kind: .fact),
        .init(text: "Un chien entend jusqu'à environ 45 kHz, un chat jusqu'à plus de 60 kHz.", kind: .fact),
        .init(text: "Les chauves-souris entendent au-delà de 100 kHz.", kind: .fact),
        .init(text: "Une oreille jeune entend jusqu'à environ 20 kHz.", kind: .fact),
        .init(text: "Un chuchotement fait environ 30 dB, une conversation 60 dB, un marteau-piqueur 100 dB.", kind: .fact),
    ]

    static func random() -> HearingTip { all.randomElement()! }

    static let agiSonURL = URL(string: "https://earweare.org/")!

    /// « Âge des oreilles » d'après le moustique le plus aigu attrapé. Tranches reprises des
    /// tests grand public : pour s'amuser, jamais présenté comme une mesure.
    static func earAge(for hz: Int) -> LocalizedStringKey {
        switch hz {
        case ..<10000: return "Tu as des oreilles de plus de 60 ans."
        case ..<12000: return "Tu as des oreilles de 50 à 60 ans."
        case ..<14000: return "Tu as des oreilles de 40 à 50 ans."
        case ..<15000: return "Tu as des oreilles de 30 à 40 ans."
        case ..<16000: return "Tu as des oreilles de 25 à 30 ans."
        case ..<17250: return "Tu as des oreilles de 20 à 25 ans."
        case ..<19000: return "Tu as des oreilles d'ado !"
        default: return "Tu as des oreilles de chauve-souris !"
        }
    }
}

/// Carte de conseil sous le bandeau de fin, avec la source quand elle existe.
struct HearingTipCard: View {
    let tip: HearingTip
    var color: Color = Neon.pink

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tip.kind == .fact ? "lightbulb" : "ear")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(tip.kind == .fact ? "Le savais-tu ?" : "Prends soin de tes oreilles", color: color)
                Text(LocalizedStringKey(tip.text))
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                if tip.source == .agiSon {
                    Link(destination: HearingTips.agiSonURL) {
                        Text("Conseil AGI-SON, campagne Ear We Are")
                            .font(.system(size: 12))
                            .underline()
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Neon.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Neon.cardBorder))
        .transition(.opacity)
    }
}
