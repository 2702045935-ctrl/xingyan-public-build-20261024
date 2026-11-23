import UIKit

enum WhatsAppChatLayout {
    static let version = 2
    static let directAvatarSide: CGFloat = L.chatAvatar
    static let groupAvatarSide: CGFloat = 34
    static var avatarSide: CGFloat { directAvatarSide }
    static var avatarGap: CGFloat { L.chatGapMsg }
    static var bubblePadH: CGFloat { L.bubblePadH }
    static var bubblePadV: CGFloat { L.bubblePadV }
    static let senderHeight: CGFloat = 16
    static let metadataHeight: CGFloat = 13
    static let metadataGap: CGFloat = 1
    static let inlineMetadataGap: CGFloat = 7
    static let tailInset: CGFloat = 0
    static let sameRunGap: CGFloat = 3
    static let runGap: CGFloat = 9
    static let metadataFont = UIFontMetrics(forTextStyle: .caption2)
        .scaledFont(for: .systemFont(ofSize: 10.5, weight: .regular))

    static var maxBubbleWidth: CGFloat {
        L.bubbleMaxW
    }

    static func metadataWidth(time: String, tickCount: Int) -> CGFloat {
        guard !time.isEmpty else { return tickCount > 0 ? 13 : 0 }
        let textWidth = ceil(
            (time as NSString).size(withAttributes: [.font: metadataFont]).width
        )
        return textWidth + (tickCount > 0 ? 15 : 0)
    }
}

private final class WhatsAppTickView: UIView {
    var tickCount = 1 {
        didSet { setNeedsDisplay() }
    }
    var tint: UIColor = .secondaryLabel {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        let count = max(0, min(2, tickCount))
        guard count > 0 else { return }
        let path = UIBezierPath()
        let offsets: [CGFloat] = count == 2 ? [0, 4.2] : [1.5]
        for offset in offsets {
            path.move(to: CGPoint(x: 1 + offset, y: 6.2))
            path.addLine(to: CGPoint(x: 3.4 + offset, y: 8.4))
            path.addLine(to: CGPoint(x: 8.2 + offset, y: 3.2))
        }
        tint.setStroke()
        path.lineWidth = 1.35
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

final class NativeMessageMetadataView: UIView {
    private let timeLabel = UILabel()
    private let ticks = WhatsAppTickView()
    private var tickCount = 0
    private var mediaStyle = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        timeLabel.font = WhatsAppChatLayout.metadataFont
        timeLabel.textAlignment = .right
        addSubview(timeLabel)
        addSubview(ticks)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(time: String,
                   tickCount: Int,
                   tickColor: UIColor,
                   textColor: UIColor,
                   mediaStyle: Bool) {
        self.tickCount = max(0, min(2, tickCount))
        self.mediaStyle = mediaStyle
        timeLabel.text = time
        timeLabel.textColor = textColor
        timeLabel.font = mediaStyle
            ? UIFont.systemFont(ofSize: 10.5, weight: .semibold)
            : WhatsAppChatLayout.metadataFont
        ticks.tickCount = self.tickCount
        ticks.tint = tickColor
        ticks.isHidden = self.tickCount == 0
        setNeedsLayout()
    }

    func preferredWidth() -> CGFloat {
        guard let text = timeLabel.text, !text.isEmpty else {
            return tickCount > 0 ? 14 : 0
        }
        timeLabel.font = mediaStyle
            ? UIFont.systemFont(ofSize: 10.5, weight: .semibold)
            : WhatsAppChatLayout.metadataFont
        let font = timeLabel.font ?? WhatsAppChatLayout.metadataFont
        let textWidth = ceil(
            (text as NSString).size(withAttributes: [.font: font]).width
        )
        let horizontal: CGFloat = mediaStyle ? 10 : 0
        return horizontal + textWidth + (tickCount > 0 ? 15 : 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontal: CGFloat = mediaStyle ? 5 : 0
        let tickWidth: CGFloat = tickCount > 0 ? 14 : 0
        timeLabel.frame = CGRect(
            x: horizontal,
            y: 0,
            width: max(0, bounds.width - horizontal * 2 - tickWidth),
            height: bounds.height
        )
        ticks.frame = CGRect(
            x: timeLabel.frame.maxX,
            y: max(0, (bounds.height - 10) / 2),
            width: tickWidth,
            height: 10
        )
        layer.cornerRadius = mediaStyle ? bounds.height / 2 : 0
        backgroundColor = mediaStyle
            ? UIColor.black.withAlphaComponent(0.42)
            : .clear
    }
}
