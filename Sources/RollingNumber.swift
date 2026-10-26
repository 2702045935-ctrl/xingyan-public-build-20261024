import SwiftUI

struct RollingNumber: View {
    let value: Int
    var font: Font = .system(size: 17, weight: .semibold)
    var color: Color = C.label

    var height: CGFloat = 20

    private var digits: [Int] {
        String(max(0, value)).compactMap { $0.wholeNumberValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, d in
                RollingDigit(value: d, font: font, color: color, height: height)
            }
        }
    }
}

private struct RollingDigit: View {
    let value: Int
    let font: Font
    let color: Color
    let height: CGFloat

    @State private var prev = 0
    @State private var cur = 0

    @State private var settled = true

    var body: some View {
        ZStack {
            Text(String(prev))
                .offset(y: settled ? -height : 0)
            Text(String(cur))
                .offset(y: settled ? 0 : height)
        }
        .font(font)
        .monospacedDigit()
        .foregroundColor(color)
        .frame(height: height)
        .clipped()
        .onAppear { cur = value; prev = value; settled = true }
        .onChange(of: value) { v in
            prev = cur
            cur = v
            settled = false
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.30)) { settled = true }
            }
        }
    }
}
