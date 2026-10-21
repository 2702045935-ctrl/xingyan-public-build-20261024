import SwiftUI

struct ContactCardWechat: View {
    let name: String
    let wxId: String
    let region: String
    let avatarPath: String
    let isEyes: Bool

    let remarkLine: String

    let permLine: String

    let moreLine: String

    let momentsHint: String
    let thumbs: [String]
    let isBot: Bool

    let relation: String

    let onClose: () -> Void
    let onAvatar: () -> Void
    let onMessage: () -> Void
    let onVoice: () -> Void
    let onVideo: () -> Void
    let onAICall: () -> Void
    let onMoments: () -> Void
    let onRemark: () -> Void
    let onPerm: () -> Void
    let onMore: () -> Void
    let onMenu: () -> Void
    let onApply: () -> Void
    let onAgree: () -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var askCall = false

    @State private var appeared = false

    @State private var copied: String? = nil

    private var green: Color { UIConfig.color("cardWechatGreen", 0x07C160, 0x07C160) }
    private var pageBg: Color { UIConfig.color("cardWechatBg", 0xEDEDED, 0x111111) }
    private var cardBg: Color { scheme == .dark ? Color(hex: 0x252525) : Color.white }
    private var ink: Color { scheme == .dark ? Color(hex: 0xEDEDED) : Color(hex: 0x191919) }
    private var gray: Color { scheme == .dark ? Color(hex: 0x7F7F7F) : Color(hex: 0x888888) }
    private var hair: Color { scheme == .dark ? Color(white: 1, opacity: 0.08) : Color(hex: 0xE6E6E6) }
    private var avatarSize: CGFloat { UIConfig.num("cardWechatAvatar", 64) }
    private var nameSize: CGFloat { UIConfig.num("cardWechatNameSize", 20) }
    private var thumbSize: CGFloat { UIConfig.num("cardWechatThumb", 40) }
    private var rowH: CGFloat { UIConfig.num("cardWechatRowH", 54) }
    private var btnH: CGFloat { UIConfig.num("cardWechatBtnH", 46) }
    private var radius: CGFloat { UIConfig.num("cardWechatRadius", 8) }

    var body: some View {
        VStack(spacing: 0) {
            nav
            ScrollView {
                VStack(spacing: 0) {
                    header
                    gap

                    card { friendInfoCard }
                    gap
                    momentsRow
                    gap

                    card {
                        actionRow(Tr("发消息"), "bubble.left.and.bubble.right.fill") { onMessage() }
                        hairline
                        actionRow(secondTitle, "video.fill", enabled: secondEnabled) { secondTap() }
                    }
                    Spacer(minLength: 28)
                }

                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
            }
            .background(pageBg)
        }
        .background(pageBg.ignoresSafeArea())
        .onAppear { withAnimation(.easeOut(duration: 0.30)) { appeared = true } }

        .overlay(alignment: .bottom) {
            if let c = copied {
                Text(c)
                    .font(pf(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .padding(.bottom, 64)
                    .transition(.opacity)
            }
        }
        .onChange(of: copied) { v in
            guard v != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) { copied = nil }
            }
        }
        .confirmationDialog(Tr("音视频通话"), isPresented: $askCall, titleVisibility: .visible) {
            Button(Tr("语音通话")) { onVoice() }
            Button(Tr("视频通话")) { onVideo() }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private var nav: some View {
        NavBar(title: "", back: { onClose() }) {
            Button { onMenu() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17))
                    .foregroundColor(ink)
                    .frame(width: 54, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("更多"))
        }
        .background(pageBg)
    }

    private var header: some View {

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(name)
                    .font(pf(nameSize, .semibold))
                    .foregroundColor(ink)
                    .lineLimit(2)
                Text(wxId)
                    .font(pf(14))
                    .foregroundColor(gray)
                    .lineLimit(1)

                    .copyOnLongPress(wxId) { msg in
                        withAnimation(.easeOut(duration: 0.15)) { copied = msg }
                    }
                Text(Tr("地区") + "：" + region)
                    .font(pf(14))
                    .foregroundColor(gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Group {
                if isEyes {
                    JarvisEyesAvatar(size: avatarSize)
                        .frame(width: avatarSize, height: avatarSize)
                } else {
                    Avatar(path: avatarPath, size: avatarSize, radius: radius)
                }
            }

            .overlay(RoundedRectangle(cornerRadius: radius + 1, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.90),
                                                Color(hex: 0xF0C24B).opacity(scheme == .dark ? 0.55 : 0.70),
                                                Color.white.opacity(0.25)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.50 : 0.10), radius: 6, y: 2)
            .contentShape(Rectangle())
            .onTapGesture { onAvatar() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)

        .background(
            LinearGradient(colors: [cardBg,
                                    scheme == .dark ? Color(hex: 0x1F1F1F) : Color(hex: 0xFCFCFC)],
                           startPoint: .top, endPoint: .bottom)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.40 : 0.04), radius: 8, y: 2)
    }

    private var friendInfoCard: some View {
        Button { onRemark() } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("朋友资料"))
                    .font(pf(16))
                    .foregroundColor(ink)
                Text(Tr("添加朋友的备注名、电话、标签、备忘、照片等，并设置朋友权限。"))
                    .font(pf(13))
                    .foregroundColor(gray)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ title: String, _ icon: String,
                           enabled: Bool = true,
                           _ tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(enabled ? Color(hex: 0x576B95) : gray)
                    .frame(width: 22)
                Text(title).font(pf(16.5)).foregroundColor(enabled ? ink : gray)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var momentsRow: some View {
        Button { onMoments() } label: {
            HStack(spacing: 10) {
                Text(Tr("朋友圈"))
                    .font(pf(16))
                    .foregroundColor(ink)
                Spacer(minLength: 8)
                if !thumbs.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(thumbs.prefix(3).indices, id: \.self) { i in
                            RemoteImage(path: thumbs[i])
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                } else {
                    Text(momentsHint.isEmpty ? Tr("暂无朋友圈动态") : Tr(momentsHint))
                        .font(pf(13.5))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .background(cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var buttons: some View {
        VStack(spacing: 0) {
            Button { onMessage() } label: {
                Text(Tr("发消息"))
                    .font(pf(17, .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: btnH)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(green))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Button { secondTap() } label: {
                Text(secondTitle)
                    .font(pf(17, .medium))
                    .foregroundColor(secondEnabled ? green : gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: btnH)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cardBg))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(secondEnabled ? green : hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!secondEnabled)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(cardBg)
    }

    private var secondTitle: String {
        if isBot { return Tr("语音通话") }
        switch relation {
        case "friend", "self": return Tr("音视频通话")
        case "incoming":       return Tr("同意好友申请")
        case "requested":      return Tr("已发送好友申请")
        default:               return Tr("添加到通讯录")
        }
    }

    private var secondEnabled: Bool { relation != "requested" }

    private func secondTap() {
        if isBot { onAICall(); return }
        switch relation {
        case "friend", "self": askCall = true
        case "incoming":       onAgree()
        case "requested":      break
        default:               onApply()
        }
    }

    private func row(_ title: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Text(title)
                    .font(pf(16))
                    .foregroundColor(ink)
                Spacer(minLength: 8)
                if !value.isEmpty {
                    Text(value)
                        .font(pf(14))
                        .foregroundColor(gray)
                        .lineLimit(1)
                }
                Chevron(size: 9, line: 1.6)
            }
            .padding(.horizontal, 16)
            .frame(height: rowH)
            .background(cardBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.045), radius: 7, y: 1.5)
    }

    private var hairline: some View {
        Rectangle().fill(hair).frame(height: 0.6).padding(.leading, 16)
    }

    private var gap: some View {
        Rectangle().fill(pageBg).frame(height: 8)
    }
}
