import SwiftUI

struct PayScoreView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var data: API.PayScore?
    @State private var loading = true

    private var score: Double { data?.score ?? 0 }
    private var levelColor: Color {
        if score >= 700 { return C.green }
        if score >= 600 { return Color(hex: 0x2AAE67) }
        return C.orange
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("支付分"), back: { dismiss() })
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    VStack(spacing: 6) {
                        Text(loading ? "…" : String(Int(score)))
                            .font(pfMoney(52, .medium))
                            .foregroundColor(.white)
                        Text(data?.level ?? "")
                            .font(pf(15, .medium))
                            .foregroundColor(.white)
                        if let d = data {
                            Text(Tr("分数区间 ") + "\(Int(d.min)) - \(Int(d.max))")
                                .font(pf(12))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppDesign.Spacing.xl)
                    .background(LinearGradient(colors: [levelColor, levelColor.opacity(0.75)],
                                               startPoint: .top, endPoint: .bottom))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(Tr("分是怎么来的")).font(pf(13)).foregroundColor(C.subLabel)
                            .padding(.horizontal, AppDesign.Spacing.xs).padding(.bottom, 6)
                        PayGroupCard(horizontalInset: 0) {
                            let dims = data?.dims ?? []
                            ForEach(Array(dims.enumerated()), id: \.element.id) { idx, d in
                                if idx > 0 { HairLine(inset: 16) }
                                dimRow(d)
                            }
                        }
                        if let f = data?.formula, !f.isEmpty {
                            Text(Tr("规则：") + f)
                                .font(pf(12)).foregroundColor(C.subLabel)
                                .padding(.horizontal, 10).padding(.top, AppDesign.Spacing.xs)
                        }
                        if let t = data?.updatedAt, !t.isEmpty {
                            Text(Tr("更新时间：") + rpTime(t) + Tr("　（每月 1 号重算，行为变了分数会跟着变）"))
                                .font(pf(11.5)).foregroundColor(C.subLabel)
                                .padding(.horizontal, 10).padding(.top, AppDesign.Spacing.xxs)
                        }
                    }
                    .padding(.horizontal, AppDesign.Spacing.xs).padding(.top, AppDesign.Spacing.sm)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(Tr("凭支付分可以免押")).font(pf(13)).foregroundColor(C.subLabel)
                            .padding(.horizontal, AppDesign.Spacing.xs).padding(.bottom, 6)
                        PayGroupCard(horizontalInset: 0) {
                            let list = data?.services ?? []
                            if list.isEmpty {
                                Text(Tr("暂时没有可用服务")).font(pf(14)).foregroundColor(C.subLabel)
                                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                            } else {
                                ForEach(Array(list.enumerated()), id: \.element.id) { idx, s in
                                    if idx > 0 { HairLine(inset: 16) }
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(s.name).font(AppDesign.Typography.bodyLarge).foregroundColor(C.label)
                                            Text(s.desc ?? "").font(pf(12)).foregroundColor(C.subLabel)
                                        }
                                        Spacer(minLength: 6)
                                        if s.ok == true {
                                            Text(Tr("可免押")).font(AppDesign.Typography.compactButtonMedium).foregroundColor(C.green)
                                        } else {
                                            Text(Tr("还差 ") + "\(Int(s.gap ?? 0))" + Tr(" 分"))
                                                .font(pf(13)).foregroundColor(C.subLabel)
                                        }
                                    }
                                    .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.profileRowHeight)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppDesign.Spacing.xs).padding(.top, 14)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(Tr("最近的分值变化")).font(pf(13)).foregroundColor(C.subLabel)
                            .padding(.horizontal, AppDesign.Spacing.xs).padding(.bottom, 6)
                        PayGroupCard(horizontalInset: 0) {
                            let list = data?.history ?? []
                            if list.isEmpty {
                                Text(Tr("还没有记录")).font(pf(14)).foregroundColor(C.subLabel)
                                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                            } else {
                                ForEach(Array(list.enumerated()), id: \.element.id) { idx, h in
                                    if idx > 0 { HairLine(inset: 16) }
                                    HStack(spacing: 10) {
                                        Text(h.text).font(pf(15)).foregroundColor(C.label)
                                        Spacer(minLength: 6)
                                        Text((h.delta >= 0 ? "+" : "") + "\(Int(h.delta))")
                                            .font(pfMoney(15))
                                            .foregroundColor(h.delta >= 0 ? C.green : C.red)
                                        Text(rpTime(h.at))
                                            .font(pf(11.5)).foregroundColor(C.subLabel)
                                    }
                                    .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.buttonHeight)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppDesign.Spacing.xs).padding(.top, 14)

                    Text(data?.note ?? "")
                        .font(AppDesign.Typography.caption).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppDesign.Spacing.xl).padding(.top, 14)
                    Color.clear.frame(height: 26)
                }
            }
            .background(PayVisual.canvas)
        }
        .background(PayVisual.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            data = try? await API.shared.payScore()
            loading = false
        }
    }

    private func dimRow(_ d: API.PayScoreDim) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Text(d.name).font(AppDesign.Typography.rowTitleMedium).foregroundColor(C.label)
                if let w = d.max {
                    Text(Tr("满分 ") + "\(Int(w))").font(pf(11.5)).foregroundColor(C.subLabel)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(C.hairline))
                }
                Spacer(minLength: 6)

                if let p = d.points, let m = d.max {
                    Text(moneyTrim(p) + " / " + moneyTrim(m))
                        .font(pfMoney(15))
                        .foregroundColor(scoreColor(p, m))
                } else {
                    Text("\(Int(d.value))").font(pfMoney(15)).foregroundColor(C.subLabel)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.hairline).frame(height: 6)
                    Capsule().fill(scoreColor(d.points ?? d.value, d.max ?? 100))
                        .frame(width: max(6, geo.size.width * CGFloat(max(0, min(100, d.value)) / 100)), height: 6)
                }
            }
            .frame(height: 6)
            Text(d.desc ?? "").font(pf(12)).foregroundColor(C.subLabel)
            if let tip = d.tip, !tip.isEmpty {
                Text(Tr("怎么提升：") + tip).font(pf(12)).foregroundColor(C.green.opacity(0.9))
            }
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, AppDesign.Spacing.sm)
    }

    private func scoreColor(_ got: Double, _ full: Double) -> Color {
        let r = full <= 0 ? 1 : got / full
        if r >= 0.8 { return C.green }
        if r >= 0.5 { return Color(hex: 0xE9A400) }
        return C.orange
    }

    private func moneyTrim(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return abs(r - r.rounded()) < 0.001 ? String(Int(r)) : String(format: "%.1f", r)
    }
}
