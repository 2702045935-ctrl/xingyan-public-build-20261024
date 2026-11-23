import SwiftUI

enum AppDesign {
    enum Type {
        static var pageTitle: Font { pf(21, .semibold) }
        static var title: Font { pf(17.5, .semibold) }
        static var rowTitle: Font { pf(15.5, .semibold) }
        static var listTitle: Font { pf(16.5) }
        static var body: Font { pf(13.5) }
        static var caption: Font { pf(12.5) }
        static var section: Font { pf(12, .semibold) }
        static var button: Font { pf(16.5, .semibold) }
        static var compactButton: Font { pf(13, .semibold) }
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
        static let searchHeight: CGFloat = 42
        static let compactHeight: CGFloat = 44
        static let buttonHeight: CGFloat = 50
        static let rowHeight: CGFloat = 72
        static let compactRowHeight: CGFloat = 64
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
