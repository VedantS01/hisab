import SwiftUI
import HisabCore

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Bahi-khata design tokens. Every screen pulls colors from here, nowhere else.
enum HisabTheme {
    static let khataRed = Color(hex: 0xA4243B)
    static let ink = Color(hex: 0x22333B)
    static let kagaz = Color(hex: 0xF5EFE6)
    static let sona = Color(hex: 0xD9A441)
    static let hara = Color(hex: 0x3A7D44)

    static let darkBackground = Color(hex: 0x161F24)
    static let darkCard = Color(hex: 0x22333B)

    static var background: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(darkBackground) : UIColor(kagaz)
        })
    }

    static var cardBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(darkCard) : .white
        })
    }

    static var primaryText: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(kagaz) : UIColor(ink)
        })
    }

    static func amountColor(direction: Direction) -> Color {
        direction == .credit ? hara : primaryText
    }

    static func amountText(_ paise: Int64, direction: Direction) -> Text {
        Text(Money.formatPaise(paise, signed: direction == .credit))
            .monospacedDigit()
            .foregroundStyle(amountColor(direction: direction))
    }

    static func sourceGlyph(_ source: Source) -> String {
        switch source {
        case .gpay: "g.circle.fill"
        case .paytm: "p.circle.fill"
        case .hdfc: "building.columns.fill"
        case .idfc: "building.columns"
        }
    }
}

/// Standard card container used across the dashboard.
struct HisabCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(HisabTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}
