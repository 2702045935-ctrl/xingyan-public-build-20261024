import SwiftUI
import Foundation

@MainActor
final class EyesStore: ObservableObject {
    static let shared = EyesStore()

    private static var cacheKey: String {
        var uid = ""
        if let s = UserDefaults.standard.string(forKey: "chris.lastUserJSON"),
           let d = s.data(using: .utf8),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let id = o["id"] as? String, !id.isEmpty {
            uid = id
        }
        return "chris.eyes.tier" + (uid.isEmpty ? "" : "." + uid)
    }

    @Published var tier: String
    @Published var paid = false
    @Published var price: Double = 40
    @Published var balance: Double = 0
    @Published var loaded = false

    @Published var resolved: Bool

    init() {
        let cached = UserDefaults.standard.string(forKey: Self.cacheKey)
        tier = cached ?? "on"
        resolved = (cached != nil)
    }

    var eyesOn: Bool { tier != "off" }

    var navEyesOn: Bool { resolved && tier != "off" }

    var animated: Bool { tier == "on" }

    func primeFromCache() {
        guard let v = UserDefaults.standard.string(forKey: Self.cacheKey) else { return }
        if tier != v { tier = v }
        if !resolved { resolved = true }
    }

    func apply(_ info: API.EyesInfo) {

        let t = info.tier
        if tier != t {
            tier = t

            UserDefaults.standard.set(t, forKey: Self.cacheKey)
        }
        let p = info.paid ?? false
        if paid != p { paid = p }
        let pr = info.price ?? 40
        if price != pr { price = pr }
        let b = info.balance ?? balance
        if balance != b { balance = b }
        if !loaded { loaded = true }
        if !resolved { resolved = true }
    }

    func refresh() async {
        do {
            apply(try await API.shared.eyesState())
        } catch {

            if !resolved, API.shared.offline { resolved = true }
        }
    }

    func set(_ want: String) async -> String? {
        do {
            apply(try await API.shared.eyesSet(want))
            DiagLog.shared.note("小星档位改成 \(want)")
            return nil
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "设置失败，再试一次"
            DiagLog.shared.note("小星档位改 \(want) 失败：\(msg)")
            return msg
        }
    }
}

struct EyesSettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var eyes = EyesStore.shared

    @State private var confirmOn = false
    @State private var busy = false

    @State private var showAI = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("显示小星"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    GroupCard {
                        tierRow("on", Tr("开启小星"), priceText, Tr("会动"))
                        HairLine(inset: 16)
                        tierRow("static", Tr("静态小星"), Tr("免费"), Tr("不动"))
                        HairLine(inset: 16)
                        tierRow("off", Tr("关闭小星"), Tr("免费"), Tr("不显示"))
                    }
                    .padding(.top, 10)

                    Text(Tr("会话页顶栏那颗眼睛已经按你的要求去掉了（那台机器上顶栏会闪退）。\n现在这三档只管 AI 助手页里那颗眼睛：开启会眨眼会瞟、静态照样画但不跑动画、\n关闭就不画了。进 AI 助手：我 → 服务 → AI 助手。"))
                        .font(pf(12.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 4)

                    GroupCard {
                        HStack(spacing: 12) {
                            Text(Tr("零钱余额")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Text("¥" + moneyFmt(eyes.balance))
                                .font(pfMoney(16))
                                .foregroundColor(C.subLabel)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                    .padding(.top, 4)

                    Button {
                        openAI()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .medium))
                            Text(Tr("进入 AI 助手"))
                                .font(pf(16, .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.green))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Spacer().frame(height: 30)
                }
                .padding(.top, 6)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { if !eyes.loaded { await eyes.refresh() } }
        .confirmationDialog(Tr("开启小星（¥40，一次性，用零钱支付）"),
                            isPresented: $confirmOn, titleVisibility: .visible) {
            Button(Tr("确认支付 ¥") + moneyFmt(eyes.price)) { Task { await choose("on") } }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("买断之后一直有效，不再重复收费。"))
        }
        .fullScreenCover(isPresented: $showAI) {
            AIWorkspaceView().environmentObject(app)
        }
    }

    private var priceText: String {
        if eyes.tier == "on" && eyes.paid { return Tr("已开启") }
        if eyes.tier == "on" && !eyes.paid { return "¥" + moneyFmt(eyes.price) + Tr(" 一次性（还没付费）") }
        return "¥" + moneyFmt(eyes.price) + Tr(" 一次性")
    }

    private func tierRow(_ id: String, _ title: String, _ value: String, _ tag: String) -> some View {
        Button {
            if id == "on" && !eyes.paid && eyes.tier != "on" {
                confirmOn = true
            } else if id != eyes.tier {
                Task { await choose(id) }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(pf(16.5)).foregroundColor(C.label)
                    Text(value + " · " + tag).font(pf(12.5)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                if eyes.tier == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(C.green)
                }
                if busy && eyes.tier != id {
                    ProgressView().scaleEffect(0.75)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .disabled(busy)
    }

    private func choose(_ want: String) async {
        busy = true
        let err = await eyes.set(want)
        busy = false
        if let err = err { app.show(err) }
        else {
            app.me = try? await API.shared.me()
            app.show(want == "on" ? Tr("小星已开启") : (want == "static" ? Tr("已切成静态小星") : Tr("已关闭小星")))
        }
    }

    private func openAI() {
        showAI = true
    }
}
