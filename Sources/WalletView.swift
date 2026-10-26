import SwiftUI

struct WalletView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var realtime = Realtime.shared

    @State private var cfg: WalletConfig?
    @State private var showBills = false
    @State private var showCoin = false
    @State private var showCards = false
    @State private var showBiz = false
    @State private var showScore = false

    @State private var showSupport = false

    @State private var showIdentity = false
    @State private var showPaySettings = false

    @State private var showPayScore = false

    @State private var creditText = ""

    @State private var revealed: Set<String> = []

    @State private var needGesture = false
    @State private var pendingAction = ""
    @State private var pendingLabel = ""

    @State private var needReal = false

    private var st: WalletStyle { cfg?.style ?? WalletStyle() }

    private var groups: [WalletGroup] {
        let list = cfg?.groups ?? []
        return list.filter { ($0.enabled != false) && !(($0.items ?? []).filter { $0.enabled != false }.isEmpty) }
    }

    private var footLinks: [WalletFoot] {
        (cfg?.footer ?? []).filter { $0.enabled != false }
    }

    var body: some View {
        if needReal {
            NeedRealNameView { dismiss() }
        } else {
        VStack(spacing: 0) {
            NavBar(title: cfg?.title ?? "钱包", back: { dismiss() }) {

                if UIConfig.num("billsShow", 1) > 0 {
                    Button {
                        run((cfg?.right?.action ?? "bills"), (cfg?.right?.label ?? "账单"))
                    } label: {
                            Text(Tr(cfg?.right?.label ?? "账单"))
                            .font(pf(17))
                            .foregroundColor(C.label)
                            .frame(height: L.navH)
                            .padding(.trailing, 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 6)

                    if cfg?.isLocked ?? false {
                        Button {
                            RealNameGate.shared.prompt()
                        } label: {
                            HStack(spacing: 6) {
                                Text("⚠️").font(pf(14))
                                Text(Tr("按国家规定，完成实名认证后才能查看和使用钱包金额"))
                                    .font(pf(13))
                                    .foregroundColor(Color(hex: 0xB06A12))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(Tr("去认证")).font(pf(13, .medium)).foregroundColor(C.green)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.dyn(0xFFF7E6, 0x3A2E17)))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(groups) { g in
                        card(g).padding(.top, g.id == groups.first?.id ? 0 : st.gap)
                    }
                    Color.clear.frame(height: 24)
                }
            }
            .background(C.pageBg)

            footer
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .navigationDestination(isPresented: $showBills) { BillsView() }
        .navigationDestination(isPresented: $showCoin) { BalancePageView() }
        .navigationDestination(isPresented: $showCards) { BankCardsView() }
        .navigationDestination(isPresented: $showBiz) { BizAccountView() }
        .navigationDestination(isPresented: $showScore) { SecurityScoreView() }
        .sheet(isPresented: $showSupport) { SupportView().environmentObject(app) }
        .sheet(isPresented: $showIdentity) { IdentityView().environmentObject(app) }
        .sheet(isPresented: $showPaySettings) { PaySettingsView().environmentObject(app) }
        .sheet(isPresented: $showPayScore) { PayScoreView().environmentObject(app) }
        .sheet(isPresented: $needGesture) {
            GestureLockView { openAfterLock(pendingAction, pendingLabel) }
        }
        .task { await load() }
        .onChange(of: realtime.event) { ev in
            if ev.type == "transfer" || ev.type == "balance" || ev.type == "ui" { Task { await load() } }
        }
        }
    }

    private func card(_ g: WalletGroup) -> some View {
        let rows = (g.items ?? []).filter { $0.enabled != false }
        let s = st
        return VStack(spacing: 0) {
            if !C.xingjiOn {
                Rectangle().fill(C.hairline).frame(height: 0.5)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, it in
                row(it)
                if idx < rows.count - 1 {
                    HairLine(inset: s.divider)
                }
            }
        }
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: C.xingjiOn ? 16 : 0,
                                    style: .continuous))
        .overlay {
            if C.xingjiOn {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(C.hairline, lineWidth: 0.5)
            }
        }
        .padding(.horizontal, C.xingjiOn ? 12 : 0)
    }

    private func row(_ it: WalletItem) -> some View {
        let s = st
        let rawValue = (it.action == "score" && !creditText.isEmpty) ? creditText : (it.value ?? "")
        let masked = !rawValue.isEmpty && s.mask && (it.mask ?? true)
        let value = (masked && !revealed.contains(it.id)) ? WalletView.maskMoney(rawValue) : rawValue
        let note = it.note ?? ""
        return Button {
            run(it.action ?? "soon", it.label)
        } label: {
            HStack(spacing: 0) {
                SVGIcon(markup: WalletIcon.markup(it.icon, it.svg), size: s.icon,
                        color: Color(hexString: it.color ?? "#1180E0", fallback: 0x1180E0))
                    .frame(width: s.icon, height: s.icon)
                    .padding(.leading, s.iconX)

            Text(Tr(it.label))
                    .font(pf(s.labelFont))
                    .foregroundColor(s.labelColorV)
                    .padding(.leading, max(0, s.textX - s.iconX - s.icon))

                if !note.isEmpty {
                    Text(note)
                        .font(pf(s.noteFont))
                        .foregroundColor(s.noteColorV)
                        .padding(.leading, 11.7)
                }

                Spacer(minLength: 0)

                if !value.isEmpty {
                    MoneyLabel(text: value, size: s.valueFont, curSize: s.curFontSize, color: s.valueColorV)
                        .padding(.trailing, 11)
                        .onTapGesture {
                            guard masked, s.canReveal else { return }
                            if revealed.contains(it.id) { revealed.remove(it.id) } else { revealed.insert(it.id) }
                        }
                }

                Chevron(size: 9, line: 1.6)
                    .padding(.trailing, s.rightPad)
            }
            .frame(height: s.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 19) {
            ForEach(footLinks) { f in
                Button {
                    run(f.action ?? "soon", f.label)
                } label: {
            Text(Tr(f.label))
                        .font(pf(st.footFont))
                        .foregroundColor(st.footerColorV)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(C.pageBg)
    }

    private func run(_ action: String, _ label: String) {

        if GestureStore.enabled, action == "balance" || label == "经营账户" {
            pendingAction = label == "经营账户" ? "biz" : action
            pendingLabel = label
            needGesture = true
            return
        }
        openAfterLock(label == "经营账户" ? "biz" : action, label)
    }

    private func openAfterLock(_ action: String, _ label: String) {
        switch action {
        case "balance":
            showCoin = true
        case "biz":
            showBiz = true
        case "score":
            showPayScore = true
        case "bills":
            showBills = true
        case "card":
            showCards = true
        case "settings":
            showPaySettings = true
        case "identity":
            showIdentity = true
        case "service":
            showSupport = true
        default:

            if label.contains("经营账户") { showBiz = true }
            else if label.contains("客服") { showSupport = true }
            else if label.contains("零钱") { showCoin = true }
            else if label.contains("账单") { showBills = true }
            else if label.contains("银行卡") { showCards = true }
            else { app.show("「\(label)」还没接后端，先把页面做出来") }
        }
    }

    private func load() async {
        revealed = []
        do {
            cfg = try await API.shared.walletConfig()
        } catch let e as APIError {

            if case .needRealName = e {
                needReal = true
                return
            }
            if cfg == nil { cfg = WalletFallback.config(balance: app.me?.balance ?? 0) }
        } catch {
            if cfg == nil { cfg = WalletFallback.config(balance: app.me?.balance ?? 0) }
        }

        let wantScore = (cfg?.groups ?? []).contains { g in
            (g.items ?? []).contains { $0.action == "score" }
        }
        if wantScore, let s = try? await API.shared.securityScore() {
            creditText = "\(s.score)"
        }
    }

    static func maskMoney(_ text: String) -> String {
        if text.contains("¥") { return "¥****" }
        return String(text.map { $0.isNumber ? "*" : $0 })
    }
}
