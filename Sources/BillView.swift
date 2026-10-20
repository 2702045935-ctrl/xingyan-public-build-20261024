import SwiftUI
import UIKit

struct TransferInfo {
    var id = ""
    var amount: Double = 0
    var note = ""
    var status = "pending"
    var method = "balance"
    var fromId = ""
    var toId = ""
    var createdAt = ""
    var expiresAt: Double = 0
    var receivedAt = ""
    var refundedAt = ""
    var refundedBy = ""

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        id = (o["id"] as? String) ?? ""
        amount = (o["amount"] as? Double) ?? 0
        note = (o["note"] as? String) ?? ""
        status = (o["status"] as? String) ?? "pending"
        method = (o["method"] as? String) ?? "balance"
        fromId = (o["fromId"] as? String) ?? ""
        toId = (o["toId"] as? String) ?? ""
        createdAt = (o["createdAt"] as? String) ?? ""
        if let e = o["expiresAt"] as? Double { expiresAt = e }
        else if let e = o["expiresAt"] as? Int { expiresAt = Double(e) }
        receivedAt = (o["receivedAt"] as? String) ?? ""
        refundedAt = (o["refundedAt"] as? String) ?? ""
        refundedBy = (o["refundedBy"] as? String) ?? ""
    }

    var methodName: String { method == "card" ? "建设银行储蓄卡(2125)" : "零钱" }

    var refundClosed: Bool {
        guard !receivedAt.isEmpty, let d = TimeFmt.date(receivedAt) else { return false }
        return Date().timeIntervalSince(d) > 5 * 60 * 60
    }

    func statusText(mine: Bool) -> String {
        if status == "pending" { return mine ? "等待对方确认收钱" : "等待你确认收钱" }
        if status == "received" { return "已收款" }

        if !refundedBy.isEmpty, refundedBy == toId { return mine ? "已退还" : "对方已退还" }
        return "已退回"
    }

    var leftText: String {
        let ms = expiresAt - Date().timeIntervalSince1970 * 1000
        if !(ms > 0) { return "已到期" }
        let h = Int(ms / 3_600_000)
        let m = Int((ms.truncatingRemainder(dividingBy: 3_600_000)) / 60_000)
        if h >= 24 { return "1天内" }
        if h >= 1 { return "\(h)小时" + (m > 0 ? "\(m)分" : "") }
        return "\(m)分钟"
    }

    var billNo: String {
        let d = TimeFmt.date(createdAt)
        var stamp = "00000000000000"
        if let d = d {
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            func p(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
            stamp = "\(c.year ?? 0)" + p(c.month) + p(c.day) + p(c.hour) + p(c.minute) + p(c.second)
        }
        return "1000050001" + stamp + id.replacingOccurrences(of: "tr_", with: "").uppercased()
    }
}

struct BillDetailView: View {
    let chat: Chat
    let info: TransferInfo

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var live: TransferInfo?
    @State private var showMore = false
    @State private var showReceipt = false
    @State private var askRefund = false
    @State private var showKefu = false

    @State private var busy = false

    private var mine: Bool { info.fromId == (app.me?.id ?? "") }
    private var who: String { mine ? chat.name : (chat.lastMessage?.senderName ?? chat.name) }
    private var t: TransferInfo { live ?? info }

    private var peerAvatar: String { chat.avatar ?? "" }

    private var faint: Color { Color.dyn(0x737373, 0x9A9A9A) }

    private var titleText: String {
        if t.status == "pending" { return mine ? "待\(who)收款" : "\(who)向你转账" }
        if t.status == "received" { return mine ? "对方已收款" : "已收款" }
        return mine ? "已退回你的余额" : "已退回对方"
    }

    private var hintText: String {
        if t.status == "pending" {

            let left = t.leftText.hasSuffix("内") ? String(t.leftText.dropLast()) : t.leftText
            return mine ? "\(left)内对方未收款，将退还给你。" : "\(left)内未收款，将退还对方。"
        }
        if t.status == "received" { return "钱已存入" + (mine ? "对方" : "你的") + "零钱余额。" }
        return "超过 24 小时未收款，钱已原路退回。"
    }

    var body: some View {
        VStack(spacing: 0) {

            NavBar(title: "", back: { dismiss() }) {
                Button {
                    showMore = true
                } label: {
                    WeChatDots(size: 4.6, gap: 3.2)
                        .frame(width: 60, height: L.navH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {

                    Avatar(path: peerAvatar, size: 56, radius: 8)
                        .padding(.top, 40)

                    Text(mine ? "转账给 \(who)" : "\(who) 转账给你")
                        .font(pfExact(15))
                        .foregroundColor(faint)
                        .padding(.top, 14)

                    MoneyLabel(text: "¥" + money(t.amount), size: 50, curSize: 34,
                               topAlign: true, color: C.label, exact: true)
                        .padding(.top, 10)

                    Text(t.statusText(mine: mine))
                        .font(pfExact(16))
                        .foregroundColor(C.label)
                        .padding(.top, 14)

                    Text(hintText)
                        .font(pfExact(14))
                        .foregroundColor(faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .padding(.top, 8)

                    if t.status == "pending", mine {
                        Button { billAction() } label: {
                            Text(Tr("提醒对方收款"))
                                .font(pfExact(14.5))
                                .foregroundColor(C.link)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .padding(.top, 12)
                    }

                    Rectangle()
                        .fill(C.hairline)
                        .frame(height: 0.5)
                        .padding(.horizontal, 32)
                        .padding(.top, 31)

                    detailRow("转账时间", TimeFmt.bill(t.createdAt))
                    if !t.note.isEmpty { detailRow("转账说明", t.note) }
                    detailRow("支付方式", t.methodName)
                    detailRow("转账单号", t.billNo)
                    if t.status == "received" { detailRow("收款时间", TimeFmt.bill(t.receivedAt)) }
                    if t.status == "refunded" { detailRow("退回时间", TimeFmt.bill(t.refundedAt)) }

                    Spacer(minLength: 40)
                }
            }
            .background(C.cardBg)

            if t.status == "pending", !mine {
                VStack(spacing: 0) {
                    Rectangle().fill(C.hairline).frame(height: 0.5)
                    Button { billAction() } label: {
                        Text(Tr("确认收款"))
                            .font(pf(17, .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(C.green))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .background(C.cardBg)
            }

            if t.status == "received", !mine, t.refundClosed {
                VStack(spacing: 0) {
                    Rectangle().fill(C.hairline).frame(height: 0.5)
                    Text(Tr("收款超过 5 小时，不能再退回了"))
                        .font(pf(13.5))
                        .foregroundColor(C.subLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .background(C.cardBg)
            }
            if t.status == "received", !mine, !t.refundClosed {
                VStack(spacing: 0) {
                    Rectangle().fill(C.hairline).frame(height: 0.5)
                    Button { askRefund = true } label: {
                        Text(Tr("退还"))
                            .font(pf(16.5, .medium))
                            .foregroundColor(C.label)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background { CardGlassBox(radius: 6) }
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(C.hairline, lineWidth: 0.9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .background(C.cardBg)
            }

            Button {
                showReceipt = true
            } label: {
                Text(Tr("账单详情"))
                    .font(pfExact(14.5))
                    .foregroundColor(C.link)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)
            .background(C.cardBg)
        }
        .background(C.cardBg.ignoresSafeArea(edges: .bottom))
        .background(C.cardBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .task { await refreshTransfer() }

        .sheet(isPresented: $showReceipt) {
            BillReceiptView(chat: chat, info: t)
        }

        .sheet(isPresented: $showKefu) {
            KefuPage().environmentObject(app)
        }

        .confirmationDialog("退还 ¥" + money(t.amount) + " 给" + who + "？",
                            isPresented: $askRefund, titleVisibility: .visible) {
            Button(Tr("退还"), role: .destructive) { doRefund() }
            Button(Tr("取消"), role: .cancel) { }
        } message: {
            Text(Tr("退还后这笔钱会原路退回到对方零钱，你和对方的转账卡片都会变成「已退还」。"))
        }
        .confirmationDialog(Tr("账单详情"), isPresented: $showMore, titleVisibility: .visible) {
            Button(Tr("刷新状态")) {
                Task {
                    if let list = try? await API.shared.messages(chatId: chat.id, limit: 30),
                       let msg = list.messages.last(where: { $0.kindName == "transfer" }),
                       let updated = TransferInfo(json: msg.body) {
                        live = updated
                    }
                    app.show(Tr("已经是最新状态"))
                }
            }
            Button(Tr("对订单有疑惑")) {
                showKefu = true
            }
            Button(Tr("定位到聊天位置")) { dismiss() }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private func detailRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            Text(k)
                .font(pfExact(14.5))
                .foregroundColor(faint)
            Spacer(minLength: 0)
            Text(v)
                .font(pfExact(14.5))
                .foregroundColor(C.label)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 32)
        .frame(height: 49)
    }

    private func doRefund() {
        Task {
            if let err = await API.shared.refundTransfer(t.id) {
                app.show(err)
                return
            }

            if let list = try? await API.shared.messages(chatId: chat.id, limit: 30),
               let msg = list.messages.last(where: { $0.kindName == "transfer" }),
               let updated = TransferInfo(json: msg.body) {
                live = updated
            }
            app.me = try? await API.shared.me()
            app.show(Tr("已退还"))
        }
    }

    private func billAction() {
        if mine {

            guard !busy else { return }
            busy = true
            Task {
                let err = await API.shared.remindTransfer(t.id)
                busy = false
                app.show(err ?? Tr("已提醒对方收款"))
            }
            return
        }
        guard !busy else { return }
        busy = true
        Task {

            let err = await API.shared.claimTransfer(t.id)
            await refreshTransfer()
            app.me = try? await API.shared.me()
            busy = false
            app.show(err ?? Tr("已收款"))
        }
    }

    private func refreshTransfer() async {
        guard let list = try? await API.shared.messages(chatId: chat.id, limit: 50) else { return }
        let hit = list.messages
            .filter { $0.kindName == "transfer" }
            .compactMap { TransferInfo(json: $0.body) }
            .first { $0.id == info.id }
        if let hit { live = hit }
    }
}

struct TransferDetailIcon: View {
    var size: CGFloat = 50

    var body: some View {
        let s = size / 50
        ZStack {
            Circle().fill(Color(hex: 0x10AEFF))
            Path { p in
                p.move(to: CGPoint(x: 25.35 * s, y: 12.7 * s))
                p.addLine(to: CGPoint(x: 25.35 * s, y: 23.6 * s))
                p.addLine(to: CGPoint(x: 31.7 * s, y: 33.4 * s))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 5.4 * s,
                                                    lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

struct BillReceiptView: View {
    let chat: Chat
    let info: TransferInfo

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showKefu = false

    private var mine: Bool { info.fromId == (app.me?.id ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("账单详情"), back: { dismiss() })

            ScrollView {
                VStack(spacing: 0) {
                    Text(info.statusText(mine: mine))
                        .font(pfExact(17))
                        .foregroundColor(C.label)
                        .padding(.top, 26)

                    MoneyLabel(text: "¥" + money(info.amount), size: 40, curSize: 27,
                               topAlign: true, color: C.label, exact: true)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        row(Tr("转账说明"), info.note.isEmpty ? "—" : info.note)
                        HairLine(inset: 16)
                        row(mine ? Tr("收款方") : Tr("付款方"), chat.name)
                        HairLine(inset: 16)
                        row(Tr("转账时间"), TimeFmt.bill(info.createdAt))
                        HairLine(inset: 16)
                        row(Tr("支付方式"), info.methodName)
                        HairLine(inset: 16)
                        row(Tr("交易单号"), info.billNo)

                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIPasteboard.general.string = info.billNo
                                app.show(Tr("单号已复制，粘给客服就行"))
                            }
                        HairLine(inset: 16)
                        row(Tr("商户单号"), "1000" + String(info.billNo.suffix(16)))
                        if info.status == "received" {
                            HairLine(inset: 16)
                            row(Tr("收款时间"), TimeFmt.bill(info.receivedAt))
                        }
                        if info.status == "refunded" {
                            HairLine(inset: 16)
                            row(Tr("退回时间"), TimeFmt.bill(info.refundedAt))
                        }
                    }
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 24)

                    Button {
                        showKefu = true
                    } label: {
                        Text(Tr("对订单有疑问"))
                            .font(pf(15.5))
                            .foregroundColor(C.link)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background { CardGlassBox(radius: 10) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }

        .sheet(isPresented: $showKefu) {
            KefuPage().environmentObject(app)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 14) {
            Text(k).font(pfExact(14.5)).foregroundColor(C.subLabel)
            Spacer(minLength: 8)
            Text(v).font(pfExact(14.5)).foregroundColor(C.label)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }
}
