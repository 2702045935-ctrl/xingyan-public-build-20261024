import SwiftUI
import UIKit

enum PayVisual {
    static var tint: Color { Color.dyn(0x007AFF, 0x0A84FF) }
    static var success: Color { Color.dyn(0x34C759, 0x30D158) }
    static var warning: Color { Color.dyn(0xFF9500, 0xFF9F0A) }
    static var danger: Color { Color.dyn(0xFF3B30, 0xFF453A) }
    static var gold: Color { Color.dyn(0xC99432, 0xD8AA4D) }

    static var canvas: Color { Color.dyn(0xF2F2F7, 0x000000) }
    static var card: Color { Color.dyn(0xFFFFFF, 0x1C1C1E) }
    static var raised: Color { Color.dyn(0xFFFFFF, 0x2C2C2E) }
    static var inset: Color { Color.dyn(0xF2F2F7, 0x2C2C2E) }
    static var separator: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.08)
        })
    }
    static var secondaryInk: Color { Color.dyn(0x6C6C70, 0x98989F) }
}

struct StarPayAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0x393A3E),
                            Color(hex: 0x16171A),
                            Color(hex: 0x030304)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: max(1, size * 0.82)
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.14), location: 0),
                            .init(color: .clear, location: 0.34),
                            .init(color: .white.opacity(0.045), location: 0.78),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            Image(systemName: "creditcard.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: Color.black.opacity(0.45), radius: 1.5, y: 1)
        }
        .frame(width: size, height: size)
        .overlay {
            Circle().stroke(
                LinearGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.8, size * 0.02)
            )
        }
        .shadow(color: Color.black.opacity(0.20), radius: max(2, size * 0.09), y: 2)
    }
}

struct StarPayPhysicalCardSurface: View {
    var radius: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x4A4B4F),
                            Color(hex: 0x121316),
                            Color(hex: 0x030405)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: 3)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x16171A), location: 0),
                            .init(color: Color(hex: 0x070708), location: 0.52),
                            .init(color: Color(hex: 0x101114), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            StarPayBrushedSurface()
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .opacity(0.62)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.15), location: 0),
                            .init(color: .clear, location: 0.17),
                            .init(color: .white.opacity(0.055), location: 0.46),
                            .init(color: .clear, location: 0.62),
                            .init(color: .white.opacity(0.07), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            RadialGradient(
                colors: [.white.opacity(0.09), .clear],
                center: UnitPoint(x: 0.76, y: 0.12),
                startRadius: 0,
                endRadius: 160
            )
            .blendMode(.screen)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.30),
                            .white.opacity(0.055),
                            .black.opacity(0.55),
                            .white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )

            RoundedRectangle(cornerRadius: max(1, radius - 1.2), style: .continuous)
                .stroke(.white.opacity(0.045), lineWidth: 0.55)
                .padding(1.2)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.38), radius: 22, y: 13)
        .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
    }
}

private struct StarPayBrushedSurface: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            let spacing: CGFloat = 3
            var y: CGFloat = -size.height
            while y < size.height * 2 {
                lines.move(to: CGPoint(x: -size.width * 0.1, y: y))
                lines.addLine(to: CGPoint(x: size.width * 1.1, y: y + size.height * 0.46))
                y += spacing
            }
            context.stroke(
                lines,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        .white.opacity(0.042),
                        .white.opacity(0.012),
                        .clear
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ),
                lineWidth: 0.32
            )
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

struct StarPayChip: View {
    var width: CGFloat = 44

    var body: some View {
        let height = width * 0.70
        RoundedRectangle(cornerRadius: width * 0.17, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xFFE7A4), location: 0),
                        .init(color: Color(hex: 0xC69A45), location: 0.42),
                        .init(color: Color(hex: 0xF4D889), location: 0.72),
                        .init(color: Color(hex: 0x9F772E), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .overlay {
                Canvas { context, size in
                    let line = Color.black.opacity(0.26)
                    for index in 1..<4 {
                        let x = size.width * CGFloat(index) / 4
                        var vertical = Path()
                        vertical.move(to: CGPoint(x: x, y: size.height * 0.12))
                        vertical.addLine(to: CGPoint(x: x, y: size.height * 0.88))
                        context.stroke(vertical, with: .color(line), lineWidth: 0.45)
                    }
                    for index in 1..<3 {
                        let y = size.height * CGFloat(index) / 3
                        var horizontal = Path()
                        horizontal.move(to: CGPoint(x: size.width * 0.12, y: y))
                        horizontal.addLine(to: CGPoint(x: size.width * 0.88, y: y))
                        context.stroke(horizontal, with: .color(line), lineWidth: 0.45)
                    }
                }
                .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.17, style: .continuous)
                    .stroke(.white.opacity(0.30), lineWidth: 0.55)
            }
            .shadow(color: .black.opacity(0.30), radius: 1.2, y: 1)
            .accessibilityHidden(true)
    }
}

struct StarPayHologram: View {
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        Color(hex: 0xB8F2DF).opacity(0.46),
                        Color(hex: 0xE7C7FF).opacity(0.32),
                        Color(hex: 0xFFD7B3).opacity(0.38),
                        Color(hex: 0xA5D8FF).opacity(0.34),
                        Color(hex: 0xB8F2DF).opacity(0.46)
                    ],
                    center: .center
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .overlay {
                Circle().stroke(.white.opacity(0.20), lineWidth: 0.55)
            }
            .shadow(color: Color(hex: 0xD8C8FF).opacity(0.20), radius: 7)
            .accessibilityHidden(true)
    }
}

struct StarPayGoldCardSurface: View {
    var radius: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x4A3210),
                            Color(hex: 0x160E03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: 4)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x7A571A), location: 0),
                            .init(color: Color(hex: 0xD9AD47), location: 0.24),
                            .init(color: Color(hex: 0x8A631D), location: 0.54),
                            .init(color: Color(hex: 0xF2D77E), location: 0.82),
                            .init(color: Color(hex: 0x5A3D0D), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            StarPayGoldBrushedMetal()
                .clipShape(RoundedRectangle(cornerRadius: radius,
                                             style: .continuous))
                .opacity(0.68)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.30), location: 0),
                            .init(color: .clear, location: 0.18),
                            .init(color: .white.opacity(0.07), location: 0.44),
                            .init(color: .clear, location: 0.62),
                            .init(color: .white.opacity(0.14), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            RadialGradient(
                colors: [.white.opacity(0.22), .clear],
                center: UnitPoint(x: 0.78, y: 0.12),
                startRadius: 0,
                endRadius: 180
            )
            .blendMode(.screen)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.52),
                            .white.opacity(0.10),
                            Color(hex: 0x2E1D06).opacity(0.90),
                            .white.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.05
                )

            RoundedRectangle(cornerRadius: max(1, radius - 1.3),
                             style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.65)
                .padding(1.3)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.36), radius: 24, y: 14)
        .shadow(color: Color(hex: 0x6D4A12).opacity(0.28), radius: 3, y: 1)
    }
}

private struct StarPayGoldBrushedMetal: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            let spacing: CGFloat = 1.8
            var y: CGFloat = -size.height
            while y < size.height * 2 {
                lines.move(to: CGPoint(x: -size.width * 0.12, y: y))
                lines.addLine(to: CGPoint(x: size.width * 1.12,
                                          y: y + size.height * 0.18))
                y += spacing
            }
            context.stroke(
                lines,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        .white.opacity(0.10),
                        .black.opacity(0.075),
                        .clear
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ),
                lineWidth: 0.28
            )
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

struct StarPayGoldCardFace: View {
    let cardholder: String
    let last4: String
    let cumulativeSpend: Double
    var adminPreview = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            StarPayGoldCardSurface(radius: 26)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0xFFF1B8),
                                        Color(hex: 0xB8872D)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0x3A2608))
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("STAR PAY")
                            .font(pfExact(11.5, .bold))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: 0x211503))
                        Text("GOLD SIGNATURE")
                            .font(pfExact(7.5, .bold))
                            .tracking(1.65)
                            .foregroundStyle(Color(hex: 0x322006).opacity(0.66))
                    }

                    Spacer(minLength: 6)

                    if adminPreview {
                        Text(Tr("管理灰度"))
                            .font(pf(9, .bold))
                            .foregroundStyle(Color(hex: 0x2B1B04))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(.white.opacity(0.24), in: Capsule())
                    }

                    Image(systemName: "wave.3.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: 0x251604).opacity(0.76))
                }

                Spacer(minLength: 18)

                HStack(alignment: .center, spacing: 12) {
                    StarPayChip(width: 39)
                    StarPayHologram(size: 30)
                    Spacer()
                    Text("GOLD")
                        .font(pfExact(13, .black))
                        .tracking(2.2)
                        .foregroundStyle(Color(hex: 0x241503))
                }

                Spacer(minLength: 16)

                Text("8800  ••••  ••••  \(last4)")
                    .font(Font(UIFont.monospacedDigitSystemFont(ofSize: 18,
                                                               weight: .bold)))
                    .tracking(1.0)
                    .foregroundStyle(Color(hex: 0x241503))
                    .shadow(color: .white.opacity(0.18), radius: 0.3, y: -0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 12)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARD HOLDER")
                            .font(pfExact(7.2, .bold))
                            .tracking(1.1)
                            .foregroundStyle(Color(hex: 0x2A1904).opacity(0.54))
                        Text(cardholder)
                            .font(pfExact(10.5, .bold))
                            .tracking(0.65)
                            .foregroundStyle(Color(hex: 0x241503))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CUMULATIVE SPEND")
                            .font(pfExact(7.2, .bold))
                            .tracking(0.9)
                            .foregroundStyle(Color(hex: 0x2A1904).opacity(0.54))
                        Text("¥" + moneyFmt(cumulativeSpend))
                            .font(pfMoney(12.5, .bold))
                            .foregroundStyle(Color(hex: 0x241503))
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 224)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Tr("星言金卡") + " " + last4)
    }
}

struct StarPayAmount: View {
    enum Role {
        case hero, metric, row, detail, sheet

        var size: CGFloat {
            switch self {
            case .hero: return 46
            case .metric: return 16
            case .row: return 17
            case .detail: return 36
            case .sheet: return 42
            }
        }

        var symbolSize: CGFloat {
            (size * 0.48).rounded()
        }

        var fractionSize: CGFloat {
            (size * 0.72).rounded()
        }

        var weight: Font.Weight {
            switch self {
            case .hero, .detail, .sheet: return .semibold
            case .metric, .row: return .semibold
            }
        }

        var tracking: CGFloat {
            switch self {
            case .hero, .detail, .sheet: return -0.55
            default: return 0
            }
        }

        var symbolLift: CGFloat {
            ((size - symbolSize) * 0.62).rounded()
        }

        var uiWeight: UIFont.Weight {
            switch weight {
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            default: return .regular
            }
        }
    }

    let value: Double
    var role: Role = .row
    var color: Color = C.label
    var sign = ""

    var body: some View {
        let text = moneyFmt(abs(value.isFinite ? value : 0))
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = parts.first.map(String.init) ?? "0"
        let fraction = parts.count > 1 ? String(parts[1]) : "00"
        let scale = max(0.85, fontScale)

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(sign + "¥")
                .font(.system(size: max(9, (role.symbolSize * scale).rounded()),
                              weight: role.weight))
                .baselineOffset(role.symbolLift)
            Text(integer)
                .font(Font(UIFont.monospacedDigitSystemFont(
                    ofSize: max(9, (role.size * scale).rounded()),
                    weight: role.uiWeight
                )))
                .tracking(role.tracking)
                .layoutPriority(1)
            Text("." + fraction)
                .font(Font(UIFont.monospacedDigitSystemFont(
                    ofSize: max(9, (role.fractionSize * scale).rounded()),
                    weight: role.uiWeight
                )))
                .tracking(role.tracking * 0.5)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sign + "¥" + moneyFmt(abs(value.isFinite ? value : 0)))
    }
}

struct PayGroupCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PaySectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(pf(13, .semibold))
            .foregroundColor(PayVisual.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct PayStatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, processing, success, warning, danger
    }

    private var color: Color {
        switch tone {
        case .neutral: return PayVisual.secondaryInk
        case .processing: return PayVisual.tint
        case .success: return PayVisual.success
        case .warning: return PayVisual.warning
        case .danger: return PayVisual.danger
        }
    }

    var body: some View {
        Text(text)
            .font(pf(12.5, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct PayDetailRow: View {
    let title: String
    let value: String
    var valueColor: Color = C.label
    var copyValue: String? = nil

    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(pf(15))
                .foregroundColor(PayVisual.secondaryInk)
            Spacer(minLength: 12)
            Text(value)
                .font(pf(15, .medium))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let copyValue, !copyValue.isEmpty else { return }
            UIPasteboard.general.string = copyValue
            app.show(Tr("已复制"))
        }
    }
}

struct PayEmptyState: View {
    let symbol: String
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(PayVisual.secondaryInk)
            Text(title)
                .font(pf(16, .semibold))
                .foregroundColor(C.label)
            if !detail.isEmpty {
                Text(detail)
                    .font(pf(13))
                    .foregroundColor(PayVisual.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 28)
    }
}

struct PayPrimaryButtonStyle: ButtonStyle {
    var tint: Color = PayVisual.tint
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(17, .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? tint : PayVisual.secondaryInk.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PaySecondaryButtonStyle: ButtonStyle {
    var tint: Color = PayVisual.tint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(16, .semibold))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ApplePayAuthorizationButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(pf(17, .semibold))
            .foregroundStyle(Color.dyn(0xFFFFFF, 0x000000))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                enabled
                    ? Color.dyn(0x000000, 0xFFFFFF)
                    : PayVisual.secondaryInk.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.10),
                       value: configuration.isPressed)
    }
}

private struct PayPrimaryActionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
                       value: configuration.isPressed)
    }
}

private struct StarPayGuidePage: Identifiable {
    let id: Int
    let kicker: String
    let title: String
    let detail: String
}

private struct StarPayGuideView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [StarPayGuidePage] = [
        .init(id: 0,
              kicker: "STAR PAY WALLET",
              title: Tr("先确认当前卡"),
              detail: Tr("卡包里的后卡先切到前台，再确认卡面和尾号。余额只在面容验证后显示。")),
        .init(id: 1,
              kicker: Tr("安全验证"),
              title: Tr("每次支付都先验证"),
              detail: Tr("面容 ID 或支付密码通过后才继续。验证失败不会创建付款记录。")),
        .init(id: 2,
              kicker: Tr("快捷操作"),
              title: Tr("付款和收款分开"),
              detail: Tr("付款用于向商家出示付款码；收款用于展示你的收款码，避免拿错页面。")),
        .init(id: 3,
              kicker: Tr("账本"),
              title: Tr("每一笔都有记录"),
              detail: Tr("支付完成后可在最近交易里查看金额、方向、余额变化和交易单号。"))
    ]

    var body: some View {
        ZStack {
            PayVisual.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PayVisual.tint)
                    Text(Tr("星言支付"))
                        .font(pf(17, .semibold))
                        .foregroundStyle(C.label)
                    Spacer(minLength: 0)
                    Button(Tr("跳过")) { onFinish() }
                        .font(pf(14, .medium))
                        .foregroundStyle(PayVisual.secondaryInk)
                }
                .padding(.horizontal, 20)
                .padding(.top, max(12, L.safeTop))

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        guidePage(item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 6) {
                    ForEach(pages) { item in
                        Capsule(style: .continuous)
                            .fill(item.id == page ? PayVisual.tint : PayVisual.separator)
                            .frame(width: item.id == page ? 20 : 6, height: 6)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: page)

                Button {
                    if page < pages.count - 1 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            page += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? Tr("继续") : Tr("开始使用"))
                }
                .buttonStyle(PayPrimaryButtonStyle(tint: PayVisual.tint))
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, max(18, L.safeBottom + 8))
            }
        }
        .interactiveDismissDisabled()
    }

    private func guidePage(_ item: StarPayGuidePage) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            guideArtwork(item.id)
                .frame(height: 238)
                .padding(.horizontal, 20)

            VStack(spacing: 9) {
                Text(item.kicker)
                    .font(pfExact(10, .bold))
                    .tracking(1.7)
                    .foregroundStyle(PayVisual.tint)
                Text(item.title)
                    .font(pf(28, .bold))
                    .foregroundStyle(C.label)
                    .multilineTextAlignment(.center)
                Text(item.detail)
                    .font(pf(15))
                    .foregroundStyle(PayVisual.secondaryInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func guideArtwork(_ index: Int) -> some View {
        switch index {
        case 0:
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(PayVisual.gold.opacity(0.24))
                    .frame(width: 236, height: 148)
                    .offset(y: 38)
                StarPayPhysicalCardSurface(radius: 24)
                    .frame(width: 270, height: 166)
                    .overlay {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STAR PAY")
                                .font(pfExact(11, .bold))
                                .tracking(1.4)
                                .foregroundStyle(.white.opacity(0.56))
                            Spacer()
                            Text("••••  " + XYPay.tail("guide"))
                                .font(pfStyled(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text(Tr("当前卡"))
                                .font(pf(11, .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        .padding(18)
                    }
            }
        case 1:
            ZStack {
                Circle()
                    .fill(PayVisual.tint.opacity(0.10))
                    .frame(width: 176, height: 176)
                Circle()
                    .stroke(PayVisual.tint.opacity(0.18), lineWidth: 1)
                    .frame(width: 208, height: 208)
                Image(systemName: "faceid")
                    .font(.system(size: 86, weight: .light))
                    .foregroundStyle(PayVisual.tint)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white, PayVisual.success)
                    .offset(x: 62, y: 62)
            }
        case 2:
            HStack(spacing: 12) {
                guideActionPreview(Tr("付款"), symbol: "wave.3.right.circle.fill",
                                   fill: Color(hex: 0x111111), ink: .white)
                guideActionPreview(Tr("收款"), symbol: "qrcode",
                                   fill: PayVisual.card, ink: C.label)
            }
        default:
            ZStack {
                PayVisual.card
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(width: 258, height: 176)
                    .shadow(color: Color.black.opacity(0.08), radius: 14, y: 7)
                VStack(alignment: .leading, spacing: 13) {
                    Label(Tr("交易成功"), systemImage: "checkmark.circle.fill")
                        .font(pf(16, .semibold))
                        .foregroundStyle(PayVisual.success)
                    Text("− ¥ 128.00")
                        .font(pfMoney(26, .bold))
                        .foregroundStyle(C.label)
                    HairLine()
                    HStack {
                        Text(Tr("余额"))
                        Spacer()
                        Text("¥ 1,280.00")
                    }
                    .font(pf(12.5, .medium))
                    .foregroundStyle(PayVisual.secondaryInk)
                }
                .padding(20)
            }
        }
    }

    private func guideActionPreview(_ title: String, symbol: String,
                                    fill: Color, ink: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(title == Tr("付款") ? .white : PayVisual.tint)
            Text(title)
                .font(pf(18, .semibold))
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
        }
    }
}

struct PayOfficialView: View {
    private struct LedgerDayGroup: Identifiable {
        let day: String
        let entries: [LedgerBillEntry]
        var id: String { day }
    }

    let name: String
    let subtitle: String
    let avatar: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var ledger: LedgerBillsPayload?
    @State private var loading = true
    @State private var selectedLedger: LedgerBillEntry?
    @State private var balanceVisible = false
    @State private var faceBusy = false
    @State private var showPayGuide = false
    @AppStorage("starpay.guide.seen.v2") private var payGuideSeen = false

    private var balance: Double { app.me?.balance ?? ledger?.balance ?? 0 }
    private static let goldThreshold = 50_000.0
    private var cumulativeSpend: Double { max(0, ledger?.expense ?? 0) }
    private var adminGoldPreview: Bool { app.me?.ops == true }
    private var goldUnlocked: Bool {
        adminGoldPreview || cumulativeSpend >= Self.goldThreshold
    }

    var body: some View {
        VStack(spacing: 0) {
            appleWalletHeader

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    paymentHero
                    paymentPrimaryActions
                    transactionFeed

                    if loading {
                        ProgressView().padding(.vertical, 20)
                    }

                    quickActions
                    ledgerSummaryStrip
                    if goldUnlocked {
                        goldCardSection
                    }

                    Color.clear.frame(height: max(20, L.safeBottom + 12))
                }
                .padding(.top, 4)
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(item: $selectedLedger) { entry in
            ledgerDetail(entry)
        }
        .fullScreenCover(isPresented: $showPayGuide) {
            StarPayGuideView {
                payGuideSeen = true
                showPayGuide = false
            }
        }
        .onAppear {
            guard !payGuideSeen, !showPayGuide else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !payGuideSeen { showPayGuide = true }
            }
        }
        .task {
            async let account = API.shared.me()
            async let ledgerValue = API.shared.ledgerBills(limit: 200)
            app.me = try? await account
            ledger = try? await ledgerValue
            loading = false
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                balanceVisible = false
            }
        }
    }

    private var appleWalletHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(C.label)
                    .frame(width: 36, height: 36)
                    .background(PayVisual.card, in: Circle())
                    .overlay {
                        Circle().stroke(PayVisual.separator, lineWidth: 0.6)
                    }
            }
            .buttonStyle(PayPrimaryActionPressStyle())
            .accessibilityLabel(Tr("返回"))

            Text(name)
                .font(pf(34, .bold))
                .tracking(-0.7)
                .foregroundStyle(C.label)
                .lineLimit(1)

            Spacer(minLength: 8)

            NavigationLink {
                CardsView()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(C.label)
                    .frame(width: 36, height: 36)
                    .background(PayVisual.card, in: Circle())
                    .overlay {
                        Circle().stroke(PayVisual.separator, lineWidth: 0.6)
                    }
            }
            .buttonStyle(PayPrimaryActionPressStyle())
            .accessibilityLabel(Tr("卡包"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var paymentHero: some View {
        ZStack(alignment: .topLeading) {
            StarPayPhysicalCardSurface(radius: 28)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Group {
                        if avatar.isEmpty {
                            StarPayAvatar(size: 36)
                        } else {
                            Avatar(path: avatar, size: 36, radius: 18, circle: true)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(pf(15.5, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("STAR PAY")
                            .font(pfExact(9.5, .bold))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        Image(systemName: ledger?.verified == true
                              ? "checkmark.shield.fill" : "clock.badge.questionmark")
                        Text(ledger?.verified == true ? Tr("账本已核对") : Tr("账本待核对"))
                    }
                    .font(pf(11, .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.10), in: Capsule())
                }

                Spacer(minLength: 12)

                Button {
                    toggleBalancePrivacy()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Tr("可用余额"))
                            .font(pf(12.5, .medium))
                            .foregroundStyle(.white.opacity(0.56))

                        Group {
                            if balanceVisible {
                                StarPayAmount(value: balance, role: .hero, color: .white)
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("¥")
                                        .font(moneySymbolFont(17, .bold))
                                        .baselineOffset(13)
                                    Text(" ********")
                                        .font(pfMoney(39, .bold))
                                        .tracking(1.2)
                                }
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            }
                        }
                        .padding(.top, 3)

                        HStack(spacing: 5) {
                            if faceBusy {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: balanceVisible ? "checkmark.shield.fill" : "faceid")
                            }
                            Text(balanceVisible ? Tr("已在本次页面验证") : Tr("轻点使用面容 ID 查看"))
                        }
                        .font(pf(10.5, .medium))
                        .foregroundStyle(.white.opacity(0.48))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                HStack(spacing: 11) {
                    StarPayChip(width: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(XYPay.cardLine)
                            .font(pf(10.5, .medium))
                            .foregroundStyle(.white.opacity(0.46))
                        Text("•• \(XYPay.tail(app.me?.id ?? app.me?.username ?? "xingyan"))")
                            .font(pfExact(8.5, .bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.30))
                    }
                    Spacer(minLength: 8)
                    StarPayHologram(size: 32)
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(height: 208)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var paymentPrimaryActions: some View {
        HStack(spacing: 10) {
            NavigationLink {
                PayCodePage()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                    Text(Tr("付款"))
                        .font(pf(17, .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.56)
                }
                .foregroundStyle(Color.dyn(0xFFFFFF, 0x000000))
                .padding(.horizontal, 17)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Color.dyn(0x000000, 0xFFFFFF),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(PayPrimaryActionPressStyle())
            .accessibilityLabel(Tr("付款"))

            NavigationLink {
                ReceiveCodePage()
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(C.label)
                    .frame(width: 50, height: 50)
                    .background(
                        PayVisual.card,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(PayVisual.separator, lineWidth: 0.7)
                    }
            }
            .buttonStyle(PayPrimaryActionPressStyle())
            .accessibilityLabel(Tr("收款"))
        }
        .padding(.horizontal, 16)
    }

    private var goldCardSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("星言消费金卡"))
                        .font(pf(18, .bold))
                        .foregroundStyle(C.label)
                    Text("STAR PAY GOLD")
                        .font(pfExact(8.5, .bold))
                        .tracking(1.55)
                        .foregroundStyle(PayVisual.secondaryInk)
                }
                Spacer()
                if adminGoldPreview {
                    Text(Tr("管理灰度"))
                        .font(pf(10, .semibold))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(PayVisual.inset, in: Capsule())
                }
            }
            .padding(.horizontal, 3)

            StarPayGoldCardFace(
                cardholder: (app.me?.name ?? app.me?.username ?? "STAR PAY")
                    .uppercased(),
                last4: XYPay.tail(app.me?.id ?? app.me?.username ?? "xingyan"),
                cumulativeSpend: cumulativeSpend,
                adminPreview: adminGoldPreview
            )

            if adminGoldPreview && cumulativeSpend < Self.goldThreshold {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PayVisual.gold)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Tr("管理灰度预览"))
                            .font(pf(13, .semibold))
                            .foregroundStyle(C.label)
                        Text(Tr("普通用户累计消费满 ¥50,000 后自动解锁。"))
                            .font(pf(12.5))
                            .foregroundStyle(PayVisual.secondaryInk)
                        ProgressView(value: min(1, cumulativeSpend / Self.goldThreshold))
                            .tint(PayVisual.gold)
                    }
                }
                .padding(14)
                .background(PayVisual.card,
                            in: RoundedRectangle(cornerRadius: 14,
                                                 style: .continuous))
            }
        }
        .padding(.horizontal, 16)
    }

    private func toggleBalancePrivacy() {
        if balanceVisible {
            balanceVisible = false
            return
        }
        guard !faceBusy else { return }
        faceBusy = true
        let reason: String
        if Lang.isEnglish {
            reason = "Authenticate to view your Balance"
        } else if Lang.isRussian {
            reason = "Подтвердите личность, чтобы увидеть баланс"
        } else {
            reason = "验证身份，查看零钱余额"
        }
        Task {
            let result = await Biometrics.authenticate(reason: reason)
            faceBusy = false
            if result.ok {
                balanceVisible = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                balanceVisible = false
                if !result.message.isEmpty {
                    app.show(result.message)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaySectionLabel(text: Tr("钱包"))

            PayGroupCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        BillsView()
                    } label: {
                        quickActionRow(Tr("账单"),
                                       symbol: "list.bullet.rectangle.portrait.fill",
                                       tint: PayVisual.success)
                    }
                    .buttonStyle(MenuPressStyle())
                    HairLine(inset: 58)
                    NavigationLink {
                        CardsView()
                    } label: {
                        quickActionRow(Tr("卡包"),
                                       symbol: "rectangle.stack.fill",
                                       tint: PayVisual.gold)
                    }
                    .buttonStyle(MenuPressStyle())
                    HairLine(inset: 58)
                    NavigationLink {
                        AccountSecurityView()
                    } label: {
                        quickActionRow(Tr("支付安全"),
                                       symbol: "lock.shield.fill",
                                       tint: PayVisual.warning)
                    }
                    .buttonStyle(MenuPressStyle())
                    HairLine(inset: 58)
                    NavigationLink {
                        VirtualCardView()
                    } label: {
                        quickActionRow(Tr("虚拟卡"),
                                       symbol: "creditcard.fill",
                                       tint: PayVisual.tint)
                    }
                    .buttonStyle(MenuPressStyle())
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var ledgerSummaryStrip: some View {
        if let ledger {
            HStack(spacing: 18) {
                summaryMetric(Tr("收入"), ledger.income, PayVisual.success)
                Rectangle()
                    .fill(PayVisual.separator)
                    .frame(width: 0.5, height: 28)
                summaryMetric(Tr("支出"), ledger.expense, C.label)
            }
            .padding(.horizontal, 22)
        }
    }

    private func summaryMetric(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(pf(10.5, .medium))
                .foregroundStyle(PayVisual.secondaryInk)
            if balanceVisible {
                StarPayAmount(value: value, role: .metric, color: color)
            } else {
                Text("¥ ***")
                    .font(pfMoney(13.5, .semibold))
                    .foregroundStyle(PayVisual.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickActionRow(_ title: String,
                                symbol: String,
                                tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(pf(16))
                .foregroundStyle(C.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PayVisual.secondaryInk.opacity(0.72))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var transactionFeed: some View {
        if let entries = ledger?.entries, !entries.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Tr("最近交易"))
                        .font(pf(20, .semibold))
                        .foregroundStyle(C.label)
                    Spacer()
                    Text("\(entries.count)")
                        .font(pfMoney(12.5, .medium))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)

                ForEach(ledgerDays(entries)) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayTitle(group.day))
                            .font(pf(13, .semibold))
                            .foregroundStyle(PayVisual.secondaryInk)
                            .padding(.horizontal, 4)

                        PayGroupCard {
                            VStack(spacing: 0) {
                                ForEach(Array(group.entries.enumerated()),
                                        id: \.element.id) { index, entry in
                                    transactionRow(entry)
                                    if index < group.entries.count - 1 {
                                        HairLine(inset: 58)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        } else if !loading {
            VStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(PayVisual.secondaryInk)
                Text(Tr("还没有支付消息"))
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Text(Tr("每一笔收付款、转账、红包和退款都会出现在这里"))
                    .font(pf(12.5))
                    .foregroundColor(PayVisual.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private func transactionRow(_ entry: LedgerBillEntry) -> some View {
        let incoming = entry.direction == "in"
        return Button {
            selectedLedger = entry
        } label: {
            HStack(spacing: 12) {
                Image(systemName: incoming
                      ? "arrow.down.left"
                      : "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(incoming ? PayVisual.success : PayVisual.tint)
                    .frame(width: 38, height: 38)
                    .background(
                        (incoming ? PayVisual.success : PayVisual.tint).opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.reason.isEmpty ? (incoming ? Tr("收款") : Tr("付款")) : entry.reason)
                        .font(pf(15.5))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(clock(entry.at) + " · " + Tr("交易成功"))
                        .font(pf(11.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                StarPayAmount(value: entry.delta,
                              role: .row,
                              color: incoming ? PayVisual.success : C.label,
                              sign: incoming ? "+" : "-")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
    }

    private func ledgerDetail(_ entry: LedgerBillEntry) -> some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("支付消息详情"), back: { selectedLedger = nil })
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: entry.direction == "in"
                              ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, entry.direction == "in"
                                             ? PayVisual.success : PayVisual.tint)
                        StarPayAmount(value: entry.delta,
                                      role: .detail,
                                      color: C.label,
                                      sign: entry.direction == "in" ? "+" : "-")
                        Text(entry.reason.isEmpty ? Tr("支付交易") : entry.reason)
                            .font(pf(15))
                            .foregroundColor(PayVisual.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)

                    PayGroupCard {
                        VStack(spacing: 0) {
                            PayDetailRow(title: Tr("交易时间"), value: TimeFmt.bill(entry.at))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("方向"), value: entry.direction == "in" ? Tr("收入") : Tr("支出"))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("交易前余额"), value: "¥" + moneyFmt(entry.before))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("交易后余额"), value: "¥" + moneyFmt(entry.after))
                            HairLine(inset: 18)
                            PayDetailRow(title: Tr("交易单号"), value: entry.id, copyValue: entry.id)
                            if !entry.ref.isEmpty {
                                HairLine(inset: 18)
                                PayDetailRow(title: Tr("关联单号"), value: entry.ref, copyValue: entry.ref)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Text(Tr("此消息由星言支付自动生成，可作为账本核对凭证。"))
                        .font(pf(11.5))
                        .foregroundColor(PayVisual.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, max(24, L.safeBottom + 12))
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func ledgerDays(_ entries: [LedgerBillEntry]) -> [LedgerDayGroup] {
        var order: [String] = []
        var map: [String: [LedgerBillEntry]] = [:]
        for entry in entries {
            let day = TimeFmt.billDayKey(entry.at)
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(entry)
        }
        return order.map { LedgerDayGroup(day: $0, entries: map[$0] ?? []) }
    }

    private func dayTitle(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar.current
        parser.timeZone = TimeZone.current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Lang.isEnglish ? "en_US" : (Lang.isRussian ? "ru_RU" : "zh_CN"))
        formatter.dateFormat = Lang.isEnglish ? "MMM d" : (Lang.isRussian ? "d MMM" : "M月d日")
        return formatter.string(from: date)
    }

    private func clock(_ value: String) -> String {
        guard let date = TimeFmt.date(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
