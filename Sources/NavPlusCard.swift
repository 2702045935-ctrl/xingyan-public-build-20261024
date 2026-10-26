import SwiftUI

struct NavPlusItem {
    var title: String
    var symbol: String
    var colors: [Color]
    var action: () -> Void
}

struct NavPlusCard: View {
    var items: [NavPlusItem]

    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 { HairLine(inset: 46) }
                Button {
                    onPick()
                    item.action()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(LinearGradient(colors: item.colors,
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                                .frame(width: 30, height: 30)
                                .shadow(color: item.colors.count > 1 ? item.colors[1].opacity(0.30) : .clear,
                                        radius: 5, y: 2)
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Text(item.title).font(pf(15)).foregroundColor(C.label)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NavPlusRowPressStyle())
            }
        }
        .frame(width: 178)

        .background {
            GlassBackground(shape: RoundedRectangle(cornerRadius: 15, style: .continuous),
                            opacity: UIConfig.num("plusCardAlpha", 0.9),
                            edgeAlpha: UIConfig.num("plusCardEdge", 0.30),
                            shadow: false,
                            seed: 0.75,
                            native: true)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}

private struct NavPlusRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .background(configuration.isPressed ? Color.black.opacity(0.05) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {

    @ViewBuilder
    func navPlusOverlay(_ show: Binding<Bool>, items: [NavPlusItem]) -> some View {
        overlay {
            if show.wrappedValue {

                GeometryReader { g in
                    let overlayTop = g.frame(in: .global).minY
                    let want = L.safeTop + L.navH + UIConfig.num("plusCardTopGap", -2)
                    let padTop = max(0, want - overlayTop)
                    ZStack(alignment: .topTrailing) {

                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.14)) { show.wrappedValue = false }
                            }
                        NavPlusCard(items: items) {
                            withAnimation(.easeOut(duration: 0.12)) { show.wrappedValue = false }
                        }
                        .padding(.top, padTop)
                        .padding(.trailing, UIConfig.num("plusCardRightGap", 10))

                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.42, anchor: .topTrailing)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -10)),
                            removal: .scale(scale: 0.92, anchor: .topTrailing)
                                .combined(with: .opacity)
                        ))
                    }
                }
            }
        }
    }
}
