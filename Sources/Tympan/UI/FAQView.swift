import SwiftUI

/// Questions fréquentes : fonctionnement de l'app, choix des niveaux relatifs, références scientifiques.
struct FAQView: View {
    @State private var open: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(Array(FAQContent.sections.enumerated()), id: \.offset) { s, section in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(section.title)
                        Panel(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(section.items.enumerated()), id: \.offset) { i, item in
                                    if i > 0 {
                                        Rectangle().fill(Theme.border).frame(height: 1)
                                    }
                                    row(item, key: "\(s)-\(i)")
                                }
                            }
                        }
                    }
                }
                references
                feedback
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    /// Contact : tickets GitHub (aucune adresse personnelle publiée).
    private var feedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Une idée, un souci ?")
            Panel(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tympan est gratuit et libre, pour tout le monde, services de santé compris. Pour signaler un problème ou proposer une amélioration, ouvre un ticket sur la page du projet (un compte GitHub gratuit suffit). N'y mets jamais tes résultats ni d'informations de santé personnelles.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 20) {
                        Link(destination: AppLinks.newIssue) {
                            Label("Proposer une amélioration", systemImage: "lightbulb")
                        }
                        Link(destination: AppLinks.repository) {
                            Label("Page du projet", systemImage: "arrow.up.right.square")
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Questions fréquentes").font(.system(size: 28, weight: .semibold))
                Text("Comment marche Tympan, et sur quoi il s'appuie.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(open.isEmpty ? LocalizedStringKey("Tout déplier") : LocalizedStringKey("Tout replier")) {
                if open.isEmpty {
                    var all: Set<String> = []
                    for (s, section) in FAQContent.sections.enumerated() {
                        for i in section.items.indices { all.insert("\(s)-\(i)") }
                    }
                    open = all
                } else {
                    open = []
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func row(_ item: FAQItem, key: String) -> some View {
        let isOpen = open.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { open.remove(key) } else { open.insert(key) }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(item.question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isOpen ? Theme.accent : Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(item.answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Références")
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(FAQContent.references.enumerated()), id: \.offset) { i, ref in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: "\(i + 1)")
                                .font(Theme.mono(12, .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22, alignment: .trailing)
                            Text(ref)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

struct FAQItem {
    let question: LocalizedStringKey
    let answer: LocalizedStringKey
}

struct FAQSection {
    let title: LocalizedStringKey
    let items: [FAQItem]
}

/// Contenu de la FAQ. Pas de signe pour cent dans ces textes (interprété comme format par la localisation).
enum FAQContent {
    static let sections: [FAQSection] = [
        FAQSection(title: "Tympan", items: [
            FAQItem(question: "À quoi sert Tympan ?",
                    answer: "À suivre ton audition dans le temps. Tu fais un test de temps en temps avec le même casque, Tympan trace ton audiogramme (le son le plus faible que tu entends à chaque fréquence, oreille par oreille) et te prévient si quelque chose bouge.\n\nIl propose aussi des exercices : le mode enfant, qui est un vrai test présenté en jeu, la chasse au moustique et la juste note."),
            FAQItem(question: "Est-ce un examen médical ?",
                    answer: "Non. Tympan est un outil de suivi personnel, pas un diagnostic. Un audiogramme médical se fait en cabine insonorisée, avec un audiomètre étalonné, chez un ORL ou un audioprothésiste.\n\nSi Tympan signale un changement, ou si tu remarques une gêne (sifflement, oreille bouchée, mal à suivre une conversation), consulte."),
            FAQItem(question: "Quand consulter sans attendre ?",
                    answer: "Si tu perds de l'audition d'un coup (en quelques heures ou quelques jours), surtout d'une seule oreille, avec ou sans acouphène ou vertige : c'est une urgence. Consulte un médecin ou un ORL dans les 48 heures, sans attendre de refaire un test.\n\nMême chose pour un acouphène qui apparaît et dure, une douleur ou un écoulement. Tympan ne remplace jamais cet avis."),
            FAQItem(question: "Où sont stockées mes données ?",
                    answer: "Uniquement sur ce Mac, dans un fichier local. Rien ne part sur internet.\n\nPour passer d'un Mac à l'autre : **Données > Exporter** sur le premier, **Données > Importer** sur le second. Les historiques sont fusionnés."),
            FAQItem(question: "Comment changer la langue ?",
                    answer: "Menu **Tympan > Réglages…** (⌘,), puis choisis la langue et appuie sur **Redémarrer**. Par défaut, Tympan suit la langue du Mac, et s'affiche en anglais si elle n'est pas encore traduite.\n\nLe changement n'est pas possible pendant un test ou une partie."),
        ]),
        FAQSection(title: "Le test", items: [
            FAQItem(question: "Comment se passe un test ?",
                    answer: "1. Tu choisis ton casque et son volume. Tympan verrouille le volume pendant tout le test ; si le casque est débranché, le test se met en pause.\n2. Il écoute le bruit de la pièce pendant 3 secondes.\n3. Des bips arrivent à des moments imprévisibles, dans une oreille ou l'autre. Appuie sur **Espace** (ou clique) dès que tu entends quelque chose, même très faible. **P** met en pause, **Échap** coupe le son tout de suite.\n\nPendant le test, l'écran n'affiche ni la fréquence, ni le niveau, ni l'oreille : tu réponds à ce que tu entends, pas à ce que tu devines."),
            FAQItem(question: "Et si un son est trop fort ?",
                    answer: "Appuie sur **Échap** : le son est coupé aussitôt et le test attend. **Reprendre** relance là où tu en étais ; l'essai interrompu ne compte pas. La touche muet du clavier marche aussi.\n\nAvant de monter le volume, Tympan vérifie qu'aucun autre son ne joue sur le Mac (musique, vidéo) : il sortirait sinon au volume du test. Si un son démarre pendant le test, ton volume habituel revient et le test attend qu'il s'arrête.\n\nÀ la fin du test, en quittant l'app et même après un plantage, ton volume d'avant est rétabli."),
            FAQItem(question: "Rapide, Moyen ou Complet ?",
                    answer: "**Rapide** (environ 3 min) : 7 fréquences de 500 Hz à 8 kHz, seuil trouvé une fois. Pour un contrôle express.\n\n**Moyen** (environ 7 min, conseillé) : ajoute 250 Hz et 10 kHz, chaque seuil est confirmé 2 fois. C'est le format du suivi.\n\n**Complet** (environ 11 min) : mêmes fréquences, précision de 2 dB, seuil confirmé 3 fois.\n\nLes trois se comparent entre eux sur leurs fréquences communes. Un Rapide ne devient jamais la référence."),
            FAQItem(question: "Comment Tympan trouve-t-il mon seuil ?",
                    answer: "La méthode de référence en clinique (dite Hughson-Westlake) descend de 10 dB quand tu entends, remonte de 5 dB quand tu rates, et retient le niveau entendu plusieurs fois en montant (réf. 1, 2, 3). Fiable, mais longue.\n\nTympan garde le principe (monter quand tu n'entends pas, confirmer le seuil plusieurs fois) mais se souvient de tout : si tu as raté 40 dB, il ne redescend jamais en dessous, et il coupe en deux l'écart entre un niveau raté et un niveau entendu. C'est une recherche adaptative, une famille de méthodes classique en psychoacoustique (réf. 4). Chaque fréquence démarre aussi près du seuil de sa voisine déjà mesurée.\n\nRésultat : environ 5 bips par fréquence en Moyen, contre 11 avec la méthode clinique (simulation sur 20 000 tests). Le seuil retenu est le niveau le plus faible entendu 1, 2 ou 3 fois selon le format, avec un raté juste en dessous."),
            FAQItem(question: "Pourquoi des bips en rafale et des silences pièges ?",
                    answer: "Chaque bip est fait de 3 impulsions courtes : un son pulsé se repère plus facilement qu'un son continu, sans changer le seuil mesuré (réf. 5). Les bords de chaque impulsion sont adoucis pour qu'aucun petit clic ne trahisse le bip.\n\nLe délai entre deux bips varie au hasard (1,2 à 2,8 s) pour qu'on ne puisse pas anticiper. Environ 1 essai sur 10 est un silence : appuyer à ce moment-là compte comme une fausse alarme. Ces essais pièges donnent l'**indice de fiabilité** du test, une idée tirée de la théorie de la détection du signal (réf. 6).\n\nEn Moyen et Complet, le 1 kHz est remesuré en fin de test pour vérifier que tes réponses sont stables."),
            FAQItem(question: "Pourquoi mesurer le bruit de la pièce ?",
                    answer: "Un bruit de fond masque les sons faibles et fait paraître l'audition moins bonne qu'elle n'est. C'est pour ça que les normes d'audiométrie fixent un bruit ambiant maximal (réf. 2, 7).\n\nTympan écoute la pièce 3 secondes au micro du Mac. Si c'est trop bruyant, il te prévient sans bloquer, et la session est marquée « bruyante » : elle reste dans l'historique mais n'entre pas dans les comparaisons. Le micro n'étant pas étalonné, c'est une alerte, pas un sonomètre."),
        ]),
        FAQSection(title: "Niveaux relatifs", items: [
            FAQItem(question: "Pourquoi des « dB app » et pas des dB HL comme chez l'ORL ?",
                    answer: "Le dB HL est une échelle médicale : 0 dB HL correspond à l'audition moyenne de jeunes adultes en bonne santé. Elle est définie pour des modèles de casques précis, mesurés en laboratoire (réf. 8), et demande un audiomètre étalonné (réf. 9). Il faut savoir exactement quel niveau sonore arrive dans l'oreille.\n\nTympan ne peut pas le savoir : le même réglage donne des niveaux très différents selon le casque, la sortie du Mac et le volume. Deux casques peuvent facilement différer de 10 dB ou plus à la même fréquence.\n\nPlutôt que d'afficher des dB HL faux avec une précision trompeuse, Tympan affiche des **dB relatifs à l'app**. Ils ne disent pas « tu entends bien ou mal », ils disent « tu entends comme la dernière fois, ou moins bien ». Pour un suivi, c'est ce qui compte. Et ça évite de se prendre pour un appareil médical."),
            FAQItem(question: "Alors comment comparer mes tests ?",
                    answer: "Grâce au **profil casque** : un casque et un volume, verrouillé pendant le test. Tympan ne compare que des tests faits avec le même profil. Avec le même matériel, l'écart d'étalonnage est identique à chaque test et s'annule quand on regarde l'évolution. Nouveau casque, nouveau suivi.\n\nC'est le principe de la surveillance auditive en médecine du travail ou pendant certains traitements toxiques pour l'oreille : on compare chaque audiogramme à un audiogramme de référence de la même personne (réf. 10)."),
            FAQItem(question: "Que veut dire 0 dB app ?",
                    answer: "C'est un repère technique : 100 dB app correspond au niveau numérique maximal du Mac (0 dBFS), donc 0 dB app est 100 dB en dessous.\n\nSelon ton casque, ton seuil peut tomber à 10 ou à 40 dB app sans que ça dise quoi que ce soit sur la qualité de ton audition. Seuls les écarts entre deux tests faits avec le même profil ont du sens."),
        ]),
        FAQSection(title: "Suivi", items: [
            FAQItem(question: "C'est quoi la référence ?",
                    answer: "Le test auquel Tympan compare les suivants. Par défaut, c'est le premier Moyen ou Complet fait dans une pièce calme. Tu peux en choisir un autre par clic droit sur une session."),
            FAQItem(question: "« Écart à vérifier » ou « Baisse à signaler » ?",
                    answer: "**Baisse à signaler** : sur un Moyen ou un Complet, le seuil a monté d'au moins 10 dB sur 2 fréquences voisines. Tympan ne pose pas de diagnostic : montre ce résultat à ton médecin ou à un ORL, qui fera un vrai audiogramme.\n\n**Écart à vérifier** : +15 dB sur une seule fréquence, ou +10 dB sur 2 voisines vu par un Rapide. Tympan propose alors un test Moyen pour en avoir le cœur net.\n\nPourquoi ces chiffres : d'un test à l'autre, un seuil bouge naturellement d'environ 5 dB. Une baisse de 10 dB sur 2 fréquences voisines est un critère classique de la surveillance auditive ; pour une fréquence isolée, ces mêmes recommandations retiennent 20 dB (réf. 10). Tympan alerte dès 15 dB, mais seulement pour vérifier."),
        ]),
        FAQSection(title: "Exercices", items: [
            FAQItem(question: "Comment marche le mode enfant ?",
                    answer: "C'est un vrai test, présenté en jeu. 5 fréquences de 500 Hz à 8 kHz, une par animal, du plus grave au plus aigu : éléphant, chat, lapin, oiseau, souris. Quand le seuil d'une fréquence est trouvé, l'animal apparaît, en rouge pour l'oreille droite et en bleu pour la gauche, comme sur l'audiogramme. Si rien n'est entendu jusqu'à 70 dB app, l'animal reste endormi et le jeu continue.\n\nLe principe vient de l'audiométrie des jeunes enfants : une récompense visuelle, donnée seulement après une vraie détection, entretient l'attention (réf. 12, 13). Un appui dans le vide ne déclenche rien, pour que l'enfant n'apprenne pas à cliquer au hasard.\n\nLe test est plus court (environ 2 min) et plafonné à 70 dB app pour ménager ses oreilles. Il s'enregistre comme un test normal mais ne devient jamais la référence. Si une fréquence reste sans réponse, un message « Pour les parents » invite à consulter."),
            FAQItem(question: "Comment marche la chasse au moustique ?",
                    answer: "Elle cherche le son le plus aigu que tu entends encore. Trois bocaux s'allument l'un après l'autre, le moustique (un son aigu) se cache dans un seul : à toi de dire lequel (clic ou touches 1, 2, 3 ; **R** pour réécouter). Trouvé : le moustique monte de 500 Hz (250 Hz au-dessus de 14 kHz), jusqu'à 20 kHz. Raté : tu perds une vie sur 3.\n\nCe format s'appelle un **choix forcé** (réf. 4, 6). Son intérêt : impossible de tricher. Dire « je l'entends » ne suffit pas, il faut désigner le bon bocal, et au hasard on n'a qu'une chance sur 3.\n\nLes fréquences au-dessus de 8 kHz sont les premières à baisser avec l'âge (réf. 14). C'est pour ça que les enfants vont souvent plus haut que leurs parents.\n\nSur la page du jeu, le podium montre les trois meilleurs chasseurs du Mac : plus le record est aigu, plus le bocal est rempli de moustiques. Ce score est indicatif, il ne compte jamais dans l'audiogramme."),
            FAQItem(question: "Mon score au moustique est-il fiable ?",
                    answer: "C'est un jeu, pas une mesure. Au-dessus de 16 kHz, beaucoup de casques rendent mal les aigus, et la carte son ne peut de toute façon pas dépasser la moitié de sa fréquence d'échantillonnage (22 à 24 kHz). Le niveau est fixe et modéré (60 dB app) pour protéger les oreilles.\n\nTon score veut donc dire : la fréquence la plus haute que tu entends avec ce casque, à ce volume. Avec 3 vies, un peu de chance peut aider sur les dernières manches. Compare tes scores avec le même casque."),
        ]),
    ]

    static let references: [LocalizedStringKey] = [
        "Carhart R., Jerger J. (1959). [Preferred method for clinical determination of pure-tone thresholds](https://pubs.asha.org/doi/10.1044/jshd.2404.330). Journal of Speech and Hearing Disorders, 24, 330-345.",
        "ISO 8253-1:2010. Acoustique, méthodes d'essais audiométriques, partie 1 : audiométrie tonale liminaire en conduction aérienne et en conduction osseuse.",
        "ASHA (2005). [Guidelines for Manual Pure-Tone Threshold Audiometry](https://www.asha.org/policy/gl2005-00014/).",
        "Levitt H. (1971). [Transformed up-down methods in psychoacoustics](https://pubs.aip.org/asa/jasa/article/49/2B/467/747112/Transformed-Up-Down-Methods-in-Psychoacoustics). Journal of the Acoustical Society of America, 49(2B), 467-477.",
        "Burk M. H., Wiley T. L. (2004). [Continuous versus pulsed tones in audiometry](https://pubmed.ncbi.nlm.nih.gov/15248804/). American Journal of Audiology, 13(1), 54-61.",
        "Green D. M., Swets J. A. (1966). Signal Detection Theory and Psychophysics. Wiley.",
        "ANSI/ASA S3.1-1999 (R2018). Maximum Permissible Ambient Noise Levels for Audiometric Test Rooms.",
        "ISO 389-1:2017. Acoustique, zéro de référence pour l'étalonnage d'équipements audiométriques, partie 1 : sons purs et écouteurs supra-auraux.",
        "IEC 60645-1:2017. Électroacoustique, équipements audiométriques, partie 1 : équipements pour l'audiométrie tonale.",
        "ASHA (1994). [Guidelines for the Audiologic Management of Individuals Receiving Cochleotoxic Drug Therapy](https://www.asha.org/policy/gl1994-00003/).",
        "ISO 7029:2000 (révisée en 2017). [Distribution statistique des seuils d'audition en fonction de l'âge](https://www.iso.org/standard/26314.html).",
        "Lidén G., Kankkunen A. (1969). [Visual reinforcement audiometry](https://pubmed.ncbi.nlm.nih.gov/5374646/). Acta Oto-Laryngologica, 67, 281-292.",
        "ASHA (2004). Guidelines for the Audiologic Assessment of Children From Birth to 5 Years of Age.",
        "Stelmachowicz P. G. et al. (1989). [Normative thresholds in the 8- to 20-kHz range as a function of age](https://pubmed.ncbi.nlm.nih.gov/2808912/). Journal of the Acoustical Society of America, 86(4), 1384-1391.",
    ]
}
