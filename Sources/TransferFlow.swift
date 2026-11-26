import SwiftUI
import UIKit

struct TransferView: View {
    let chat: Chat

    var onPaid: () -> Void = {}

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var digits = ""
    @State private var note = ""
    @State private var noteEditing = false
    @State private var method = "balance"
    @State private var showPay = false
    @State private var showMethod = false
    @State private var password = ""
    @State private var hasPwd = false
    @State private var busy = false
    @State private var step = 0
    @State private var doneAmount: Double = 0
    @State private var receipt: API.TransferReceipt?

    @State private var showBills = false
    @State private var showPayHelp = false
    @State private var payHint: String?
    @State private var badPwd = false

    @State private var needFaceForRisk = false
    @State private var caretOn = true

    @State private var faceOK = false
    @State private var usePassword = false
    @State private var checkoutDetailsExpanded = false

    @State private var peerRealName = ""

    private var amount: Double { Double(digits) ?? 0 }
    private var peerAvatar: String { chat.avatar ?? "" }

    private var peerTitle: String {
        let masked = peerRealName.trimmingCharacters(in: .whitespaces)
        if masked.isEmpty { return chat.name }
        return chat.name + "（" + masked + "）"
    }
    private var balance: Double { app.me?.balance ?? 0 }
    private var methodName: String {
        method == "xypay" ? XYPay.name : Tr("星言零钱")
    }
    private var methodSub: String {
        (method == "xypay" ? XYPay.cardLine + " · " : "") + Tr("可用") + " ¥" + money(balance)
    }

    var body: some View {
        ZStack {

            PayVisual.canvas.ignoresSafeArea()

            if step == 1 {
                resultPage
            } else {
                mainPage
            }

            if busy {
                PayBusyOverlay(text: "正在转账").zIndex(30)
            }
        }

        .alert(Tr("转账说明"), isPresented: $noteEditing) {
            TextField("", text: $note)
            Button(Tr("好")) { }
            Button(Tr("取消"), role: .cancel) { note = "" }
        } message: {
            Text(Tr("收付款双方可见，最多 60 个字"))
        }

        .onChange(of: note) { v in
            if v.count > 60 { note = String(v.prefix(60)) }
        }

        .sheet(isPresented: $showBills) {
            NavigationStack { BillsView().environmentObject(app) }
        }

        .sheet(isPresented: $showPay) {
            paySheet
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(busy)
        }

        .sheet(isPresented: $needFaceForRisk) {
            FaceVerifyFlowView { ok in
                needFaceForRisk = false
                if ok {
                    submit(face: true)
                } else {
                    payHint = "没有人脸验证通过，这一笔没有转出去"
                }
            }
            .environmentObject(app)
        }
        .alert(Tr("转账帮助"), isPresented: $showPayHelp) {
            Button(Tr("好"), role: .cancel) { }
        } message: {
            Text(Tr("转账后对方需要确认收款才会到账；24 小时未确认会自动退回。可以在「我 → 账单」里查这笔记录。"))
        }
        .task {
            hasPwd = await API.shared.hasPayPassword()
            faceOK = Biometrics.paymentReady

            if (chat.type ?? "direct") != "group" {
                let meId = app.me?.id ?? ""
                if let peerId = (chat.memberIds ?? []).first(where: { $0 != meId }),
                   let peer = try? await API.shared.user(id: peerId) {
                    peerRealName = peer.realName ?? ""
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 525_000_000)
                caretOn.toggle()
            }
        }
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            head
            bodyArea
            Spacer(minLength: 0)

            sendBar

            amountPad
        }
    }

    private var amountPad: some View {
        VStack(spacing: 0) {
            PayKeypadView(busy: false, keyHeight: L.payPadH, secure: false, dot: true) { k in
                tapAmount(k)
            }
            Rectangle()
                .fill(C.cardBg)
                .frame(height: max(0, L.safeBottom))
        }
    }

    private func tapAmount(_ k: String) {
        if k == "⌫" {
            if !digits.isEmpty { digits.removeLast() }
            return
        }
        if k == "." {
            if digits.isEmpty { digits = "0."; return }
            if !digits.contains(".") { digits += "." }
            return
        }
        if digits == "0" { digits = k; return }
        let next = digits + k
        let clean = sanitizeAmount(next)

        if clean.count > digits.count { digits = clean }
    }

    private var sendBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openPay()
        } label: {
            HStack(spacing: 8) {
                Text(Tr("转账"))
                    .font(pf(17, .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(amount > 0 ? C.cardBg : PayVisual.secondaryInk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                amount > 0 ? C.label : PayVisual.secondaryInk.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(scheme == .dark ? 0.17 : 0.06),
                            lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(amount > 0 ? 0.16 : 0),
                    radius: 12, y: 6)
        }
        .buttonStyle(AppleCheckoutButtonStyle())
        .disabled(amount <= 0)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, max(14, L.safeBottom))
    }

    private var head: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(Tr("转账"))
                    .font(pf(16.5, .semibold))
                    .foregroundColor(C.label)
                HStack {
                    Button { dismiss() } label: {
                        SVGIcon(markup: I.backCover, size: 20, color: C.label)
                            .frame(width: 44, height: L.navH)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .frame(height: L.navH)

            HStack(spacing: 13) {
                    Avatar(path: peerAvatar,
                           size: 46,
                           radius: 23)
                        .overlay {
                            Circle().stroke(Color.white.opacity(scheme == .dark ? 0.20 : 0.72),
                                            lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(Tr("转账给"))
                            .font(pf(11, .medium))
                            .foregroundColor(PayVisual.secondaryInk)
                        Text(peerTitle)
                            .font(pf(17, .semibold))
                            .foregroundColor(C.label)
                            .lineLimit(1)
                        Text(Lang.isEnglish ? "Account: \(chat.name)" : "账号：\(chat.name)")
                            .font(pf(12.5))
                            .foregroundColor(C.subLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: peerRealName.isEmpty ? "person.crop.circle" : "checkmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(peerRealName.isEmpty ? PayVisual.secondaryInk : PayVisual.success)
                        .frame(width: 34, height: 34)
                        .background(C.fieldBg, in: Circle())
                }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(PayVisual.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(C.hairline.opacity(0.72), lineWidth: 0.6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
        .background(PayVisual.canvas)
    }

    private var bodyArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr("转账金额"))
                .font(pf(14.5))
                .foregroundColor(C.label)
                .padding(.horizontal, L.v(16, 5, 20))
                .padding(.top, L.v(10, 4, 16))
                .padding(.bottom, L.v(4, 1.4, 6))

            HStack(alignment: .center, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("¥")
                        .font(pfMoney(L.tfCnySize))
                        .foregroundColor(C.label)
                    digitCells
                }
                if caretOn {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(C.green)
                        .frame(width: L.tfCaretW, height: L.tfCaretH)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, L.v(4, 1.4, 7))
            .padding(.horizontal, L.v(16, 5, 20))
            .padding(.bottom, L.v(10, 3.4, 15))
            .overlay(alignment: .bottom) {
                Rectangle().fill(C.hairline).frame(height: 0.5)
            }
            .contentShape(Rectangle())

            HStack(alignment: .top, spacing: 5) {
                Text("¥")
                    .font(pfMoney(L.tfCnySize))
                    .foregroundColor(.clear)
                unitCells
                Spacer(minLength: 0)
            }
            .padding(.top, L.v(2, 1, 4))
            .padding(.horizontal, L.v(16, 5, 20))

            HairLine(inset: 16)

            Button {
                noteEditing = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PayVisual.tint)
                    Text(note.isEmpty ? Tr("添加转账说明") : note)
                        .font(pf(15.5))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PayVisual.secondaryInk)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }

        .background {
            ZStack {
                NativePremiumGlassMaterial(dark: scheme == .dark)
                PayVisual.card.opacity(scheme == .dark ? 0.84 : 0.90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.10 : 0.46),
                        lineWidth: 0.65)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.06),
                radius: 18, y: 8)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var digitCells: some View {
        let chars = Array(digits)
        return HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { i in
                Text(String(chars[i]))
                    .font(pf(L.tfDigitSize, .semibold))
                    .foregroundColor(C.label)
                    .frame(width: L.tfCellW)
            }
            if digits.isEmpty { Color.clear.frame(width: L.tfCellW, height: 1) }
        }
    }

    private var unitCells: some View {
        let chars = Array(digits)
        return HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { i in
                Text(unit(at: i, in: chars))
                    .font(pf(L.tfUnitSize))
                    .foregroundColor(Color(hex: 0xB8B8B8))
                    .lineLimit(1)
                    .frame(width: L.tfCellW)
            }
            if chars.isEmpty { Color.clear.frame(width: L.tfCellW, height: 1) }
        }
    }

    private func unit(at i: Int, in chars: [Character]) -> String {
        guard i < chars.count else { return "" }
        if chars[i] == "." { return "" }
        if chars[0..<i].contains(where: { $0 != "." }) { return "" }
        let intLen = digits.split(separator: ".").first?.count ?? 0
        switch intLen {
        case 5: return "万"
        case 6: return "十万"
        default: return intLen >= 7 ? "百万" : "千"
        }
    }

    private func sanitizeAmount(_ raw: String) -> String {
        var out = ""
        var seenDot = false
        var decimals = 0
        for ch in raw {
            if ch >= "0" && ch <= "9" {
                if seenDot {
                    if decimals >= 2 { continue }
                    decimals += 1
                }
                out.append(ch)
            } else if ch == "." || ch == "," {
                if seenDot { continue }
                seenDot = true
                out.append(".")
            }
        }
        return out.count > 10 ? String(out.prefix(10)) : out
    }

    private func openPay() {
        guard amount > 0 else { app.show(Tr("请先输入转账金额")); return }
        password = ""
        usePassword = !faceOK
        payHint = nil
        badPwd = false
        withAnimation(.easeOut(duration: 0.26)) { showPay = true }
        Task {
            hasPwd = await API.shared.hasPayPassword()
            app.me = try? await API.shared.me()
        }
    }

    private var paySheet: some View {
        VStack(spacing: 0) {
            paySheetHeader

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    checkoutHero
                    checkoutSummaryCard

                    if !faceOK || usePassword {
                        passwordPanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }

            if faceOK && !usePassword {
                VStack(spacing: 12) {
                    faceConfirmPanel
                    paymentTrustLine
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, max(18, L.safeBottom))
                .background(C.cardBg)
                .overlay(alignment: .top) {
                    HairLine(inset: 0)
                }
            } else {
                VStack(spacing: 8) {
                    PayKeypadView(busy: busy, keyHeight: L.payPadH) { key in
                        tapPay(key)
                    }
                    paymentTrustLine
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(12, L.safeBottom))
                }
                .background(PayVisual.canvas)
                .overlay(alignment: .top) {
                    HairLine(inset: 0)
                }
            }
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .sheet(isPresented: $showMethod) {
            methodSheet
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var paySheetHeader: some View {
        ZStack {
            Text(Tr("确认转账"))
                .font(pf(16.5, .semibold))
                .foregroundStyle(C.label)

            HStack {
                Button { closePay() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(C.label)
                        .frame(width: 34, height: 34)
                        .background(C.fieldBg, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Tr("关闭"))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(C.cardBg)
        .overlay(alignment: .bottom) {
            HairLine(inset: 0)
        }
    }

    private var checkoutHero: some View {
        VStack(spacing: 10) {
            Avatar(path: peerAvatar, size: 60, radius: 30)
                .overlay {
                    Circle().stroke(C.hairline.opacity(0.72), lineWidth: 0.8)
                }

            Text(Lang.isEnglish ? "Pay \(peerTitle)" : "付款给 \(peerTitle)")
                .font(pf(14, .medium))
                .foregroundStyle(PayVisual.secondaryInk)
                .lineLimit(1)

            StarPayAmount(value: amount, role: .hero, color: C.label)
                .accessibilityLabel(Tr("转账金额") + " " + money(amount))

            Text(methodName)
                .font(pf(12.5, .medium))
                .foregroundStyle(PayVisual.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var checkoutSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaySectionLabel(text: Tr("付款方式"))

            checkoutSurface {
                VStack(spacing: 0) {
                    Button {
                        showMethod = true
                    } label: {
                        HStack(spacing: 13) {
                            paymentMethodMark

                            VStack(alignment: .leading, spacing: 3) {
                                Text(methodName)
                                    .font(pf(15.5, .semibold))
                                    .foregroundStyle(C.label)
                                Text(methodSub)
                                    .font(pf(12))
                                    .foregroundStyle(PayVisual.secondaryInk)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(Tr("更改"))
                                .font(pf(13, .medium))
                                .foregroundStyle(PayVisual.tint)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PayVisual.tint.opacity(0.82))
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HairLine(inset: 16)

                    Button {
                        withAnimation(.spring(response: 0.28,
                                              dampingFraction: 0.88)) {
                            checkoutDetailsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(C.label)
                                .frame(width: 24)
                            Text(checkoutDetailsExpanded
                                 ? Tr("收起详情")
                                 : Tr("付款详情"))
                                .font(pf(14.5, .medium))
                                .foregroundStyle(C.label)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PayVisual.secondaryInk)
                                .rotationEffect(.degrees(
                                    checkoutDetailsExpanded ? 180 : 0
                                ))
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if checkoutDetailsExpanded {
                        HairLine(inset: 16)
                        checkoutDetailRow(Tr("收款方"), peerTitle)
                        if !note.isEmpty {
                            HairLine(inset: 16)
                            checkoutDetailRow(Tr("转账说明"), note)
                        }
                        HairLine(inset: 16)
                        checkoutDetailRow(Tr("安全"),
                                          Tr("支付过程由设备安全验证保护"))
                    }
                }
            }
        }
    }

    private var paymentMethodMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
            Image(systemName: method == "card"
                  ? "creditcard.fill" : "wallet.bifold.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.6)
        }
    }

    private func checkoutDetailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(pf(13.5))
                .foregroundStyle(PayVisual.secondaryInk)
            Spacer(minLength: 12)
            Text(value)
                .font(pf(13.5, .medium))
                .foregroundStyle(C.label)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
    }

    private var faceConfirmPanel: some View {
        VStack(spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                facePay()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "faceid")
                        .font(.system(size: 20, weight: .semibold))
                    Text(Tr("使用面容 ID 确认"))
                        .font(pf(16.5, .semibold))
                }
                .foregroundStyle(C.cardBg)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(C.label,
                            in: RoundedRectangle(cornerRadius: 14,
                                                 style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(scheme == .dark ? 0.16 : 0.05),
                                lineWidth: 0.6)
                }
            }
            .buttonStyle(AppleCheckoutButtonStyle())
            .disabled(busy)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    usePassword = true
                    password = ""
                    payHint = nil
                }
            } label: {
                Text(Tr("改用支付密码"))
                    .font(pf(13.5, .medium))
                    .foregroundStyle(PayVisual.tint)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)

            if amount > balance {
                Button {
                    recharge()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(Tr("充值余额"))
                            .font(pf(13, .semibold))
                    }
                    .foregroundStyle(C.link)
                    .padding(.horizontal, 12)
                    .frame(height: 31)
                    .background(C.link.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 1)
    }

    private var passwordPanel: some View {
        checkoutSurface {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Tr("输入 6 位支付密码完成这笔转账"))
                        .font(pf(13, .medium))
                }
                .foregroundStyle(PayVisual.secondaryInk)

                PayDotField(count: password.count,
                            shake: badPwd ? -6 : 0,
                            height: 48)
                    .padding(.horizontal, -20)

                if let hint = payHint {
                    Text(hint)
                        .font(pf(13.5))
                        .foregroundStyle(PayVisual.danger)
                        .multilineTextAlignment(.center)
                } else if !hasPwd {
                    Text(Tr("还没设置支付密码：我 → 设置 → 账号与安全 → 支付密码"))
                        .font(pf(13))
                        .foregroundStyle(PayVisual.secondaryInk)
                        .multilineTextAlignment(.center)
                } else if amount > balance {
                    Button {
                        recharge()
                    } label: {
                        Text("余额只剩 ¥\(money(balance))，点这里去充值")
                            .font(pfMoney(13.5))
                            .foregroundStyle(C.link)
                    }
                    .buttonStyle(.plain)
                }

                if faceOK {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            usePassword = false
                            password = ""
                            payHint = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "faceid")
                            Text(Tr("改用面容 ID"))
                        }
                        .font(pf(13, .medium))
                        .foregroundStyle(PayVisual.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var paymentTrustLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(PayVisual.secondaryInk)
                .padding(.top, 1)
            Text(Tr("金额与收款方确认后将立即安全提交"))
                .font(pf(12))
                .foregroundStyle(PayVisual.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 3)
    }

    private func checkoutSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) { content() }
            .background(PayVisual.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(C.hairline.opacity(0.54), lineWidth: 0.55)
            }
    }

    private func tapPay(_ k: String) {
        if k == "⌫" {
            if !password.isEmpty { password.removeLast() }
            payHint = nil
            return
        }
        guard password.count < 6 else { return }
        password += k
        payHint = nil
        badPwd = false
        if password.count == 6 && !busy { submit(face: false) }
    }

    private func closePay() {
        withAnimation(.easeOut(duration: 0.22)) {
            showPay = false
            showMethod = false
        }
        password = ""
        usePassword = false
        payHint = nil
        badPwd = false
    }

    private var methodSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    PaySectionLabel(text: Tr("选择付款方式"))

                    checkoutSurface {
                        VStack(spacing: 0) {
                            methodRow("balance", Tr("星言零钱"),
                                      "¥" + money(balance))

                            if XYPay.on {
                                HairLine(inset: 68)
                                methodRow("xypay", XYPay.name,
                                          XYPay.cardLine + " · ¥" + money(balance))
                            }
                        }
                    }

                    Button {
                        recharge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text(Tr("充值余额"))
                                .font(pf(15, .semibold))
                        }
                        .foregroundStyle(PayVisual.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(PayVisual.card,
                                    in: RoundedRectangle(cornerRadius: 14,
                                                         style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, max(24, L.safeBottom))
            }
            .background(PayVisual.canvas.ignoresSafeArea())
            .navigationTitle(Tr("付款方式"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Tr("关闭")) {
                        showMethod = false
                    }
                }
            }
        }
    }

    private func methodRow(_ key: String, _ name: String, _ sub: String) -> some View {
        Button {
            method = key
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.22)) { showMethod = false }
            app.show(Tr("付款方式：") + name)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x303034), Color(hex: 0x08080A)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: key == "xypay"
                          ? "creditcard.fill" : "wallet.bifold.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.65)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(pf(15, .semibold))
                        .foregroundColor(C.label)
                    Text(sub)
                        .font(pf(12.5))
                        .foregroundColor(PayVisual.secondaryInk)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(method == key
                                ? PayVisual.tint
                                : PayVisual.secondaryInk.opacity(0.34),
                                lineWidth: 1.1)
                        .frame(width: 23, height: 23)
                    if method == key {
                        Circle()
                            .fill(PayVisual.tint)
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(method == key
                          ? PayVisual.tint.opacity(scheme == .dark ? 0.14 : 0.08)
                          : PayVisual.card.opacity(scheme == .dark ? 0.76 : 0.82))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(method == key
                            ? PayVisual.tint.opacity(0.36)
                            : C.hairline.opacity(0.58),
                            lineWidth: method == key ? 0.9 : 0.6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recharge() {
        Task {
            if let b = try? await API.shared.recharge(500) {
                app.me = try? await API.shared.me()
                app.show("充值成功，余额 ¥\(money(b))")
            }
        }
    }

    private var resultPage: some View {
        VStack(spacing: 0) {

            HStack {
                Spacer(minLength: 0)
                Menu {
                    Button { showBills = true } label: { Label(Tr("查看账单"), systemImage: "list.bullet.rectangle") }
                    Button { again() } label: { Label(Tr("再转一笔"), systemImage: "arrow.triangle.2.circlepath") }
                    Button { showPayHelp = true } label: { Label(Tr("转账帮助"), systemImage: "questionmark.circle") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)

            Spacer().frame(height: 36)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                PayVisual.success.opacity(0.22),
                                PayVisual.success.opacity(0.04)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.52),
                                    lineWidth: 0.8)
                    }
                Image(systemName: "checkmark")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(PayVisual.success)
            }
            Text(Tr("转账已发出"))
                .font(pf(23, .semibold))
                .foregroundColor(C.label)
                .padding(.top, 16)
            StarPayAmount(value: doneAmount, role: .sheet, color: C.label)
                .padding(.top, 8)
            PayStatusPill(text: Tr("等待对方确认收款"), tone: .processing)
                .padding(.top, 12)
            Text(Tr("对方确认后款项进入其零钱；24 小时未确认将自动退回。"))
                .font(pf(13))
                .foregroundColor(PayVisual.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 12)

            checkoutSurface {
                VStack(spacing: 0) {
                    resultRow(Tr("收款方"), chat.name)
                    HairLine(inset: 18)
                    resultRow(Tr("付款方式"), methodName)
                    HairLine(inset: 18)
                    resultRow(Tr("剩余零钱"), "¥" + money(balance))
                    if !note.isEmpty {
                        HairLine(inset: 18)
                        resultRow(Tr("转账说明"), note)
                    }
                    if let id = receipt?.transfer?.id, !id.isEmpty {
                        HairLine(inset: 18)
                        resultRow(Tr("转账单号"), id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showBills = true
                } label: {
                    Text(Tr("查看账单"))
                        .font(pf(16, .semibold))
                        .foregroundStyle(C.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(C.hairline.opacity(0.76), lineWidth: 0.65)
                        }
                }
                .buttonStyle(AppleCheckoutButtonStyle())

                Button {
                    dismiss()
                } label: {
                    Text(Tr("完成"))
                        .font(pf(17, .semibold))
                        .foregroundStyle(C.cardBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(C.label,
                                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.06),
                                        lineWidth: 0.6)
                        }
                        .shadow(color: .black.opacity(0.17), radius: 12, y: 6)
                }
                .buttonStyle(AppleCheckoutButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, max(26, L.safeBottom))
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                PayVisual.canvas
                RadialGradient(
                    colors: [
                        PayVisual.success.opacity(scheme == .dark ? 0.08 : 0.06),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 30,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
    }

    private func resultRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(pf(15)).foregroundColor(C.subLabel)
            Spacer()
            Text(v).font(pf(15)).foregroundColor(C.label)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
    }

    private func again() {
        withAnimation(.easeOut(duration: 0.2)) {
            step = 0
            digits = ""
            note = ""
            password = ""
            payHint = nil
            doneAmount = 0
            receipt = nil
        }
    }

    private func facePay() {
        guard amount > 0 else { app.show(Tr("请先输入转账金额")); return }
        Task {
            let r = await Biometrics.authenticate(
                reason: "验证身份，向 \(chat.name) 转账 ¥\(money(amount))")
            if r.ok {
                payHint = nil
                submit(face: true)
            } else if !r.message.isEmpty {
                payHint = r.message
            }
        }
    }

    private func submit(face: Bool) {
        guard amount > 0 else { return }
        if !face && hasPwd && password.count < 6 {
            payHint = "请输入 6 位支付密码"
            return
        }
        busy = true
        payHint = nil
        Task {
            do {
                let result = try await API.shared.transfer(
                    chatId: chat.id, amount: amount, note: note,
                    method: method, password: password, face: face)
                receipt = result
                doneAmount = result.amount ?? amount
                app.me = try? await API.shared.me()
                password = ""
                busy = false
                withAnimation(.easeOut(duration: 0.22)) {
                    showPay = false
                    step = 1
                }

                onPaid()
                await app.loadChats()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? "转账失败"
                password = ""

                if msg.contains("需要人脸验证") {
                    payHint = msg
                    needFaceForRisk = true
                    busy = false
                    return
                }
                badPwd = true
                payHint = msg
                try? await Task.sleep(nanoseconds: 420_000_000)
                badPwd = false
            }
            busy = false
        }
    }
}

private struct AppleCheckoutButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82),
                       value: configuration.isPressed)
    }
}

extension View {
    func twoLayerCard(radius: CGFloat = 18, pad: CGFloat = 12) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(C.cardBg))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(C.hairline, lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            .padding(.horizontal, pad)
    }
}

struct TopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

let payClose = """
<svg data-key="pay.close" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"><path d="M5.8 5.8l12.4 12.4M18.2 5.8L5.8 18.2"/></svg>
"""

let payChev = """
<svg data-key="pay.chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.8 5.6l6.4 6.4-6.4 6.4"/></svg>
"""

let payTick = """
<svg data-key="pay.tick" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4.9 12.7l4.7 4.7 9.5-10.4"/></svg>
"""

let payBalanceIcon = """
<svg data-key="pay.balance" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.6"/><path d="M12 6.6v10.8M9.4 9.2h4.2a2.1 2.1 0 0 1 0 4.2H9.4h4.6a2.1 2.1 0 0 1 0 4.2H9.4"/></svg>
"""

let payCardIcon = """
<svg data-key="pay.card" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3.2" y="5.6" width="17.6" height="12.8" rx="2.6"/><path d="M3.2 10.2h17.6"/><path d="M6.6 14.6h3.4"/></svg>
"""

func money(_ v: Double) -> String {
    moneyFmt(v)
}
