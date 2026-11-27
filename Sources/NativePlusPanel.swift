import SwiftUI
import UIKit

struct NativePlusPanel: UIViewRepresentable {
    let items: [PlusItem]
    let onTap: (PlusItem) -> Void
    let onLongPress: ((PlusItem) -> Bool)?

    static func requiredHeight(for items: [PlusItem]) -> CGFloat {
        let rows = CGFloat(max(1, Int(ceil(Double(min(items.count, 8)) / 4.0))))
        let tileHeight = L.v(48, 14, 52)
        let tileGap = L.v(7, 2.4, 9)
        let gridPad = L.v(14, 4.2, 18)
        let gridGap = L.v(10, 3.2, 14)
        let dotsHeight = L.v(22, 6, 26)
        let needed = gridPad * 2
            + rows * (tileHeight + tileGap + 28)
            + max(0, rows - 1) * gridGap
            + dotsHeight
        return max(panelH, needed)
    }

    func makeUIView(context: Context) -> NativePlusPanelView {
        let view = NativePlusPanelView()
        view.update(items: items, onTap: onTap, onLongPress: onLongPress)
        return view
    }

    func updateUIView(_ view: NativePlusPanelView, context: Context) {
        view.update(items: items, onTap: onTap, onLongPress: onLongPress)
    }
}

final class NativePlusPanelView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let pageHost = UIView()
    private let dots = UIStackView()
    private let hairline = UIView()
    private var items: [PlusItem] = []
    private var pages: [[PlusItem]] = []
    private var pageViews: [NativePlusPageView] = []
    private var onTap: ((PlusItem) -> Void)?
    private var onLongPress: ((PlusItem) -> Bool)?
    private var currentPage = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        addSubview(scrollView)

        scrollView.addSubview(pageHost)

        dots.axis = .horizontal
        dots.alignment = .center
        dots.distribution = .fill
        dots.spacing = L.v(5, 1.6, 7)
        addSubview(dots)

        hairline.backgroundColor = UIColor(C.hairline)
        addSubview(hairline)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(items: [PlusItem],
                onTap: @escaping (PlusItem) -> Void,
                onLongPress: ((PlusItem) -> Bool)?) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        guard self.items != items else { return }
        self.items = items
        rebuildPages()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hairline.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 0.5)
        let dotsHeight = L.v(22, 6, 26)
        scrollView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, bounds.height - dotsHeight)
        )
        pageHost.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width * CGFloat(max(1, pages.count)),
            height: scrollView.bounds.height
        )
        for (index, page) in pageViews.enumerated() {
            page.frame = CGRect(
                x: CGFloat(index) * bounds.width,
                y: 0,
                width: bounds.width,
                height: scrollView.bounds.height
            )
        }
        layoutDots(height: dotsHeight)
        scrollView.contentSize = CGSize(
            width: bounds.width * CGFloat(max(1, pages.count)),
            height: scrollView.bounds.height
        )
        if currentPage >= pages.count {
            currentPage = max(0, pages.count - 1)
        }
        scrollView.contentOffset = CGPoint(
            x: CGFloat(currentPage) * bounds.width,
            y: 0
        )
    }

    private func rebuildPages() {
        pages = stride(from: 0, to: max(1, items.count), by: 8).map { start in
            Array(items[start..<min(start + 8, items.count)])
        }
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll(keepingCapacity: true)
        for page in pages {
            let pageView = NativePlusPageView(items: page)
            pageView.onTap = { [weak self] item in self?.onTap?(item) }
            pageView.onLongPress = { [weak self] item in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let onLongPress = self?.onLongPress, onLongPress(item) { return }
                self?.onTap?(item)
            }
            pageHost.addSubview(pageView)
            pageViews.append(pageView)
        }
        currentPage = min(currentPage, max(0, pages.count - 1))
        rebuildDots()
        setNeedsLayout()
    }

    private func rebuildDots() {
        dots.arrangedSubviews.forEach {
            dots.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        dots.isHidden = pages.count <= 1
        guard pages.count > 1 else { return }
        for index in pages.indices {
            let dot = NativePlusDotView()
            dot.backgroundColor = index == currentPage
                ? UIColor(C.green)
                : UIColor(Color.dyn(0xD6D6D6, 0x4A4A4C))
            dot.tag = index
            dots.addArrangedSubview(dot)
        }
        updateDotSizes()
    }

    private func updateDotSizes() {
        let height = L.v(6, 1.8, 7)
        for (index, dot) in dots.arrangedSubviews.enumerated() {
            let width = index == currentPage ? L.v(14, 4, 16) : height
            (dot as? NativePlusDotView)?.dotSize = CGSize(width: width, height: height)
            dot.backgroundColor = index == currentPage
                ? UIColor(C.green)
                : UIColor(Color.dyn(0xD6D6D6, 0x4A4A4C))
        }
        dots.setNeedsLayout()
        dots.invalidateIntrinsicContentSize()
    }

    private func layoutDots(height: CGFloat) {
        if dots.isHidden {
            dots.frame = CGRect(
                x: 0,
                y: bounds.height - L.v(10, 3, 12),
                width: bounds.width,
                height: 0
            )
            return
        }
        let height = L.v(6, 1.8, 7)
        let widths = pages.indices.map { index in
            index == currentPage ? L.v(14, 4, 16) : height
        }
        let width = widths.reduce(CGFloat(0), +)
            + CGFloat(max(0, widths.count - 1)) * dots.spacing
        dots.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - height,
            width: width,
            height: height
        )
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard bounds.width > 0 else { return }
        currentPage = max(0, min(pages.count - 1,
                                 Int(round(scrollView.contentOffset.x / bounds.width))))
        updateDotSizes()
    }
}

private final class NativePlusDotView: UIView {
    var dotSize = CGSize(width: 6, height: 6) {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize { dotSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

private final class NativePlusPageView: UIView {
    var onTap: ((PlusItem) -> Void)?
    var onLongPress: ((PlusItem) -> Bool)?
    private var tileViews: [NativePlusTileView] = []

    init(items: [PlusItem]) {
        super.init(frame: .zero)
        backgroundColor = .clear
        tileViews = items.map { item in
            let tile = NativePlusTileView(item: item)
            tile.onTap = { [weak self] in self?.onTap?(item) }
            tile.onLongPress = { [weak self] in self?.onLongPress?(item) }
            addSubview(tile)
            return tile
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridPad = L.v(14, 4.2, 18)
        let gridGap = L.v(10, 3.2, 14)
        let rowGap = L.v(10, 3.2, 14)
        let tileGap = L.v(7, 2.4, 9)
        let tileHeight = L.v(48, 14, 52)
        let rowHeight = tileHeight + tileGap + 28
        let usable = max(1, bounds.width - gridPad * 2 - gridGap * 3)
        let tileWidth = usable / 4
        for (index, tile) in tileViews.enumerated() {
            let row = index / 4
            let column = index % 4
            tile.frame = CGRect(
                x: gridPad + CGFloat(column) * (tileWidth + gridGap),
                y: gridPad + CGFloat(row) * (rowHeight + rowGap),
                width: tileWidth,
                height: rowHeight
            )
        }
    }
}

private final class NativePlusTileView: UIControl {
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    private let item: PlusItem
    private let box = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    init(item: PlusItem) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = .clear

        let tileHeight = L.v(48, 14, 52)
        box.isUserInteractionEnabled = false
        box.backgroundColor = NativePlusTileView.color(for: item.action)
        box.layer.cornerRadius = tileHeight * 0.30
        box.layer.cornerCurve = .continuous
        box.layer.borderColor = UIColor.label.withAlphaComponent(0.08).cgColor
        box.layer.borderWidth = 0.5
        addSubview(box)

        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: L.v(20.5, 6.2, 23),
            weight: .semibold
        )
        icon.image = UIImage(systemName: NativePlusTileView.symbol(for: item.action))
        icon.isUserInteractionEnabled = false
        addSubview(icon)

        label.text = chatEntryLabel(item.label, action: item.action)
        label.font = pfUIFont(L.v(12, 3.5, 13), .medium)
        label.textColor = UIColor(C.label)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.78
        label.isUserInteractionEnabled = false
        addSubview(label)

        alpha = item.enabled == false ? 0.45 : 1
        isAccessibilityElement = true
        accessibilityLabel = label.text
        accessibilityTraits = item.enabled == false ? [.button, .notEnabled] : .button
        addTarget(self, action: #selector(triggerTap), for: .touchUpInside)
        addGestureRecognizer(UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tileHeight = L.v(48, 14, 52)
        let tileGap = L.v(7, 2.4, 9)
        box.frame = CGRect(
            x: (bounds.width - tileHeight) / 2,
            y: 6,
            width: tileHeight,
            height: tileHeight
        )
        icon.frame = box.frame.insetBy(dx: tileHeight * 0.18,
                                       dy: tileHeight * 0.18)
        label.frame = CGRect(
            x: 2,
            y: box.frame.maxY + tileGap,
            width: bounds.width - 4,
            height: 17
        )
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.92, y: 0.92)
                    : .identity
            }
        }
    }

    @objc private func triggerTap() {
        guard item.enabled != false else { return }
        onTap?()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard item.enabled != false else { return }
        switch recognizer.state {
        case .began:
            isHighlighted = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let onLongPress {
                onLongPress()
            } else {
                onTap?()
            }
        case .ended, .cancelled, .failed:
            isHighlighted = false
        default:
            break
        }
    }

    private static func symbol(for action: String?) -> String {
        switch (action ?? "").lowercased() {
        case "photo": return "photo.on.rectangle.angled"
        case "camera": return "camera.fill"
        case "video", "videocall": return "video.fill"
        case "voice", "voicecall": return "phone.fill"
        case "location": return "location.fill"
        case "liveshare": return "location.circle.fill"
        case "file": return "doc.fill"
        case "card", "contact": return "person.crop.rectangle"
        case "redpacket": return "envelope.fill"
        case "transfer": return "arrow.left.arrow.right"
        case "gift": return "gift.fill"
        case "music": return "music.note"
        case "screenshare", "screen": return "rectangle.on.rectangle"
        case "favorite", "star": return "star.fill"
        case "coupon": return "ticket.fill"
        case "vote": return "chart.bar.fill"
        case "chain", "link": return "link"
        case "feedback": return "bubble.left.and.bubble.right.fill"
        default: return "plus.circle.fill"
        }
    }

    private static func color(for action: String?) -> UIColor {
        switch (action ?? "").lowercased() {
        case "photo", "camera": return UIColor(C.green)
        case "video", "videocall": return UIColor(hex: 0xFF8A73)
        case "voice", "voicecall": return UIColor(hex: 0x64B5F6)
        case "location", "liveshare": return UIColor(hex: 0x4ECDC4)
        case "redpacket": return UIColor(hex: 0xF4634A)
        case "gift": return UIColor(hex: 0xFFC85C)
        case "transfer": return UIColor(hex: 0xFFC24B)
        case "file": return UIColor(hex: 0x8A93FF)
        case "card": return UIColor(hex: 0xA0A4AE)
        case "favorite", "star": return UIColor(hex: 0xFFD34B)
        case "coupon": return UIColor(hex: 0xFF9F6B)
        case "music": return UIColor(hex: 0xB98CFF)
        case "screen": return UIColor(hex: 0x7FA6E8)
        case "chain", "link": return UIColor(hex: 0x74C0FC)
        case "vote": return UIColor(hex: 0x6FD3A8)
        default: return UIColor(hex: 0xA8ACB6)
        }
    }
}
