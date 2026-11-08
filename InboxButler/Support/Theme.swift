import SwiftUI
import UIKit

// MARK: - Colour

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// A colour that switches with light / dark mode.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Inbox Butler's cinematic identity: deep ink, restrained teal, and accessible surfaces.
enum Theme {
    static let background = Color.dynamic(light: 0xF4F7F9, dark: 0x090D1B)
    static let surface    = Color.dynamic(light: 0xFFFFFF, dark: 0x171D32)
    static let ink        = Color.dynamic(light: 0x14212D, dark: 0xF7F8FF)
    static let muted      = Color.dynamic(light: 0x576574, dark: 0xA0ABC5)
    static let hairline   = Color.dynamic(light: 0xDFE6EC, dark: 0x333B57)
    static let accent     = Color.dynamic(light: 0x087E84, dark: 0x65E2DC)
    static let gold       = Color.dynamic(light: 0xB98310, dark: 0xE3B34C)
    static let good       = Color.dynamic(light: 0x1E8E5A, dark: 0x4CC88B)
    static let warn       = Color.dynamic(light: 0xC2600A, dark: 0xF0A04B)
    static let radius: CGFloat = 16
    static let violet = Color(hex: 0x9477FF)
    static let elevated = Color.dynamic(light: 0xEDF3F6, dark: 0x202840)

    /// Soft, distinct tints for avatars and accounts.
    static let palette: [Color] = [
        Color(hex: 0x4C5BD4), Color(hex: 0x1F9D8F), Color(hex: 0xC8841F),
        Color(hex: 0xC2476B), Color(hex: 0x7A52C7), Color(hex: 0x4F6B8A)
    ]
}

extension Font {
    /// Editorial serif for headings. Scales with Dynamic Type.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}

// MARK: - Building blocks

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    /// A clean rounded surface with a hairline border.
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Small spaced-out caps label above a group, e.g. "ATTACHMENTS".
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Round initials avatar, tinted consistently from the name.
struct Avatar: View {
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var tint: Color {
        // A stable hash (Swift's own Hasher changes every launch).
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Theme.palette[h % Theme.palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Rounded label for statuses ("Priority", "Reply waiting").
struct PillLabel: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Filter chip for the inbox.
struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(selected ? Color.white.opacity(0.25) : Theme.hairline, in: Capsule())
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .background(selected ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.hairline.opacity(0.7), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// "14:30", "Yesterday", "Mon", "12 Mar".
enum ShortDate {
    static func string(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: now).day, days >= 0, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
