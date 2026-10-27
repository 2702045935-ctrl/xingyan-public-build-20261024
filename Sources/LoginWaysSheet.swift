import SwiftUI

struct LoginWaysSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onPhone: () -> Void
    let onPassword: () -> Void
    let onFace: () -> Void
    let onVoice: () -> Void

    var onPair: (() -> Void)? = nil

    private struct Way: Identifiable {
        let id: String
        let title: String
        let sub: String
        let symbol: String
        let color: Color
    }

    private var ways: [Way] {
        var a: [Way] = [Way(id: "face", title: Tr("人脸识别登录"), sub: Tr("用面容直接进"), symbol: "faceid",
                            color: C.green),
                        Way(id: "voice", title: Tr("声音锁登录"), sub: Tr("读出屏幕上的数字"), symbol: "waveform",
                            color: C.green),
                        Way(id: "phone", title: Tr("手机号登录"), sub: Tr("短信验证码"), symbol: "phone.fill",
                            color: Color(hex: 0x3D83E7)),
                        Way(id: "pass", title: Tr("账号密码登录"), sub: Tr("用用户名和密码"), symbol: "key.fill",
                            color: Color(hex: 0x5B6673))]
        if onPair != nil {
            a.append(Way(id: "pair", title: Tr("在另一台设备上确认登录"),
                         sub: Tr("扫码或输数字，和微信一样"), symbol: "qrcode.viewfinder",
                         color: Color(hex: 0x6366F1)))
        }
        return a
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(Tr("更多登录方式"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                    ForEach(ways) { w in
                        HairLine(inset: 16)
                        Button {
                            dismiss()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                switch w.id {
                                case "face":  onFace()
                                case "voice": onVoice()
                                case "phone": onPhone()
                                case "pair":  onPair?()
                                default:      onPassword()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(w.color)
                                    Image(systemName: w.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.title).font(pf(16.5)).foregroundColor(C.label)
                                    Text(w.sub).font(pf(12)).foregroundColor(C.subLabel)
                                }
                                Spacer(minLength: 0)
                                Chevron(size: 9, line: 1.6)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 62)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MenuPressStyle())
                    }
                }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button { dismiss() } label: {
                    Text(Tr("取消"))
                        .font(pf(17)).foregroundColor(C.label)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(C.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, max(10, L.safeBottom))
        }
        .presentationDetents([.height(CGFloat(46 + 62 * ways.count) + 56 + 8 + 18 + L.safeBottom)])
        .presentationDragIndicator(.hidden)
    }
}
