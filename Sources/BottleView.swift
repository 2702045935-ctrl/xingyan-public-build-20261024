import SwiftUI

struct BottlePageView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var total = 0
    @State private var showThrow = false
    @State private var picking = false
    @State private var picked: API.APIBottle?
    @State private var emptyNote = ""

    @State private var fx = 0

    @State private var fxAt = Date()

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("漂流瓶"), back: { dismiss() }) {
                Button { showThrow = true } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(C.label)
                        .frame(width: 40, height: 32)
                }
                .buttonStyle(.plain)
            }

            ZStack {

                BottleSea(mode: fx, actionAt: fxAt)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(picked == nil
                         ? (emptyNote.isEmpty ? Tr("海里漂着 ") + String(total) + Tr(" 个瓶子") : emptyNote)
                         : Tr("捞到一个瓶子"))
                        .font(pf(13.5, .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))

                    if let b = picked {

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 30, height: 30)
                                    .overlay(Image(systemName: "person.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.9)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text((b.fromName ?? "").isEmpty ? Tr("一个陌生人") : (b.fromName ?? ""))
                                        .font(pf(13.5, .medium)).foregroundColor(C.label)
                                    Text(shortTime(b.at ?? ""))
                                        .font(pf(11.5)).foregroundColor(C.subLabel)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "water.waves")
                                    .font(.system(size: 13))
                                    .foregroundColor(C.subLabel.opacity(0.7))
                            }
                            Text(b.text)
                                .font(pf(16.5))
                                .foregroundColor(C.label)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 0.9))
                        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        Button { showThrow = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                                Text(Tr("扔一个"))
                            }
                            .font(pf(16, .medium)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().stroke(Color.white.opacity(0.34), lineWidth: 0.9))
                        }
                        .buttonStyle(.plain)
                        Button { Task { await pick() } } label: {
                            HStack(spacing: 7) {
                                if picking {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Text(picking ? Tr("正在捞…") : Tr("捞一个"))
                            }
                            .font(pf(16, .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x45BEFF),
                                                                               Color(hex: 0x1B63D6)],
                                                                      startPoint: .top, endPoint: .bottom)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.26), lineWidth: 0.8))
                            .shadow(color: Color(hex: 0x1B63D6).opacity(0.45), radius: 14, y: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(picking)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, max(26, L.safeBottom + 14))
                }
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .task {
            total = await API.shared.bottleCount()
            netOK = total > 0

            AppLog.error("漂流瓶", "打开页面，海里数量=" + String(total))
        }
        .sheet(isPresented: $showThrow) {
            ThrowBottleSheet { t in

                fxAt = Date()
                fx = 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 900_000_000)
                let ok = await API.shared.throwBottle(text: t)
                if ok {
                    total += 1
                    emptyNote = ""
                    app.show(Tr("瓶子已经扔进海里"))
                }
                fx = 0
                return ok
            }
            .environmentObject(app)
        }
    }

    private func pick() async {
        picking = true
        emptyNote = ""
        picked = nil

        fxAt = Date()
        fx = 2
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let r = await API.shared.pickBottle()
        try? await Task.sleep(nanoseconds: 500_000_000)
        fx = 0
        total = r.total
        netOK = total > 0 || r.bottle != nil
        picking = false
        if let b = r.bottle {
            AppLog.error("漂流瓶", "捞到了 " + b.id + "（海里 " + String(total) + " 个）")
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { picked = b }
        } else {
            AppLog.error("漂流瓶", "捞到空的（total=" + String(total) + "，netOK=" + (netOK ? "1" : "0") + "）")

            if total == 0 && !netOK {
                emptyNote = Tr("连不上服务器（捞不出来）—— 检查一下网络，或稍后再试")
            } else {
                emptyNote = Tr("海里暂时没有别人的瓶子，先扔一个吧")
            }
        }
    }

    @State private var netOK = false

    private func shortTime(_ at: String) -> String {

        let f = ISO8601DateFormatter()
        guard let d = f.date(from: at) else { return "" }
        let o = DateFormatter()
        o.dateFormat = "MM-dd HH:mm"
        return o.string(from: d)
    }
}

struct BottleSea: View {

    var mode: Int

    var actionAt: Date

    @State private var ripples: [Date] = []

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    var body: some View {
        TimelineView(.animation) { ctx in
            let now = ctx.date
            let t = now.timeIntervalSinceReferenceDate
            Canvas { g, size in
                drawSea(&g, size, t)
                drawRipples(&g, size, now)
                drawBottle(&g, size, t, now)
            }
        }

        .onChange(of: actionAt) { _ in
            ripples.append(Date())
            if ripples.count > 6 { ripples.removeFirst(ripples.count - 6) }
        }
    }

    private func drawSea(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {

        let horizon = size.height * 0.36

        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [Color(hex: 0x050B1A),
                                                       Color(hex: 0x0A1B36),
                                                       Color(hex: 0x123A63),
                                                       Color(hex: 0x1E5A8C)]),
                                     startPoint: .zero,
                                     endPoint: CGPoint(x: 0, y: horizon)))

        for i in 0..<52 {
            let fx = Double((i * 37) % 100) / 100.0
            let fy = Double((i * 61) % 34) / 100.0
            let r = 0.9 + Double((i * 13) % 10) / 10.0 * 1.1
            let tw = 0.5 + 0.5 * sin(t * 0.9 + Double(i) * 1.7)
            let rect = CGRect(x: CGFloat(fx) * size.width, y: CGFloat(fy) * size.height,
                              width: CGFloat(r), height: CGFloat(r))
            g.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.18 + 0.34 * tw)))
        }

        let moon = CGPoint(x: size.width * 0.78, y: size.height * 0.13)
        g.fill(Path(ellipseIn: CGRect(x: moon.x - 78, y: moon.y - 78, width: 156, height: 156)),
               with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF2D0).opacity(0.26), Color.clear]),
                                     center: moon, startRadius: 8, endRadius: 78))
        g.fill(Path(ellipseIn: CGRect(x: moon.x - 13, y: moon.y - 13, width: 26, height: 26)),
               with: .color(Color(hex: 0xFFF7E6).opacity(0.94)))

        g.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
               with: .linearGradient(Gradient(colors: [Color(hex: 0x1C5FA0),
                                                       Color(hex: 0x0A2B52),
                                                       Color(hex: 0x04132A)]),
                                     startPoint: CGPoint(x: 0, y: horizon),
                                     endPoint: CGPoint(x: 0, y: size.height)))

        g.fill(Path(CGRect(x: moon.x - 30, y: horizon, width: 60, height: size.height - horizon)),
               with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF2D0).opacity(0.18),
                                                       Color(hex: 0xFFF2D0).opacity(0.05),
                                                       Color.clear]),
                                     startPoint: CGPoint(x: 0, y: horizon),
                                     endPoint: CGPoint(x: 0, y: size.height * 0.92)))

        for layer in 0..<4 {
            let l = Double(layer)
            let amp = 5.0 + l * 4.5
            let speed = (0.34 + l * 0.20) * (layer % 2 == 0 ? 1 : -1)
            let yBase = Double(size.height) * (0.40 + l * 0.10)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: yBase))
            var x: CGFloat = 0
            while x <= size.width {
                let xd = Double(x)
                let y = yBase
                    + sin(xd / 92.0 + t * speed + l) * amp
                    + sin(xd / 37.0 - t * speed * 1.5) * amp * 0.42
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
            g.fill(path, with: .color(Color(hex: 0x1C5FA0)
                .opacity(0.34 + l * 0.17)))
        }
    }

    private func drawRipples(_ g: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let cx = size.width / 2
        let cy = size.height * 0.66
        for r in ripples {
            let age = now.timeIntervalSince(r)
            guard age >= 0, age < 2.0 else { continue }
            let p = age / 2.0
            for k in 0..<2 {
                let pk = clamp01((p - Double(k) * 0.18) / (1 - 0.18 * Double(k)))
                let w = 40 + pk * 165
                let rect = CGRect(x: cx - w, y: cy - w * 0.30, width: w * 2, height: w * 0.60)
                g.stroke(Path(ellipseIn: rect),
                         with: .color(Color.white.opacity((1 - pk) * 0.34)),
                         lineWidth: 1.4)
            }
        }
    }

    private func drawBottle(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double, _ now: Date) {

        let baseX = size.width / 2
        let baseY = size.height * 0.60

        var dx: Double = sin(t * 0.62) * 10
        var dy: Double = sin(t * 0.95) * 7
        var rot: Double = sin(t * 0.72) * 7
        var alpha: Double = 1

        if mode == 1 {
            let p = clamp01(now.timeIntervalSince(actionAt) / 0.95)
            dx += p * 46
            dy -= sin(p * Double.pi) * 148
            rot += p * 540
            alpha = 1 - clamp01((p - 0.72) / 0.28) * 0.85
        } else if mode == 2 {
            let p = clamp01(now.timeIntervalSince(actionAt) / 0.9)
            dy += (1 - p) * 40
            rot += (1 - p) * -14
            alpha = 0.35 + p * 0.65
        }

        var ctx = g
        ctx.translateBy(x: baseX + dx, y: baseY + dy)
        ctx.rotate(by: .degrees(rot))
        ctx.opacity = alpha

        let w: CGFloat = 52, h: CGFloat = 108
        let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

        ctx.fill(Path(ellipseIn: CGRect(x: -w * 1.05, y: -h * 0.72, width: w * 2.1, height: h * 1.44)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x9FE0FF).opacity(0.16), Color.clear]),
                                       center: .zero, startRadius: 6, endRadius: w * 1.05))

        let bodyPath = Path(roundedRect: body, cornerRadius: 17, style: .continuous)
        ctx.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.42), Color(hex: 0xBEE7FF).opacity(0.26)]),
            startPoint: CGPoint(x: body.minX, y: body.minY),
            endPoint: CGPoint(x: body.maxX, y: body.maxY)))
        ctx.stroke(bodyPath, with: .color(Color.white.opacity(0.62)), lineWidth: 1.6)

        let neck = CGRect(x: -7, y: -h / 2 - 16, width: 14, height: 20)
        ctx.fill(Path(roundedRect: neck, cornerRadius: 4, style: .continuous),
                 with: .color(Color.white.opacity(0.42)))
        let cork = CGRect(x: -9, y: -h / 2 - 26, width: 18, height: 12)
        ctx.fill(Path(roundedRect: cork, cornerRadius: 3, style: .continuous),
                 with: .color(Color(hex: 0xC08A4B)))

        for k in 0..<2 {
            let y = cork.minY + 3.5 + CGFloat(k) * 4
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: cork.minX + 2, y: y))
                p.addLine(to: CGPoint(x: cork.maxX - 2, y: y))
            }, with: .color(Color(hex: 0x8A5C2B).opacity(0.7)), lineWidth: 0.8)
        }

        let paper = CGRect(x: -13, y: -6, width: 26, height: 40)
        ctx.fill(Path(roundedRect: paper, cornerRadius: 4, style: .continuous),
                 with: .color(Color(hex: 0xF7F1DE).opacity(0.92)))

        let shine = CGRect(x: -w / 2 + 9, y: -h / 2 + 14, width: 8, height: 46)
        ctx.fill(Path(roundedRect: shine, cornerRadius: 4, style: .continuous),
                 with: .color(Color.white.opacity(0.55)))

        ctx.fill(Path(roundedRect: CGRect(x: w / 2 - 13, y: -h / 2 + 22, width: 3.5, height: 30),
                      cornerRadius: 2, style: .continuous),
                 with: .color(Color.white.opacity(0.30)))
    }
}

struct ThrowBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onThrow: (String) async -> Bool

    @State private var text = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("扔一个漂流瓶"), back: { dismiss() }) {
                Button {
                    Task {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        busy = true
                        let ok = await onThrow(t)
                        busy = false
                        if ok { dismiss() }
                    }
                } label: {
                    Text(busy ? Tr("发送中…") : Tr("扔出去"))
                        .font(pf(16, .medium)).foregroundColor(C.green)
                        .frame(height: 32).padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .font(pf(16))
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                HStack {
                    Text(Tr("说点什么，扔进海里，等陌生人捞到"))
                        .font(pf(12)).foregroundColor(C.subLabel)
                    Spacer(minLength: 0)
                    Text(String(text.count) + "/200").font(pf(12))
                        .foregroundColor(text.count > 200 ? C.red : C.subLabel)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(C.cardBg))
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(C.pageBg.ignoresSafeArea())

        .swipeBack { dismiss() }
        .onChange(of: text) { v in if v.count > 200 { text = String(v.prefix(200)) } }
    }
}
