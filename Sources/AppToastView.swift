import SwiftUI

enum AppToastTone: Equatable {
    case success
    case warning
    case info

    var tint: Color {
        switch self {
        case .success: return Color(hex: 0x30D158)
        case .warning: return Color(hex: 0xFF9F0A)
        case .info: return OrbitTheme.jade
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark"
        case .warning: return "exclamationmark"
        case .info: return "info"
        }
    }
}

struct AppToastNotice: Identifiable, Equatable {
    let id: UUID
    let text: String
    let tone: AppToastTone
    let duration: TimeInterval

    init(text: String, tone: AppToastTone? = nil) {
        self.id = UUID()
        self.text = text
        self.tone = tone ?? Self.inferTone(text)
        self.duration = self.tone == .warning ? 2.8 : 2.4
    }

    private static func inferTone(_ raw: String) -> AppToastTone {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let warningHints = [
            "失败", "错误", "无法", "不能", "没保存", "未保存", "请重试",
            "暂未保存", "failed", "error", "couldn't", "unable", "try again",
            "ошиб", "не удалось"
        ]
        if warningHints.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return .warning
        }
        let successHints = [
            "已", "成功", "完成", "换好", "更新", "保存", "上传", "设置",
            "updated", "saved", "uploaded", "complete", "готов", "обнов",
            "сохран"
        ]
        if successHints.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return .success
        }
        return .info
    }
}

struct AppToastView: View {
    let notice: AppToastNotice

    @Environment(\.colorScheme) private var scheme
    @State private var progress: CGFloat = 1

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(notice.tone.tint.opacity(scheme == .dark ? 0.20 : 0.14))
                Image(systemName: notice.tone.symbol)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(notice.tone.tint)
            }
            .frame(width: 26, height: 26)

            Text(notice.text)
                .font(pfStyled(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: min(360, max(220, L.width - 36)))
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(scheme == .dark
                      ? Color(hex: 0x1C1C1E).opacity(0.82)
                      : Color.white.opacity(0.84))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(scheme == .dark
                        ? Color.white.opacity(0.10)
                        : Color.black.opacity(0.055),
                        lineWidth: 0.6)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(notice.tone.tint.opacity(0.42))
                    .frame(
                        width: max(0, proxy.size.width * progress),
                        height: 1.5
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
            .frame(height: 2)
        }
        .shadow(
            color: Color.black.opacity(scheme == .dark ? 0.34 : 0.13),
            radius: 18,
            y: 8
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.text)
        .accessibilityAddTraits(.isStaticText)
        .task(id: notice.id) {
            progress = 1
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: max(0.4, notice.duration - 0.1))) {
                progress = 0
            }
        }
    }
}
