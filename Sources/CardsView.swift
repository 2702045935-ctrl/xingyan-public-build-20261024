import SwiftUI

struct WalletCard: Decodable, Identifiable, Hashable {
    var id: String
    var userId: String?
    var kind: String?
    var title: String?
    var sub: String?
    var amount: Double?
    var code: String?
    var used: Bool?
    var usedAt: String?
    var validTo: String?
    var note: String?
    var createdAt: String?

    var kindName: String {
        switch kind ?? "coupon" {
        case "member": return Tr("会员卡")
        case "gift":   return Tr("礼品卡")
        case "ticket": return Tr("票")
        default:       return Tr("优惠券")
        }
    }
    var symbol: String {
        switch kind ?? "coupon" {
        case "member": return "crown.fill"
        case "gift":   return "gift.fill"
        case "ticket": return "ticket.fill"
        default:       return "ticket.fill"
        }
    }
    var tint: Color {
        switch kind ?? "coupon" {
        case "member": return Color(hex: 0xD9A13B)
        case "gift":   return Color(hex: 0xC0433F)
        case "ticket": return Color(hex: 0x3E7BD6)
        default:       return C.green
        }
    }
}

private struct WalletCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
                       value: configuration.isPressed)
    }
}

struct CardsView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [WalletCard] = []
    @State private var loading = true
    @State private var open: WalletCard? = nil
    @State private var focusedCardID: String? = nil
    @AppStorage("wallet.deck.tip.seen.v2") private var deckTipSeen = false

    @State private var diagNote = ""

    private var live: [WalletCard] { cards.filter { $0.used != true } }
    private var used: [WalletCard] { cards.filter { $0.used == true } }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("卡包"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if loading && cards.isEmpty {
                        Text(Tr("正在加载…")).font(pf(14)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if cards.isEmpty {
                        Text(Tr("还没有卡券")).font(pf(14)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                        Text(Tr("商家发卡、别人赠送之后会出现在这里")).font(pf(12.5)).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity).padding(.top, 6)
                        if !diagNote.isEmpty {
                            Text(diagNote).font(pf(11.5)).foregroundColor(C.subLabel)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).padding(.horizontal, 26).padding(.top, 10)
                        }
                    } else {
                        if !live.isEmpty {
                            sectionTitle(Tr("可用"))
                            if live.count > 1 && !deckTipSeen {
                                walletDeckTip
                            }
                            walletCardStack(live)
                        }
                        if !used.isEmpty {
                            sectionTitle(Tr("已使用"))
                            cardList(used)
                        }
                        if !diagNote.isEmpty {
                            Text(diagNote).font(pf(11.5)).foregroundColor(C.subLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22).padding(.top, 10)
                        }
                    }
                    Spacer().frame(height: 30)
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
        .sheet(item: $open) { c in cardDetail(c) }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(pf(13)).foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 8)
    }

    private func cardList(_ list: [WalletCard]) -> some View {
        GroupCard {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                if i > 0 { HairLine(inset: 16) }
                Button { open = c } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous)
                                .fill(c.tint.opacity(0.16))
                            Image(systemName: c.symbol)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(c.tint)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title ?? "").font(pf(16)).foregroundColor(C.label).lineLimit(1)
                            Text(subText(c)).font(pf(12.5)).foregroundColor(C.subLabel).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Chevron(size: 9, line: 1.6).padding(.trailing, 3)
                    }
                    .padding(.horizontal, 16).frame(height: 66)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuPressStyle())
            }
        }
    }

    private var walletDeckTip: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PayVisual.gold)
                .frame(width: 30, height: 30)
                .background(PayVisual.gold.opacity(0.10), in: Circle())

            Text(Tr("点后面露出的卡片，可以先把它切到前面再查看"))
                .font(pf(12.5))
                .foregroundStyle(C.label)
                .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                withAnimation(.easeOut(duration: 0.16)) { deckTipSeen = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(C.subLabel)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Tr("关闭提示"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(PayVisual.card, in: RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous)
                .stroke(PayVisual.separator, lineWidth: 0.6)
        }
        .padding(.horizontal, 16)
    }

    private var walletCardHeight: CGFloat {
        min(218, max(194, L.width * 0.54))
    }

    private var walletCardPeek: CGFloat { 42 }

    private func orderedLiveCards(_ list: [WalletCard]) -> [WalletCard] {
        guard let focusedCardID,
              let focused = list.first(where: { $0.id == focusedCardID }) else {
            return list
        }
        return [focused] + list.filter { $0.id != focusedCardID }
    }

    private func walletCardStack(_ list: [WalletCard]) -> some View {
        let ordered = orderedLiveCards(list)
        let stackHeight = walletCardHeight
            + CGFloat(max(0, ordered.count - 1)) * walletCardPeek

        return ZStack(alignment: .top) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, card in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if index == 0 {
                        open = card
                    } else {
                        deckTipSeen = true
                        withAnimation(.spring(response: 0.40, dampingFraction: 0.86)) {
                            focusedCardID = card.id
                        }
                    }
                } label: {
                    walletCardFace(card, isFront: index == 0)
                }
                .buttonStyle(WalletCardPressStyle())
                .scaleEffect(index == 0 ? 1 : 0.975, anchor: .top)
                .opacity(index == 0 ? 1 : max(0.78, 1 - CGFloat(index) * 0.035))
                .offset(y: index == 0
                        ? 0
                        : walletCardHeight - 30 + CGFloat(index - 1) * walletCardPeek)
                .zIndex(Double(ordered.count - index))
                .accessibilityLabel(
                    (card.title ?? card.kindName)
                    + "，" + subText(card)
                    + "，" + Tr(index == 0 ? "当前卡，点按查看详情" : "点按移到前面")
                )
            }
        }
        .frame(height: stackHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, 16)
        .accessibilityHint(Tr("点按后卡切换到前面，再点当前卡查看详情"))
    }

    private func walletCardFace(_ card: WalletCard, isFront: Bool) -> some View {
        let ink = Color.white
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppDesign.Radius.overlay, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [card.tint.opacity(0.96), card.tint, card.tint.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .frame(width: walletCardHeight * 0.92, height: walletCardHeight * 0.92)
                .offset(x: L.width * 0.38, y: -walletCardHeight * 0.42)

            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                .padding(10)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: card.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.16)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.kindName)
                            .font(pf(12, .semibold))
                            .foregroundStyle(ink.opacity(0.74))
                        Text(card.title ?? "")
                            .font(pf(19, .semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(card.used == true ? Tr("已使用") : Tr("星言卡包"))
                        .font(pf(10.5, .semibold))
                        .foregroundStyle(ink.opacity(0.82))
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(Capsule().fill(Color.white.opacity(0.13)))
                }

                Spacer(minLength: 10)

                if let amount = card.amount, amount > 0 {
                    Text("¥" + String(format: "%.0f", amount))
                        .font(pf(28, .bold))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                } else if let sub = card.sub, !sub.isEmpty {
                    Text(sub)
                        .font(pf(16, .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    }

                Spacer(minLength: 8)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(maskedCardCode(card.code))
                            .font(pfStyled(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(ink.opacity(0.84))
                        Text((card.validTo ?? "").isEmpty
                             ? Tr("长期有效")
                             : Tr("有效期至 ") + (card.validTo ?? ""))
                            .font(pf(11))
                            .foregroundStyle(ink.opacity(0.62))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.70))
                        .rotationEffect(.degrees(90))
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: walletCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.overlay, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.overlay, style: .continuous)
                .stroke(Color.white.opacity(isFront ? 0.20 : 0.12), lineWidth: 0.8)
        }
        .shadow(color: card.tint.opacity(isFront ? 0.24 : 0.14),
                radius: isFront ? 14 : 7,
                y: isFront ? 8 : 3)
    }

    private func maskedCardCode(_ code: String?) -> String {
        let raw = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "••••  ••••  ••••" }
        return "••••  ••••  " + String(raw.suffix(4))
    }

    private func subText(_ c: WalletCard) -> String {
        var parts: [String] = [c.kindName]
        if let a = c.amount, a > 0 { parts.append("¥" + String(format: "%.0f", a)) }
        if let v = c.validTo, !v.isEmpty { parts.append(Tr("有效期至 ") + v) }
        if c.used == true { parts.append(Tr("已使用")) }
        return parts.joined(separator: " · ")
    }

    private func cardDetail(_ c: WalletCard) -> some View {
        VStack(spacing: 0) {
            NavBar(title: c.title ?? Tr("卡券"), back: { open = nil })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {

                    VStack(spacing: 8) {
                        Image(systemName: c.symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white)
                        Text(c.title ?? "").font(pf(20, .semibold)).foregroundColor(.white)
                        if let a = c.amount, a > 0 {
                            Text("¥" + String(format: "%.0f", a)).font(pf(26, .bold)).foregroundColor(.white)
                        }
                        if let s = c.sub, !s.isEmpty {
                            Text(s).font(pf(13)).foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .background(
                        LinearGradient(colors: [c.tint, c.tint.opacity(0.72)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
                    .padding(.horizontal, 16)

                    GroupCard {
                        row(Tr("类型"), c.kindName)
                        HairLine(inset: 16)
                        row(Tr("有效期"), (c.validTo ?? "").isEmpty ? Tr("长期有效") : (c.validTo ?? ""))
                        if let n = c.note, !n.isEmpty {
                            HairLine(inset: 16)
                            row(Tr("使用说明"), n)
                        }
                        if c.used == true {
                            HairLine(inset: 16)
                            row(Tr("状态"), Tr("已核销"))
                        }
                    }

                    GroupCard {
                        VStack(spacing: 8) {
                            Text(Tr("核销码")).font(pf(13)).foregroundColor(C.subLabel)
                            Text(c.code ?? "-")
                                .font(pfStyled(size: 22, weight: .semibold, design: .monospaced))
                                .foregroundColor(c.used == true ? C.subLabel : C.label)
                            Text(Tr("到店出示这一串给商家核销"))
                                .font(pf(12)).foregroundColor(C.subLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }

                    if c.used != true {
                        Button {
                            Task {
                                if await API.shared.cardUse(id: c.id) {
                                    app.show(Tr("已核销"))
                                    await load()
                                    open = nil
                                } else {
                                    app.show(Tr("核销失败，可能已经用过了"))
                                }
                            }
                        } label: {
                            Text(Tr("核销这张卡"))
                                .font(pf(17, .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous).fill(C.green))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    Spacer().frame(height: 30)
                }
                .padding(.top, 12)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)

        .swipeBack { open = nil }
    }

    private func row(_ t: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            Text(t).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Text(v).font(pf(14)).foregroundColor(C.subLabel)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 50)
    }

    private func load() async {

        let r = await API.shared.walletCardsDiag()
        DiagLog.shared.note(r.note)
        await MainActor.run {
            cards = r.cards
            diagNote = r.note
            loading = false
            let available = r.cards.filter { $0.used != true }
            let stillAvailable = focusedCardID.map { id in
                available.contains(where: { $0.id == id })
            } ?? false
            if !stillAvailable {
                focusedCardID = available.first?.id
            }
        }
    }
}
