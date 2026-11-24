import SwiftUI

struct NeedRealNameView: View {
    var onClose: () -> Void
    var onVerified: () -> Void
    @EnvironmentObject var app: AppState
    @State private var showRealName = false

    init(onClose: @escaping () -> Void, onVerified: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.onVerified = onVerified
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("设置钱包"), back: { onClose() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppDesign.Spacing.xl) {
                    identityHeader
                    setupSteps
                    continueButton
                    privacyNotice
                    Color.clear.frame(height: AppDesign.Control.badgeHeight)
                }
                .padding(.horizontal, AppDesign.Spacing.lg)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .swipeBack { onClose() }
        .sheet(isPresented: $showRealName) {
            RealNameView {
                showRealName = false
                onVerified()
            }
            .environmentObject(app)
        }
    }

    private var identityHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: AppDesign.Radius.overlay, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(Color(uiColor: .systemBackground))
            }
            Text(Tr("身份验证"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(C.label)
            Text(Tr("验证身份后即可启用零钱、转账、收付款与提现。聊天、通话和生活圈不受影响。"))
                .font(pf(14))
                .foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
        }
        .padding(.top, AppDesign.Spacing.xl)
    }

    private var setupSteps: some View {
        VStack(spacing: 0) {
            setupRow(number: "1",
                     symbol: "person.text.rectangle",
                     title: Tr("核对身份信息"),
                     detail: Tr("填写真实姓名与身份证号"))
            HairLine(inset: 58)
            setupRow(number: "2",
                     symbol: "faceid",
                     title: Tr("人脸验证"),
                     detail: Tr("确认由本人完成设置"))
            HairLine(inset: 58)
            setupRow(number: "3",
                     symbol: "checkmark.shield",
                     title: Tr("启用钱包"),
                     detail: Tr("验证完成后自动返回钱包"))
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.5)
        )
    }

    private var continueButton: some View {
        Button {
            showRealName = true
        } label: {
            Text(Tr("继续"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .frame(height: AppDesign.Control.largeControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.Radius.row, style: .continuous)
                        .fill(Color.primary)
                )
        }
        .buttonStyle(.plain)
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(C.green)
            Text(Tr("身份资料只保存在星言服务器；身份证号加密保存，页面只显示脱敏信息。"))
                .font(AppDesign.Typography.caption)
                .foregroundColor(C.subLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppDesign.Spacing.md)
        .background(C.cardBg.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.row, style: .continuous))
    }

    private func setupRow(number: String, symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(C.label)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(pf(15, .semibold))
                    .foregroundColor(C.label)
                Text(detail)
                    .font(AppDesign.Typography.caption)
                    .foregroundColor(C.subLabel)
            }
            Spacer(minLength: 8)
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(C.subLabel)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .frame(minHeight: 64)
    }
}
