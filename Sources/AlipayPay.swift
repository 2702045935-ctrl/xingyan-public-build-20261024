import SwiftUI
import UIKit

enum AliPay {

    static var name: String { UIConfig.text("alipayName", "支付宝") }

    static var on: Bool { UIConfig.num("alipayOn", 1) > 0 }

    @discardableResult
    static func open(_ orderStr: String) -> Bool {
        guard !orderStr.isEmpty else { return false }
        let enc = orderStr.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard !enc.isEmpty else { return false }
        for head in ["alipays://platformapi/startapp?appId=20000067&url=",
                     "alipay://platformapi/startapp?appId=20000067&url="] {
            if let u = URL(string: head + enc) {
                UIApplication.shared.open(u, options: [:], completionHandler: nil)
                return true
            }
        }
        return false
    }

    static func waitPaid(orderId: String, tryTimes: Int = 30) async -> Bool {
        var left = max(1, tryTimes)
        while left > 0 {
            left -= 1
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return false }
            if await API.shared.alipayStatus(id: orderId).paid { return true }
        }
        return false
    }
}

struct AliPayWaitingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let amount: Double
    let orderId: String

    var sync: (() async -> Void)? = nil

    var onResult: (Bool) -> Void

    @State private var checking = false
    @State private var tip = ""
    @State private var poll: Task<Void, Never>? = nil

    private let aliBlue = Color(hex: 0x1677FF)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { finish(false) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Image(systemName: "a.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(aliBlue)
                .padding(.top, 4)
            Text(Tr("支付宝付款"))
                .font(pf(16, .medium)).foregroundColor(C.label).padding(.top, 10)
            Text("¥" + moneyFmt(amount))
                .font(pfMoney(32, .medium)).foregroundColor(C.label).padding(.top, 6)
            Text(orderId)
                .font(pf(12)).foregroundColor(C.subLabel).padding(.top, 4)
            Text(tip.isEmpty ? Tr("付完会自动回到这里，我每 2 秒查一次") : tip)
                .font(pf(13)).foregroundColor(C.subLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24).padding(.top, 14)
            Button { check() } label: {
                Text(checking ? Tr("查询中…") : Tr("我已付好，立刻查一下"))
                    .font(pf(15.5, .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(aliBlue))
            }
            .buttonStyle(.plain)
            .disabled(checking)
            .padding(.horizontal, 24).padding(.top, 18)
            Button { finish(false) } label: {
                Text(Tr("先不付了，去我的订单"))
                    .font(pf(14)).foregroundColor(C.subLabel).frame(height: 40)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .background(C.pageBg)
        .onAppear { startAutoCheck() }
        .onDisappear { poll?.cancel() }
    }

    private func startAutoCheck() {
        poll = Task {

            if let sync { await sync() }

            do {
                let r = try await API.shared.alipayCreate(orderId: orderId)
                if r.orderStr.isEmpty {
                    await MainActor.run { tip = Tr("支付宝还没配好：后台「支付配置」里把 APPID 和密钥填上再试。") }
                    return
                }
                _ = await MainActor.run { AliPay.open(r.orderStr) }
            } catch {
                await MainActor.run {
                    tip = Tr("发起支付失败（订单已经留在「待付款」，稍后再点付款）。")
                }
                return
            }

            let ok = await AliPay.waitPaid(orderId: orderId, tryTimes: 45)
            if Task.isCancelled { return }
            await MainActor.run {
                if ok { finish(true) }
                else { tip = Tr("还没查到这笔付款。支付宝那边付成功了就先别急，订单在「待付款」里，稍后再点一次。") }
            }
        }
    }

    private func check() {
        guard !checking else { return }
        checking = true
        tip = ""
        Task {
            let r = await API.shared.alipayStatus(id: orderId)
            await MainActor.run {
                checking = false
                if r.paid { finish(true) }
                else { tip = Tr("还没收到这笔钱。付过了的话等 5 秒再点一次；没付就点左上角关掉，订单会留在「待付款」。") }
            }
        }
    }

    private func finish(_ paid: Bool) {
        poll?.cancel()
        onResult(paid)
        dismiss()
    }
}
