import SwiftUI

struct ShopView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [API.ShopItem] = []
    @State private var orders: [API.ShopOrder] = []
    @State private var balance: Double = 0
    @State private var loading = true
    @State private var errText = ""

    @State private var open: API.ShopItem? = nil
    @State private var showOrders = false

    @State private var showMall = false

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("小店"), back: { dismiss() }) {
                Button { showOrders = true } label: {
                    Text(Tr("我的订单"))
                        .font(pf(14.5))
                        .foregroundColor(C.green)
                        .padding(.horizontal, AppDesign.Spacing.sm).frame(height: AppDesign.Control.smallButtonHeight)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    Button { showMall = true } label: {
                        HStack(spacing: AppDesign.Spacing.sm) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous)
                                    .fill(LinearGradient(colors: [Color(hex: 0xFF5A3C), Color(hex: 0xE02A0F)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 19, weight: .semibold)).foregroundColor(.white)
                            }
                            .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(Tr("拼多多商城")).font(AppDesign.Type.buttonMedium).foregroundColor(C.label)
                                    Text(Tr("H5")).font(pf(10.5)).foregroundColor(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                                        .background(RoundedRectangle(cornerRadius: AppDesign.Radius.micro).fill(Color(hex: 0xE02A0F)))
                                }
                                Text(Tr("拼团 · 秒杀 · 种草 · 购物车（和商城后台同一套数据）"))
                                    .font(pf(12)).foregroundColor(C.subLabel).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Chevron(size: 9, line: 1.6)
                        }
                        .padding(.horizontal, 14).frame(height: 66)
                        .background(C.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.compact, style: .continuous))
                        .padding(.horizontal, AppDesign.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if loading && items.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if items.isEmpty {
                        Text(Tr("店里还没上架商品")).font(pf(14)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        if !errText.isEmpty {
                            Text(errText).font(pf(12)).foregroundColor(C.subLabel)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26).padding(.top, 6)
                        }
                    } else {
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(items) { it in
                                Button { open = it } label: { cell(it) }
                                    .buttonStyle(MenuPressStyle())
                            }
                        }
                        .padding(.horizontal, AppDesign.Spacing.sm)

                        Text(Tr("下单后可以在右上角「我的订单」里看进度。"))
                            .font(pf(12)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.top, AppDesign.Spacing.xxs)
                    }
                    Spacer().frame(height: AppDesign.Control.sectionHeaderHeight)
                }
                .padding(.top, 10)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task { await load() }
        .sheet(item: $open) { it in
            ShopItemSheet(item: it, balance: balance) { newBalance in
                balance = newBalance
                Task { await load() }
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showOrders) {
            ShopOrdersSheet(orders: orders, balance: balance)
                .environmentObject(app)
        }

        .fullScreenCover(isPresented: $showMall) {

            MallAuthGate { MallNativeView(app: app) }
        }
    }

    private var balanceCard: some View {
        GroupCard {
            HStack(spacing: AppDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Tr("零钱余额")).font(pf(14)).foregroundColor(C.subLabel)
                    Text("¥" + moneyFmt(balance))
                        .font(pfMoney(22, .medium)).foregroundColor(C.label)
                }
                Spacer(minLength: 0)
                Image(systemName: "bag.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(C.green.opacity(0.85))
            }
            .padding(.horizontal, AppDesign.Spacing.md).padding(.vertical, 14)
        }
        .padding(.top, 2)
    }

    private func cell(_ it: API.ShopItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous)
                    .fill(C.fieldBg)
                if let img = it.img, !img.isEmpty {
                    RemoteImage(path: img)
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous))
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 30))
                        .foregroundColor(C.subLabel)
                }
            }
            .frame(height: 104)

            Text(it.name).font(pf(14.5)).foregroundColor(C.label)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppDesign.Spacing.xs)

            HStack(spacing: 6) {
                Text("¥" + moneyFmt(it.price))
                    .font(pfMoney(15, .medium)).foregroundColor(C.red)
                Text(it.kindName)
                    .font(pf(10.5))
                    .foregroundColor(C.subLabel)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: AppDesign.Radius.micro, style: .continuous).fill(C.fieldBg))
                Spacer(minLength: 0)
                Text(Tr("库存 ") + String(it.stock ?? 0))
                    .font(pf(11)).foregroundColor(C.subLabel)
            }
            .padding(.top, AppDesign.Spacing.xxs)
            .padding(.bottom, 10)
        }
        .padding(AppDesign.Spacing.xs)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.compact, style: .continuous))
        .opacity((it.stock ?? 1) <= 0 ? 0.55 : 1)
    }

    private func load() async {
        do {
            let d = try await API.shared.shopData()
            items = d.items ?? []
            orders = d.orders ?? []
            balance = d.balance ?? (app.me?.balance ?? 0)
            errText = ""
            DiagLog.shared.note("小店：拉到 \(items.count) 件商品 / \(orders.count) 个订单")
        } catch {
            errText = "暂时没准备好，稍后再试"
            DiagLog.shared.note("小店：暂时没准备好")
        }
        loading = false
    }
}

struct ShopItemSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let item: API.ShopItem
    let balance: Double

    let onDone: (Double) -> Void

    @State private var count = 1
    @State private var address = ""
    @State private var showPay = false
    @State private var busy = false

    private var total: Double { item.price * Double(count) }
    private var soldOut: Bool { (item.stock ?? 1) <= 0 }

    private var specText: String {
        let price = Tr("价格") + " ¥" + moneyFmt(item.price)
        let stock = Tr("库存 ") + String(item.stock ?? 0)
        return price + " · " + item.kindName + " · " + stock
    }

    private var totalText: String {
        Tr("合计 ") + "¥" + moneyFmt(total) + "　" + Tr("零钱 ") + "¥" + moneyFmt(balance)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: item.name, back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppDesign.Spacing.sm) {
                    if let img = item.img, !img.isEmpty {
                        RemoteImage(path: img)
                            .scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.compact, style: .continuous))
                            .padding(.horizontal, AppDesign.Spacing.sm)
                    }

                    GroupCard(horizontalInset: 0) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(pf(17, .medium)).foregroundColor(C.label)
                                Text(specText)
                                    .font(pf(13)).foregroundColor(C.subLabel)
                                if let d = item.desc, !d.isEmpty {
                                    Text(d).font(pf(13)).foregroundColor(C.subLabel)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppDesign.Spacing.md).padding(.vertical, 14)

                        if item.isPhysical {
                            HairLine(inset: 16)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Tr("收货地址")).font(pf(13)).foregroundColor(C.subLabel)
                                TextField(Tr("省市区 + 详细地址 + 手机号"), text: $address, axis: .vertical)
                                    .font(pf(14.5))
                                    .lineLimit(2...4)
                            }
                            .padding(.horizontal, AppDesign.Spacing.md).padding(.vertical, AppDesign.Spacing.sm)
                        }

                        HairLine(inset: 16)
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Text(Tr("数量")).font(AppDesign.Type.bodyLarge).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Button { if count > 1 { count -= 1 } } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(C.label)
                                    .frame(width: 32, height: 30)
                                    .background(RoundedRectangle(cornerRadius: AppDesign.Radius.mini, style: .continuous).fill(C.fieldBg))
                            }
                            .buttonStyle(.plain)
                            Text("\(count)").font(pf(16)).foregroundColor(C.label).frame(minWidth: 26)
                            Button { if count < min(99, item.stock ?? 99) { count += 1 } } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(C.label)
                                    .frame(width: 32, height: 30)
                                    .background(RoundedRectangle(cornerRadius: AppDesign.Radius.mini, style: .continuous).fill(C.fieldBg))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.dialogRowHeight)
                    }

                    Text(totalText)
                        .font(pf(13)).foregroundColor(C.subLabel)

                    Button {
                        buy()
                    } label: {
                        Text(soldOut ? Tr("已售罄") : Tr("立即购买"))
                            .font(pf(17, .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: AppDesign.Control.mediumControlHeight)
                            .background(RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous)
                                .fill(soldOut ? Color.gray : C.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || soldOut)
                    .padding(.horizontal, AppDesign.Spacing.md)

                    Spacer().frame(height: AppDesign.Control.sectionHeaderHeight)
                }
                .padding(.top, AppDesign.Spacing.sm)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)

        .sheet(isPresented: $showPay) {
            ShopPaySheet(amount: total, item: item.name) { pwd in
                await submit(payPassword: pwd)
            }
            .environmentObject(app)
        }

        .swipeBack { dismiss() }
    }

    private func buy() {
        if item.isPhysical && address.trimmingCharacters(in: .whitespaces).isEmpty {
            app.show(Tr("实物商品要填收货地址"))
            return
        }
        if total > balance {
            app.show(Tr("零钱不够（还差 ") + "¥" + moneyFmt(total - balance) + "）")
            return
        }
        Task {

            let has = await API.shared.hasPayPassword()
            if has { showPay = true } else { _ = await submit(payPassword: "") }
        }
    }

    private func submit(payPassword: String) async -> String? {
        if busy { return nil }
        busy = true
        defer { busy = false }
        do {
            let r = try await API.shared.shopOrder(itemId: item.id, count: count,
                                                   address: address, payPassword: payPassword)
            let nb = r.balance ?? balance
            app.show(Tr("下单成功：") + (r.order?.name ?? item.name))
            DiagLog.shared.note("小店下单成功 \(item.name) ×\(count)，余额 ¥\(moneyFmt(nb))")
            onDone(nb)
            Task { app.me = try? await API.shared.me() }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
            return nil
        } catch {
            let msg = (error as? APIError)?.errorDescription
                ?? (error as? LocalizedError)?.errorDescription ?? "下单失败"
            DiagLog.shared.note("小店下单失败：\(msg)")
            return msg
        }
    }
}

struct ShopPaySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let amount: Double
    let item: String

    let pay: (String) async -> String?

    @State private var password = ""
    @State private var busy = false
    @State private var tip = ""
    @State private var shake: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text(item).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            Text("¥\(moneyFmt(amount))")
                .font(pfMoney(32, .medium)).foregroundColor(C.label)
                .padding(.top, 6)

            PayDotField(count: password.count, shake: shake, busy: busy)
                .padding(.top, AppDesign.Spacing.md)
            if !tip.isEmpty {
                Text(tip).font(pf(13)).foregroundColor(C.red)
                    .multilineTextAlignment(.center).padding(.horizontal, AppDesign.Spacing.lg).padding(.top, 10)
            }
            PayKeypadView(busy: busy) { tap($0) }
                .padding(.top, AppDesign.Spacing.md)
            Spacer(minLength: 0)
        }
        .overlay { if busy { PayBusyOverlay() } }
        .background(C.pageBg.ignoresSafeArea())
        .presentationDetents([.height(452)])
    }

    private func tap(_ key: String) {
        if busy { return }
        if key == "⌫" {
            if !password.isEmpty { password.removeLast() }
            tip = ""
            return
        }
        guard !key.isEmpty, password.count < 6 else { return }
        password.append(key)
        tip = ""
        if password.count == 6 { run() }
    }

    private func run() {
        busy = true
        Task { @MainActor in
            let err = await pay(password)
            busy = false
            if let err = err {
                password = ""
                tip = err
                payShake($shake)
            } else {
                dismiss()
            }
        }
    }
}

struct ShopOrdersSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let orders: [API.ShopOrder]
    let balance: Double
    @State private var filter = 0

    private let names = ["全部", "待发货", "已发货", "已完成"]

    private func stage(_ s: String?) -> Int {
        let t = s ?? ""
        if t.contains("完成") || t.contains("收货") { return 3 }
        if t.contains("发货") || t.contains("途中") { return 2 }
        if t.contains("取消") { return 3 }
        return 1
    }

    private var shown: [API.ShopOrder] {
        filter == 0 ? orders : orders.filter { stage($0.status) == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的订单"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    HStack(spacing: AppDesign.Spacing.xs) {
                        ForEach(0..<names.count, id: \.self) { i in
                            Button { filter = i } label: {
                                Text(Tr(names[i]))
                                    .font(AppDesign.Type.body)
                                    .foregroundColor(filter == i ? .white : C.label)
                                    .padding(.horizontal, AppDesign.Spacing.sm).frame(height: AppDesign.Control.sectionHeaderHeight)
                                    .background(RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous)
                                        .fill(filter == i ? C.green : C.cardBg))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, AppDesign.Spacing.sm)

                    if shown.isEmpty {
                        Text(Tr("还没有订单")).font(pf(14)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        GroupCard(horizontalInset: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, o in
                                if i > 0 { HairLine(inset: 16) }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: AppDesign.Spacing.xs) {
                                        Text(o.name ?? Tr("订单")).font(AppDesign.Type.bodyLarge).foregroundColor(C.label)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("¥" + moneyFmt(o.price ?? 0))
                                            .font(pfMoney(15)).foregroundColor(C.label)
                                    }
                                    HStack(spacing: AppDesign.Spacing.xs) {
                                        Text(o.status ?? Tr("已下单")).font(AppDesign.Type.caption).foregroundColor(C.subLabel)
                                        Spacer(minLength: 0)
                                        Text(TimeFmt.bill(o.at ?? "")).font(AppDesign.Type.caption).foregroundColor(C.subLabel)
                                    }
                                    if let a = o.address, !a.isEmpty {
                                        Text(Tr("地址：") + a).font(pf(12)).foregroundColor(C.subLabel)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, AppDesign.Spacing.md).padding(.vertical, AppDesign.Spacing.sm)
                            }
                        }
                        Text(Tr("零钱余额 ") + "¥" + moneyFmt(balance))
                            .font(AppDesign.Type.caption).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22).padding(.top, 2)
                    }
                        Spacer().frame(height: AppDesign.Control.sectionHeaderHeight)
                }
                .padding(.top, 10)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)

        .swipeBack { dismiss() }
    }
}
