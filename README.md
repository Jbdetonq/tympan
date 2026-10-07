# Tympan

**Free, open source hearing tracker for macOS.** Take a hearing test at home with your own headphones, keep a history per person, and see how your hearing evolves over time.

*Version française plus bas.*

> Tympan is a personal tracking tool, **not a medical device** and not a diagnosis. It does not replace a hearing test by a doctor or an ENT specialist. If you suddenly lose hearing (within hours or days), see a doctor within 48 hours.

## Features

- **Audiogram test** in three lengths (Quick ~3 min, Standard ~7 min, Full ~11 min), 250 Hz to 10 kHz, each ear.
- **Reliable by design**: random timing, shuffled frequencies, catch trials (silent trials) and a 1 kHz retest give a reliability score.
- **History per user**: compare each test with a reference, see the trend per frequency, get a notice when a shift appears.
- **Headphone profiles**: tests are compared only with the same headphones at the same locked volume, so results stay comparable without lab calibration.
- **Ambient noise check** with the microphone before each test (nothing is recorded).
- **Kids mode**: a real test presented as a game (an animal appears when a sound is found).
- **Ear games**: mosquito hunt (highest frequency you can hear) and pitch matching.
- **PDF export** of the audiogram, data export and import between Macs.
- **English and French**. Follows your Mac's language, or choose one in **Tympan > Settings** (⌘,).

## Hearing safety

- The volume is locked during a test, and only raised when nothing else is playing on the Mac. If another app starts playing, your usual volume comes back and the test waits.
- **Esc cuts the sound immediately.** The mute key is respected.
- Your original volume is restored at the end, when you quit, and even at next launch after a crash.
- Games play at a fixed moderate level.

## Privacy

Everything stays on your Mac. Tympan has no network access, no account, no analytics. Data lives in `~/Library/Application Support/Tympan/tympan-data.json`. The microphone is only used to measure the room level for 3 seconds.

## Levels are relative

Tympan shows **app-relative dB**, not dB HL. Real dB HL need a calibrated audiometer and known headphones. What Tympan tells you is "same as last time, or worse", which is what matters for tracking. Same approach as hearing monitoring in occupational health: each test is compared with a reference test of the same person, on the same equipment.

## Install

1. Download `Tympan.dmg` from the [Releases](../../releases) page.
2. Open it and drag Tympan into Applications.
3. The app is not notarized by Apple yet. On first launch, macOS blocks it: open **System Settings > Privacy & Security** and click **Open Anyway**.

Requires macOS 14 or later, Apple Silicon or Intel.

## Build from source

Requires Xcode (selected with `sudo xcode-select -s /Applications/Xcode.app`).

```
./build.sh run    # build dist/Tympan.app and launch it
./build.sh dmg    # universal build and dist/Tympan.dmg
```

Always launch through `build.sh` (not Xcode's Run button): the microphone needs the .app bundle. To edit the code, open `Package.swift` in Xcode.

## Translations

Tympan is written in French and translated into English. Other languages are welcome, no Swift needed:

1. Copy `Localization/en.lproj` to `Localization/xx.lproj` (`xx` = language code, e.g. `de`, `es`, `it`).
2. Translate the right-hand side of each line in `Localizable.strings`, `Localizable.stringsdict` (plural forms) and `InfoPlist.strings`. The left-hand side is the French original: leave it unchanged.
3. Keep every placeholder (`%@`, `%lld`, `%1$@`...). You may reorder them with positions (`%2$@ ... %1$@`). Write a percent sign as `%%`.
4. Add `xx` to `CFBundleLocalizations` in `Support/Info.plist`.
5. Check: `python3 Localization/check.py xx`, then build and try it: `./build.sh` and `open dist/Tympan.app --args -AppleLanguages "(xx)"`. The new language also appears in Settings.

Key terms (translate them the same way everywhere): app dB, headphone profile, threshold, catch trial, reliability, reference, Check needed, Worth showing a doctor, Kids mode, Mosquito Hunt, Pitch Match, Quick / Standard / Full.

Style: short sentences, address the user informally where your language allows it, no em dash. Keep the warnings intact: Tympan is not a medical device. Medical terms stay simple (for example "ear specialist" rather than an acronym). Then open a pull request, or an issue with your files attached.

## Feedback

Found a bug, have an idea? [Open an issue](../../issues/new/choose) (a free GitHub account is enough). Health professionals are welcome to suggest improvements. Please never post personal health data or test results.

## Free for everyone

Tympan is and will stay free, for individuals as well as hospitals, clinics, schools and occupational health services. No fee, no registration.

## License

[MIT](LICENSE). You can use, copy, modify and share Tympan freely, as long as the license notice is kept.

---

# Tympan (français)

**Suivi auditif gratuit et libre pour macOS.** Faites un audiogramme chez vous avec votre casque, gardez un historique par personne et suivez l'évolution de votre audition.

> Tympan est un outil de suivi personnel, **pas un dispositif médical** ni un diagnostic. Il ne remplace pas un audiogramme chez un médecin ou un ORL. En cas de perte d'audition brutale (en quelques heures ou jours), consultez dans les 48 heures.

- **Test** en trois durées (Rapide, Moyen, Complet), de 250 Hz à 10 kHz, oreille par oreille, avec essais pièges et indice de fiabilité.
- **Historique** par utilisateur, comparaison à une référence, signal en cas d'écart.
- **Profils casque** : volume verrouillé, on ne compare qu'à matériel identique.
- **Sécurité** : le volume ne monte que si rien d'autre ne joue sur le Mac, **Échap** coupe le son tout de suite, le volume d'origine est toujours rétabli.
- **Mode enfant** et **jeux** d'écoute (chasse au moustique, juste note).
- **Confidentialité** : tout reste sur le Mac, aucune connexion réseau.
- **Français et anglais**, selon la langue du Mac ou au choix dans **Tympan > Réglages** (⌘,). Pour proposer une autre langue, voir la section *Translations* plus haut.

**Installation** : télécharger `Tympan.dmg` dans [Releases](../../releases), glisser Tympan dans Applications, puis au premier lancement : Réglages Système > Confidentialité et sécurité > **Ouvrir quand même**.

**Une idée, un souci ?** [Ouvrir un ticket](../../issues/new/choose). N'y publiez jamais de données de santé.

**Gratuit pour tous**, particuliers comme services de santé, sans inscription. Licence [MIT](LICENSE).
