import SwiftUI
import UIKit

final class ChatScrollHandle {
    static let shared = ChatScrollHandle()
    weak var scroll: UIScrollView?

    @discardableResult
    func pinToBottom(animated: Bool) -> Bool {
        guard let sv = scroll, sv.window != nil else { return false }
        let bottom = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom
        let y = max(bottom, -sv.adjustedContentInset.top)
        sv.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
        return true
    }

    var gap: CGFloat? {
        guard let sv = scroll, sv.window != nil else { return nil }
        let maxY = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom
        return maxY - sv.contentOffset.y
    }

    var moving: Bool {
        guard let sv = scroll else { return false }
        return sv.isDragging || sv.isDecelerating || sv.isTracking
    }

    func windowRect(fromContent rect: CGRect) -> CGRect {
        guard let sv = scroll, sv.window != nil else { return rect }
        return sv.convert(rect, to: nil)
    }
}

final class ChatScrollDiag: ObservableObject {
    static let shared = ChatScrollDiag()
    @Published private(set) var lines: [String] = []

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func note(_ reason: String) {
        let gap = ChatScrollHandle.shared.gap
        let g = gap.map { String(Int($0)) } ?? "?"
        let hand = ChatScrollHandle.shared.moving ? "指" : "-"
        let line = fmt.string(from: Date()) + " " + hand + " 离底" + g + "  " + reason
        if Thread.isMainThread {
            push(line)
        } else {
            DispatchQueue.main.async { self.push(line) }
        }
    }

    private func push(_ line: String) {
        lines.append(line)
        if lines.count > 14 { lines.removeFirst(lines.count - 14) }
    }

    func clear() { lines.removeAll() }
}

struct ChatScrollDiagView: View {
    @ObservedObject private var diag = ChatScrollDiag.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("滚动诊断 · 点一下清空")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text(diag.lines.isEmpty ? "（还没有记录）" : "\(diag.lines.count) 条")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.7))
            }
            ForEach(diag.lines.indices, id: \.self) { i in
                Text(diag.lines[i])
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .contentShape(Rectangle())
        .onTapGesture { diag.clear() }
        .allowsHitTesting(true)
    }
}

struct ScrollOffsetProbe: UIViewRepresentable {
    final class Coordinator {
        var obsOffset: NSKeyValueObservation?
        var obsDrag: NSKeyValueObservation?
        var obsBounds: NSKeyValueObservation?
        var obsSize: NSKeyValueObservation?
        var scroll: UIScrollView?
        var report: (CGFloat) -> Void = { _ in }
        var reportDrag: (Bool) -> Void = { _ in }
        var reportBounds: () -> Void = { }
        var reportSize: () -> Void = { }

        func attach(_ sv: UIScrollView) {
            scroll = sv
            ChatScrollHandle.shared.scroll = sv

            sv.alwaysBounceVertical = true
            obsOffset = sv.observe(\.contentOffset, options: [.new]) { [weak self] s, _ in
                self?.report(s.contentOffset.y)
            }
            obsDrag = sv.observe(\.isDragging, options: [.new]) { [weak self] s, _ in
                self?.reportDrag(s.isDragging)
            }

            obsBounds = sv.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                self?.reportBounds()
            }

            obsSize = sv.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                self?.reportSize()
            }
        }
    }

    var onChange: (CGFloat) -> Void

    var onDragChange: (Bool) -> Void = { _ in }

    var onBoundsChange: () -> Void = { }

    var onSizeChange: () -> Void = { }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.report = onChange
        context.coordinator.reportDrag = onDragChange
        context.coordinator.reportBounds = onBoundsChange
        context.coordinator.reportSize = onSizeChange
        Self.bind(uiView, context.coordinator, attempt: 0)
    }

    private static func bind(_ uiView: UIView, _ c: Coordinator, attempt: Int) {
        if let sv = findScroll(uiView) {
            if c.scroll !== sv { c.attach(sv) }
            c.report(sv.contentOffset.y)
            c.reportDrag(sv.isDragging)
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            bind(uiView, c, attempt: attempt + 1)
        }
    }

    static func findScroll(_ view: UIView) -> UIScrollView? {
        var cur: UIView? = view
        while let v = cur {
            if let s = v as? UIScrollView { return s }
            cur = v.superview
        }
        return nil
    }
}
