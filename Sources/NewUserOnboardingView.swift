import SwiftUI
import UIKit

private struct OnboardingFeature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String

    static let all: [OnboardingFeature] = [
        .init(id: "chat", symbol: "bubble.left.and.bubble.right.fill",
              title: "聊天与通话", detail: "单聊、群聊、语音和视频通话"),
        .init(id: "discover", symbol: "safari.fill",
              title: "动态与服务", detail: "朋友圈、视频号、小程序和常用服务"),
        .init(id: "security", symbol: "lock.shield.fill",
              title: "账号与安全", detail: "登录设备、隐私权限和安全设置可随时管理")
    ]
}

private struct OnboardingInterest: Identifiable {
    let id: String
    let symbol: String

    static let all: [OnboardingInterest] = [
        .init(id: "穿搭", symbol: "tshirt.fill"),
        .init(id: "美食", symbol: "fork.knife"),
        .init(id: "旅行", symbol: "airplane"),
        .init(id: "摄影", symbol: "camera.fill"),
        .init(id: "运动", symbol: "figure.run"),
        .init(id: "音乐", symbol: "music.note"),
        .init(id: "宠物", symbol: "pawprint.fill"),
        .init(id: "游戏", symbol: "gamecontroller.fill"),
        .init(id: "阅读", symbol: "book.fill"),
        .init(id: "数码", symbol: "desktopcomputer"),
        .init(id: "美妆", symbol: "sparkles"),
        .init(id: "生活", symbol: "sun.max.fill")
    ]
}

struct NewUserOnboardingView: View {
    @EnvironmentObject private var app: AppState
    @State private var step = 0
    @State private var avatar: UIImage?
    @State private var avatarPath = ""
    @State private var showPicker = false
    @State private var uploading = false
    @State private var saving = false
    @State private var error = ""
    @State private var appeared = false
    @State private var selectedInterests: Set<String> = []

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 0) {
                heading

                Group {
                    if step == 0 {
                        avatarStep
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        welcomeStep
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomAction
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, max(16, L.safeBottom))
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { image in
                avatar = image
                uploadAvatar(image)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            Color.dyn(0xF7F8F7, 0x121214).ignoresSafeArea()
            Circle()
                .fill(Color(hex: 0x07C160).opacity(0.12))
                .frame(width: 310, height: 310)
                .blur(radius: 46)
                .offset(x: -155, y: -310)
            Circle()
                .fill(Color(hex: 0x3D7EFF).opacity(0.09))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: 165, y: 285)
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var heading: some View {
        HStack {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [Color(hex: 0x07C160), Color(hex: 0x16B979)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 28, height: 28)
                Text("星言")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(C.label)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index <= step
                              ? LinearGradient(colors: [Color(hex: 0x07C160), Color(hex: 0x16B979)],
                                               startPoint: .leading, endPoint: .trailing)
                              : LinearGradient(colors: [C.subLabel.opacity(0.18), C.subLabel.opacity(0.18)],
                                               startPoint: .leading, endPoint: .trailing))
                        .frame(width: index == step ? 28 : 12, height: 5)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
    }

    private var avatarStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("完善个人资料")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(C.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 44)
                Text("设置一张清晰头像，方便联系人和群成员识别你。")
                    .font(.system(size: 14.5))
                    .foregroundColor(C.subLabel)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                Button { showPicker = true } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: 0x07C160), Color(hex: 0x25C885), Color(hex: 0x82E5B9)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 172, height: 172)
                            .shadow(color: Color(hex: 0x07C160).opacity(0.20), radius: 25, y: 14)

                        if let avatar {
                            Image(uiImage: avatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 158, height: 158)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.dyn(0xFFFFFF, 0x232326))
                                .frame(width: 158, height: 158)
                            VStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(C.subLabel.opacity(0.62))
                                if uploading {
                                    ProgressView().tint(Color(hex: 0x07C160))
                                } else {
                                    Label("选择头像", systemImage: "camera.fill")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(hex: 0x07C160))
                                }
                            }
                        }

                        if avatar != nil && !uploading {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(Color.black.opacity(0.58)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                                        .offset(x: -5, y: -5)
                                }
                            }
                            .frame(width: 172, height: 172)
                        }
                    }
                    .padding(.top, 48)
                }
                .buttonStyle(OnboardingPressStyle())
                .disabled(uploading)

                Text(avatar == nil ? "点击上传你的专属头像" : "头像已就绪，可以继续了")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(avatar == nil ? C.subLabel : Color(hex: 0x18A66A))
                    .padding(.top, 22)

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(C.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                Text("建议使用本人照片或能代表你的头像\n之后可以在「我 → 个人资料」里更换")
                    .font(.system(size: 12.5))
                    .foregroundColor(C.subLabel.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 24)
            }
        }
    }

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("选择你的兴趣")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(C.label)
                    .padding(.top, 36)
                Text("至少选择 2 个，最多 5 个。我们会据此为你推荐更有兴趣的内容。")
                    .font(.system(size: 14.5))
                    .foregroundColor(C.subLabel)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(OnboardingInterest.all) { interest in
                        interestCard(interest)
                    }
                }
                .padding(.top, 26)

                HStack {
                    Text("已选择 \(selectedInterests.count) / 5")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(selectedInterests.count >= 2 ? Color(hex: 0x18A66A) : C.subLabel)
                    Spacer(minLength: 0)
                    Text(selectedInterests.count < 2 ? "还需选择 \(2 - selectedInterests.count) 个" : "可以继续")
                        .font(.system(size: 12))
                        .foregroundColor(C.subLabel)
                }
                .padding(.top, 14)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: 0x07C160))
                        .padding(.top, 1)
                    Text("头像和资料之后可在「我 → 个人信息」中修改；登录设备与隐私权限在「我 → 设置」中管理。")
                        .font(.system(size: 12.5))
                        .foregroundColor(C.subLabel)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color(hex: 0x07C160).opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color(hex: 0x07C160).opacity(0.18), lineWidth: 0.7)
                )
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private func interestCard(_ interest: OnboardingInterest) -> some View {
        let selected = selectedInterests.contains(interest.id)
        return Button {
            error = ""
            if selected {
                selectedInterests.remove(interest.id)
            } else if selectedInterests.count >= 5 {
                error = "最多选择 5 个兴趣分类"
            } else {
                selectedInterests.insert(interest.id)
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: interest.symbol)
                    .font(.system(size: 19, weight: .medium))
                Text(interest.id)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
            }
            .foregroundColor(selected ? .white : C.label)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected
                          ? LinearGradient(colors: [Color(hex: 0x07C160), Color(hex: 0x16B979)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.dyn(0xFFFFFF, 0x1D1D20),
                                                    Color.dyn(0xFFFFFF, 0x1D1D20)],
                                           startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.25) : C.hairline, lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(OnboardingPressStyle())
    }

    private func featureCard(_ feature: OnboardingFeature) -> some View {
        HStack(spacing: 13) {
            Image(systemName: feature.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: 0x07C160))
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x07C160).opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(C.label)
                Text(feature.detail)
                    .font(.system(size: 12.5))
                    .foregroundColor(C.subLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.dyn(0xFFFFFF, 0x1D1D20).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.55)
        )
    }

    private var bottomAction: some View {
        VStack(spacing: 13) {
            if !error.isEmpty && step == 1 {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(C.red)
            }

            Button {
                if step == 0 {
                    guard !avatarPath.isEmpty else {
                        error = uploading ? "头像正在上传，请稍候" : "请先选择一张头像"
                        return
                    }
                    error = ""
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = 1 }
                } else {
                    finish()
                }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView().tint(.white)
                    }
                    Text(step == 0 ? "继续" : saving ? "正在完成设置…" : "完成，进入星言")
                        .font(.system(size: 16, weight: .semibold))
                    if step == 0 && !saving {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: canContinue
                              ? [Color(hex: 0x07C160), Color(hex: 0x16B979)]
                              : [C.subLabel.opacity(0.28), C.subLabel.opacity(0.28)],
                        startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: canContinue ? Color(hex: 0x07C160).opacity(0.20) : .clear,
                        radius: 16, y: 8)
            }
            .buttonStyle(OnboardingPressStyle())
            .disabled(saving || uploading || (step == 1 && selectedInterests.count < 2))

            if step == 1 {
                Button {
                    error = ""
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { step = 0 }
                } label: {
                    Text("返回上一步")
                        .font(.system(size: 13))
                        .foregroundColor(C.subLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
    }

    private var canContinue: Bool {
        if step == 0 { return !avatarPath.isEmpty && !uploading && !saving }
        return !saving && selectedInterests.count >= 2
    }

    private func uploadAvatar(_ image: UIImage) {
        uploading = true
        error = ""
        Task {
            do {
                let path = try await API.shared.upload(image: image)
                await MainActor.run {
                    avatarPath = path
                    uploading = false
                }
            } catch {
                await MainActor.run {
                    avatar = nil
                    avatarPath = ""
                    uploading = false
                    self.error = (error as? APIError)?.errorDescription ?? "头像上传失败，请重试"
                }
            }
        }
    }

    private func finish() {
        guard !saving else { return }
        guard selectedInterests.count >= 2 else {
            error = "请至少选择两个兴趣分类"
            return
        }
        saving = true
        error = ""
        Task {
            do {
                let interests = OnboardingInterest.all
                    .map(\.id)
                    .filter { selectedInterests.contains($0) }
                try await app.finishNewUserOnboarding(avatar: avatarPath, interests: interests)
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    saving = false
                }
            } catch {
                await MainActor.run {
                    saving = false
                    self.error = (error as? APIError)?.errorDescription ?? "保存失败，请重试"
                }
            }
        }
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
