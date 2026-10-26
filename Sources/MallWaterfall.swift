import SwiftUI

struct DDWaterfallGrid: View {

    let cells: [(view: AnyView, h: CGFloat)]
    var spacing: CGFloat = 10

    @State private var availableWidth: CGFloat = 0
    private var columnWidth: CGFloat { max(0, (availableWidth - spacing) / 2) }

    var body: some View {
        var left: [(view: AnyView, h: CGFloat)] = []
        var right: [(view: AnyView, h: CGFloat)] = []
        var hL: CGFloat = 0
        var hR: CGFloat = 0
        for c in cells {
            if hL <= hR { left.append(c); hL += c.h + spacing }
            else { right.append(c); hR += c.h + spacing }
        }
        return Group {
            if availableWidth > 1 {
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        ForEach(Array(left.enumerated()), id: \.offset) { item in
                            item.element.view.frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .frame(width: columnWidth, alignment: .top)
                    VStack(spacing: spacing) {
                        ForEach(Array(right.enumerated()), id: \.offset) { item in
                            item.element.view.frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .frame(width: columnWidth, alignment: .top)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { g in
                Color.clear.preference(key: DDWaterfallWidthKey.self, value: g.size.width)
            }
        }
        .onPreferenceChange(DDWaterfallWidthKey.self) { w in
            if abs(w - availableWidth) > 0.5 { availableWidth = w }
        }
    }

    static func estimate(_ p: DDProduct) -> CGFloat {
        var h: CGFloat = 1.0

        if p.title.count > 18 { h += 0.12 }
        if p.sold.isEmpty == false { h += 0.04 }
        if p.shop.isEmpty == false { h += 0.04 }
        if p.tags.isEmpty == false { h += 0.05 }
        return h
    }
}

private struct DDWaterfallWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
