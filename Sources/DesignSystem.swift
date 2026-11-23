import SwiftUI
import UIKit

enum AppPalette {
    static let online = Color.dyn(0x4FD229, 0x4FD229)
    static let appleBlue = Color(hex: 0x0A84FF)
    static let danger = Color.dyn(0xFA5151, 0xFA5151)
    static let legacyLink = Color.dyn(0x576B95, 0x7D90A9)
    static let neutralSurface = Color.dyn(0xEDEDED, 0x1C1C1E)
    static let systemSecondary = Color.dyn(0x8E8E93, 0x8E8E93)
    static let warmHighlight = Color.dyn(0xFFE7B0, 0xFFE7B0)
    static let teal = Color.dyn(0x128C7E, 0x128C7E)
    static let success = Color.dyn(0x19A47A, 0x19A47A)
    static let info = Color.dyn(0x356FF4, 0x356FF4)
    static let dangerSoft = Color.dyn(0xFF6B6B, 0xFF6B6B)
    static let deepForest = Color.dyn(0x07351C, 0x07351C)
    static let title = Color.dyn(0x1A1A1A, 0xF2F4F6)
    static let preview = Color.dyn(0x8A8A8A, 0x8F969E)
    static let conversationPreview = Color.dyn(0x999999, 0x8F969E)
    static let previewAccent = Color.dyn(0xFA5151, 0xFA5151)
    static let time = Color.dyn(0xB2B2B2, 0x6F767E)
    static let badgeRing = Color.dyn(0xFFFFFF, 0x121317)
    static let chipInk = Color.dyn(0x62636A, 0xA8A9AF)
    static let selectedChipFill = Color.dyn(0x161823, 0xF1F1F3)
    static let selectedChipInk = Color.dyn(0xFFFFFF, 0x17171A)
    static let blueDeep = Color.dyn(0x325DFF, 0x6EA8FF)
    static let blueShadow = Color(hex: 0x286DFF)
    static let tileStart = Color.dyn(0x2B2F3A, 0x2B2F3A)
    static let tileEnd = Color.dyn(0x171B22, 0x171B22)
    static let unreadAction = Color.dyn(0x28986C, 0x28986C)
    static let mutedAction = Color.dyn(0x7B8087, 0x7B8087)
    static let pinAction = Color.dyn(0x0A84FF, 0x0A84FF)
    static let rowDark = Color(hex: 0x121317)
    static let canvasDark = Color(hex: 0x0E0F12)
    static let searchFill = Color.dyn(0xF0F2F5, 0x1D2026)
    static let tertiary = Color.dyn(0x8A8A8A, 0x6E7378)
    static let whatsApp = Color(hex: 0x25D366)
    static let violet = Color.dyn(0x7A45D6, 0xB98CFF)
    static let violetDeep = Color.dyn(0x7A45D6, 0x7A45D6)

    static let onlineUI = UIColor(hex: 0x4FD229)
    static let whatsAppUI = UIColor(hex: 0x25D366)
    static let dangerUI = UIColor(hex: 0xFA5151)
    static let rowDarkUI = UIColor(hex: 0x121317)
    static let titleDarkUI = UIColor(hex: 0xF2F4F6)
    static let titleLightUI = UIColor(hex: 0x191919)
    static let previewDarkUI = UIColor(hex: 0x8F969E)
    static let previewLightUI = UIColor(hex: 0x999999)
    static let timeDarkUI = UIColor(hex: 0x6F767E)
    static let timeLightUI = UIColor(hex: 0xB2B2B2)
    static let dividerUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x2A2D33)
            : UIColor(hex: 0xE9EDEF)
    }
}

enum AppDesign {
    enum Type {
        static var pageTitle: Font { pf(21, .semibold) }
        static var title: Font { pf(17.5, .semibold) }
        static var titleRegular: Font { pf(17.5) }
        static var rowTitle: Font { pf(15.5, .semibold) }
        static var rowTitleMedium: Font { pf(15.5, .medium) }
        static var listTitle: Font { pf(16.5) }
        static var bodyLarge: Font { pf(15.5) }
        static var bodyStrong: Font { pf(13.5, .semibold) }
        static var bodyMedium: Font { pf(13.5, .medium) }
        static var body: Font { pf(13.5) }
        static var caption: Font { pf(12.5) }
        static var captionStrong: Font { pf(12.5, .semibold) }
        static var captionMedium: Font { pf(12.5, .medium) }
        static var section: Font { pf(12, .semibold) }
        static var sectionMedium: Font { pf(12, .medium) }
        static var button: Font { pf(16.5, .semibold) }
        static var buttonMedium: Font { pf(16.5, .medium) }
        static var compactButton: Font { pf(13, .semibold) }
        static var compactButtonMedium: Font { pf(13, .medium) }
        static var status: Font { pf(12.5, .semibold) }
        static var code: Font { pf(28, .semibold) }
        static var keypad: Font { pf(22, .medium) }
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let hairline: CGFloat = 1.5
        static let micro: CGFloat = 4
        static let tiny: CGFloat = 6
        static let mini: CGFloat = 8
        static let small: CGFloat = 10
        static let compact: CGFloat = 12
        static let control: CGFloat = 14
        static let row: CGFloat = 16
        static let panel: CGFloat = 20
        static let overlay: CGFloat = 28
        static let hero: CGFloat = 36
    }

    enum Control {
        static let hairline: CGFloat = 0.5
        static let compactBadgeHeight: CGFloat = 20
        static let badgeHeight: CGFloat = 24
        static let statusHeight: CGFloat = 28
        static let sectionHeaderHeight: CGFloat = 30
        static let smallButtonHeight: CGFloat = 32
        static let floatingControlHeight: CGFloat = 36
        static let iconSmallHeight: CGFloat = 38
        static let iconControlHeight: CGFloat = 40
        static let searchHeight: CGFloat = 42
        static let toolbarHeight: CGFloat = 44
        static let mediumControlHeight: CGFloat = 48
        static let compactHeight: CGFloat = 44
        static let buttonHeight: CGFloat = 50
        static let largeControlHeight: CGFloat = 52
        static let dialogRowHeight: CGFloat = 54
        static let profileRowHeight: CGFloat = 60
        static let rowHeight: CGFloat = 72
        static let compactRowHeight: CGFloat = 64
        static let menuRowHeight: CGFloat = 56
        static let loadingPanelHeight: CGFloat = 82
    }

    enum Avatar {
        static let inline: CGFloat = 24
        static let compact: CGFloat = 34
        static let row: CGFloat = 40
        static let standard: CGFloat = 44
        static let hero: CGFloat = 54
    }

    enum Motion {
        static let press = Animation.easeOut(duration: 0.10)
        static let selection = Animation.easeOut(duration: 0.18)
        static let transition = Animation.easeOut(duration: 0.22)
    }
}

enum AppActionTone {
    case primary
    case secondary
    case destructive

    var fill: Color {
        switch self {
        case .primary: return OrbitTheme.jadeDeep
        case .secondary: return OrbitTheme.fieldRaised
        case .destructive: return C.red
        }
    }

    var ink: Color {
        switch self {
        case .primary, .destructive: return .white
        case .secondary: return OrbitTheme.ink
        }
    }
}

struct AppFlowPanel<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(OrbitTheme.cardBackground())
            .clipShape(RoundedRectangle(
                cornerRadius: AppDesign.Radius.panel,
                style: .continuous
            ))
    }
}

struct AppFlowDivider: View {
    var leading: CGFloat = 76

    var body: some View {
        Rectangle()
            .fill(OrbitTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}

struct AppSectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        OrbitSectionLabel(text: title, count: count)
            .frame(height: 30)
    }
}

struct AppEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: AppDesign.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(OrbitTheme.jadeSoft)
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(OrbitTheme.jadeDeep)
            }
            .frame(width: 48, height: 48)

            Text(title)
                .font(AppDesign.Type.rowTitle)
                .foregroundStyle(OrbitTheme.ink)

            Text(detail)
                .font(AppDesign.Type.body)
                .foregroundStyle(OrbitTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, 30)
    }
}

struct AppStatusPill: View {
    let title: String
    var symbol: String? = nil
    var tone: AppActionTone = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            Text(title)
                .font(AppDesign.Type.status)
                .lineLimit(1)
        }
        .foregroundStyle(tone == .primary ? OrbitTheme.jadeDeep : OrbitTheme.secondary)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            Capsule().fill(
                tone == .primary ? OrbitTheme.jadeSoft : OrbitTheme.fieldRaised
            )
        )
    }
}

struct AppIconTile: View {
    let symbol: String
    var tone: AppActionTone = .primary
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.28,
                style: .continuous
            )
            .fill(background)

            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .frame(width: size, height: size)
    }

    private var background: Color {
        switch tone {
        case .primary: return OrbitTheme.jadeSoft
        case .secondary: return OrbitTheme.fieldRaised
        case .destructive: return C.red.opacity(0.10)
        }
    }

    private var foreground: Color {
        switch tone {
        case .primary: return OrbitTheme.jadeDeep
        case .secondary: return OrbitTheme.secondary
        case .destructive: return C.red
        }
    }
}

struct AppCompactButton: View {
    let title: String
    var symbol: String? = nil
    var tone: AppActionTone = .primary
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(tone.ink)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Text(title)
                    .font(AppDesign.Type.compactButton)
                    .lineLimit(1)
            }
            .foregroundStyle(enabled ? tone.ink : OrbitTheme.tertiary)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                Capsule().fill(
                    enabled ? tone.fill : OrbitTheme.fieldRaised
                )
            )
        }
        .buttonStyle(AppPressStyle())
        .disabled(!enabled || busy)
    }
}

struct AppPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var tone: AppActionTone = .primary
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(enabled ? tone.ink : OrbitTheme.secondary)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(title)
                    .font(AppDesign.Type.button)
            }
            .foregroundStyle(enabled ? tone.ink : OrbitTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: AppDesign.Control.buttonHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: AppDesign.Radius.control,
                    style: .continuous
                )
                .fill(enabled ? tone.fill : OrbitTheme.fieldRaised)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AppDesign.Radius.control,
                    style: .continuous
                )
                .stroke(OrbitTheme.divider, lineWidth: enabled ? 0 : 0.7)
            }
        }
        .buttonStyle(AppPressStyle())
        .disabled(!enabled || busy)
    }
}

struct AppFlowRow<Leading: View, Content: View, Trailing: View>: View {
    var height: CGFloat = AppDesign.Control.rowHeight
    let leading: Leading
    let content: Content
    let trailing: Trailing

    init(
        height: CGFloat = AppDesign.Control.rowHeight,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.height = height
        self.leading = leading()
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            leading
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .contentShape(Rectangle())
    }
}

struct AppPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(AppDesign.Motion.press, value: configuration.isPressed)
    }
}

struct MenuPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.995 : 1))
            .overlay {
                Color.primary
                    .opacity(configuration.isPressed ? 0.045 : 0)
                    .allowsHitTesting(false)
            }
            .animation(
                reduceMotion ? nil : AppDesign.Motion.press,
                value: configuration.isPressed
            )
    }
}

struct AppCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(AppDesign.Motion.press, value: configuration.isPressed)
    }
}

struct AppIconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .animation(AppDesign.Motion.press, value: configuration.isPressed)
    }
}

struct AppSegmentPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(
                    cornerRadius: AppDesign.Radius.control,
                    style: .continuous
                )
                .fill(Color.primary.opacity(configuration.isPressed ? 0.055 : 0))
                .allowsHitTesting(false)
            }
            .animation(
                reduceMotion ? nil : AppDesign.Motion.press,
                value: configuration.isPressed
            )
    }
}

struct AppKeyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(AppDesign.Motion.press, value: configuration.isPressed)
    }
}
