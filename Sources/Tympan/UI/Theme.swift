import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0E0F12)
    static let sidebar = Color(hex: 0x15171B)
    static let panel = Color(hex: 0x15171B)
    static let panelDeep = Color(hex: 0x111316)
    static let raised = Color(hex: 0x1D1F24)
    static let border = Color(hex: 0x262930)
    static let borderStrong = Color(hex: 0x3A3E46)
    static let text = Color(hex: 0xE8E9EC)
    static let secondary = Color(hex: 0xB8BCC5)
    static let muted = Color(hex: 0x8B909B)
    static let accent = Color(hex: 0xFFB020)
    static let accentSoft = Color(hex: 0xFFC95C)
    static let accentBg = Color(hex: 0x2A200C)
    static let accentBorder = Color(hex: 0x5C4413)
    static let onAccent = Color(hex: 0x16120A)
    static let right = Color(hex: 0xFF5A4E)
    static let left = Color(hex: 0x4DA3FF)
    static let ok = Color(hex: 0x3DDC84)
    static let okBg = Color(hex: 0x1D2A22)

    static func color(for ear: Ear) -> Color { ear == .right ? right : left }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Petit titre en capitales condensées, façon sérigraphie de console.
struct SectionLabel: View {
    let text: LocalizedStringKey
    var color: Color = Theme.muted

    init(_ text: LocalizedStringKey, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold).width(.condensed))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Module : panneau sombre à bord fin.
struct Panel<Content: View>: View {
    var padding: CGFloat
    var borderColor: Color
    let content: Content

    init(padding: CGFloat = 18, borderColor: Color = Theme.border, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Theme.text)
            .background(configuration.isPressed ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderStrong))
            .contentShape(Rectangle())
    }
}

/// Symbole clinique : O rouge pour la droite, X bleu pour la gauche.
struct EarSymbol: View {
    let ear: Ear
    var dimmed = false

    var body: some View {
        Group {
            if ear == .right {
                Circle()
                    .strokeBorder(Theme.right, lineWidth: 2)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.left)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
    }
}

struct Keycap: View {
    let text: String
    var color: Color = Theme.onAccent

    var body: some View {
        Text(verbatim: text)
            .font(Theme.mono(13, .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 1.5))
            .foregroundStyle(color)
            .opacity(0.8)
    }
}

/// Langue réellement affichée (celle des traductions chargées), qui peut différer du système :
/// Mac en allemand = app en anglais, ou langue choisie dans les Réglages.
enum AppLocale {
    static let language: String = Bundle.main.preferredLocalizations.first ?? "en"
    static var isFrench: Bool { language.hasPrefix("fr") }
    /// Langue de l'app, région du système : formats de date et de nombre cohérents avec le texte.
    static let current: Locale = {
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: language) }
        return Locale(identifier: "\(language)_\(region)")
    }()
}

enum Format {
    /// Date courte : 07/10/26 en français, 10/07/26 en anglais américain.
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLocale.current
        f.setLocalizedDateFormatFromTemplate("ddMMyy")
        return f
    }()

    static let long: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLocale.current
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// 14800 -> « 14 800 » en français, « 14,800 » en anglais.
    static func hz(_ value: Int) -> String {
        value.formatted(.number.locale(AppLocale.current))
    }

    /// Nombre décimal selon la langue : « 1,5 » ou « 1.5 ». `trim` retire les zéros inutiles (« 4 » et pas « 4,0 »).
    static func decimal(_ value: Double, digits: Int = 1, trim: Bool = true) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(AppLocale.current)
        return trim
            ? value.formatted(style.precision(.fractionLength(0...digits)))
            : value.formatted(style.precision(.fractionLength(digits)))
    }

    /// Place au classement (index 0 = premier) : « 1re place », « 2e place » ; « 1st place », « 2nd place ».
    static func place(_ index: Int) -> String {
        let n = index + 1
        if AppLocale.isFrench { return n == 1 ? "1re place" : "\(n)e place" }
        let f = NumberFormatter()
        f.locale = AppLocale.current
        f.numberStyle = .ordinal
        let ordinal = f.string(from: NSNumber(value: n)) ?? "\(n)"
        return String(localized: "\(ordinal) place")
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
