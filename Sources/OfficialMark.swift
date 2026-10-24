import SwiftUI

/// 官方账号名称后的玻璃胶囊标识。
struct OfficialMark: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(Tr("官方"))
            .font(pf(10.5, .medium))
            .foregroundColor(C.label.opacity(0.86))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background {
                GlassBackground(shape: Capsule(style: .continuous),
                                opacity: scheme == .dark ? 0.64 : 0.78,
                                edgeAlpha: scheme == .dark ? 0.42 : 0.56,
                                shadow: false,
                                seed: 0.74,
                                native: true)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(scheme == .dark ? 0.14 : 0.48), lineWidth: 0.6)
            }
            .accessibilityLabel(Tr("官方账号"))
    }
}

extension Chat {
    var showsOfficialMark: Bool {
        !(oaId ?? "").isEmpty || oaDigest == true
    }
}
