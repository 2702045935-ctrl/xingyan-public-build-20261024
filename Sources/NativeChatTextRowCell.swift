import UIKit

struct NativeChatTextRowModel {
    var messageID: String
    var text: String
    var mine: Bool
    var senderName: String
    var senderNameColor: UIColor
    var avatarPath: String
    var avatarName: String
    var avatarSize: CGFloat
    var maxBubbleWidth: CGFloat
    var horizontalMargin: CGFloat
    var avatarGap: CGFloat
    var bubblePadH: CGFloat
    var bubblePadV: CGFloat
    var bottomGap: CGFloat
    var textColor: UIColor
    var bubbleColor: UIColor
    var secondaryColor: UIColor
    var mentionColor: UIColor
    var showTail: Bool
    var showsAvatar: Bool = true
    var reservesAvatarSpace: Bool = true
    var metaText: String
    var metaColor: UIColor
    var tickCount: Int
    var tickColor: UIColor
}

private struct NativeTextLayout {
    var senderHeight: CGFloat
    var textHeight: CGFloat
    var metaHeight: CGFloat
    var bubbleHeight: CGFloat
    var bubbleWidth: CGFloat
    var textWidth: CGFloat
    var inlineMetadata: Bool
    var tailInset: CGFloat
}

final class NativeChatBubbleBackground: UIView {
    var fillColor: UIColor = .clear {
        didSet { setNeedsDisplay() }
    }
    var mine = false {
        didSet { setNeedsDisplay() }
    }
    var showTail = true {
        didSet { setNeedsDisplay() }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let tail: CGFloat = showTail ? WhatsAppChatLayout.tailInset : 0
        let body = CGRect(
            x: mine ? 0 : tail,
            y: 0,
            width: max(0, bounds.width - tail),
            height: bounds.height
        )
        let path = UIBezierPath(
            roundedRect: body,
            cornerRadius: WhatsAppChatLayout.resolvedCornerRadius(for: body.size)
        )
        if showTail {
            // Match BubbleShape exactly: the WhatsApp tail spans y=6...15.
            let tipY = WhatsAppChatLayout.tailCenterY
            if mine {
                path.move(to: CGPoint(
                    x: body.maxX - 1,
                    y: tipY - WhatsAppChatLayout.tailHeight / 2
                ))
                path.addLine(to: CGPoint(x: bounds.maxX, y: tipY))
                path.addLine(to: CGPoint(
                    x: body.maxX - 1,
                    y: tipY + WhatsAppChatLayout.tailHeight / 2
                ))
            } else {
                path.move(to: CGPoint(
                    x: body.minX + 1,
                    y: tipY - WhatsAppChatLayout.tailHeight / 2
                ))
                path.addLine(to: CGPoint(x: bounds.minX, y: tipY))
                path.addLine(to: CGPoint(
                    x: body.minX + 1,
                    y: tipY + WhatsAppChatLayout.tailHeight / 2
                ))
            }
        }
        path.close()
        fillColor.setFill()
        path.fill()
    }
}

final class NativeStaticAvatarView: UIImageView {
    private var requestedPath = ""
    private var requestToken = UUID()
    private let initials = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentMode = .scaleAspectFill
        backgroundColor = UIColor.tertiarySystemFill
        initials.textAlignment = .center
        initials.textColor = .secondaryLabel
        initials.font = .systemFont(ofSize: 13, weight: .semibold)
        addSubview(initials)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        initials.frame = bounds
    }

    func configure(path: String, name: String) {
        let key = ImageCacheKey.stablePath(path)
        initials.text = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
        if key == requestedPath, image != nil { return }
        requestedPath = key
        requestToken = UUID()
        let token = requestToken
        image = nil
        guard !key.isEmpty else { return }
        if let hit = ImageStore.shared.get(key + "#150")
            ?? ImageStore.shared.get(key)
            ?? ImageStore.shared.get(path + "#150")
            ?? ImageStore.shared.get(path) {
            apply(hit)
            return
        }
        guard let url = API.shared.assetURL(path) else { return }
        Task { @MainActor in
            let disk = await Task.detached(priority: .utility) {
                ImageStore.shared.diskRead(key)
            }.value
            let data: Data?
            if let disk {
                data = disk
            } else {
                data = try? await API.shared.imageData(url)
            }
            guard let data, let image = RemoteImage.downsampled(data, maxSide: 150) else {
                return
            }
            ImageStore.shared.putAvatar(key + "#150", image)
            ImageStore.shared.putAvatar(key, image)
            await MainActor.run {
                guard self.requestToken == token, self.requestedPath == key else { return }
                self.apply(image)
            }
        }
    }

    private func apply(_ value: UIImage) {
        image = value
        initials.isHidden = true
    }
}

final class NativeChatTextRowView: UIView, UIGestureRecognizerDelegate {
    private static let mentionRegex = try? NSRegularExpression(
        pattern: "@[^\\s，。！？,!?]+"
    )

    private let avatar = NativeStaticAvatarView()
    private let senderLabel = UILabel()
    private let bubble = NativeChatBubbleBackground()
    private let textLabel = UILabel()
    private let metadata = NativeMessageMetadataView()
    private var model: NativeChatTextRowModel?
    private var onTap: (() -> Void)?
    private var onLongPress: (() -> Void)?
    private var onAvatarTap: (() -> Void)?
    private var cachedLayoutWidth: CGFloat = -1
    private var cachedLayout: NativeTextLayout?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        senderLabel.numberOfLines = 1
        senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        textLabel.numberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        addSubview(avatar)
        addSubview(bubble)
        addSubview(senderLabel)
        addSubview(metadata)
        bubble.addSubview(textLabel)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.42
        long.cancelsTouchesInView = false
        long.delaysTouchesBegan = false
        long.delegate = self
        addGestureRecognizer(long)
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(handleAvatarTap))
        avatarTap.cancelsTouchesInView = false
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(avatarTap)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ next: NativeChatTextRowModel) {
        model = next
        avatar.isHidden = !next.showsAvatar
        if next.showsAvatar {
            avatar.configure(path: next.avatarPath, name: next.avatarName)
        }
        senderLabel.text = next.senderName
        senderLabel.textColor = next.senderNameColor
        bubble.fillColor = next.bubbleColor
        bubble.mine = next.mine
        bubble.showTail = next.showTail
        textLabel.attributedText = attributedText(next)
        metadata.configure(
            time: next.metaText,
            tickCount: next.tickCount,
            tickColor: next.tickColor,
            textColor: next.metaColor,
            mediaStyle: false
        )
        cachedLayout = nil
        cachedLayoutWidth = -1
        accessibilityLabel = next.text
        accessibilityTraits = .button
        setNeedsLayout()
    }

    func setActions(onTap: @escaping () -> Void,
                    onLongPress: @escaping () -> Void,
                    onAvatarTap: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onAvatarTap = onAvatarTap
    }

    func bubbleWindowFrame() -> CGRect {
        convert(bubble.frame, to: nil)
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress?()
    }

    @objc private func handleAvatarTap() {
        onAvatarTap?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        bubble.frame.contains(touch.location(in: self))
    }

    private func attributedText(_ model: NativeChatTextRowModel) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        paragraph.lineBreakMode = .byWordWrapping
        let font = pfUIFont(L.chatFontSize)
        let value = NSMutableAttributedString(
            string: ClassicEmojiSet.expand(model.text),
            attributes: [
                .font: font,
                .foregroundColor: model.textColor,
                .paragraphStyle: paragraph
            ]
        )
        if value.string.contains("@") {
            let raw = value.string as NSString
            Self.mentionRegex?.enumerateMatches(
                in: value.string,
                range: NSRange(location: 0, length: raw.length)
            ) { match, _, _ in
                guard let range = match?.range else { return }
                value.addAttribute(.foregroundColor, value: model.mentionColor, range: range)
            }
        }
        return value
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }
        let available = max(1, bounds.width - model.horizontalMargin * 2)
        let resolved: NativeTextLayout
        if let cachedLayout, abs(cachedLayoutWidth - available) < 0.5 {
            resolved = cachedLayout
        } else {
            resolved = Self.resolvedLayout(model, width: available)
            cachedLayout = resolved
            cachedLayoutWidth = available
        }
        let avatarReserve = model.reservesAvatarSpace
            ? model.avatarSize + model.avatarGap
            : 0
        let avatarX = model.mine
            ? model.horizontalMargin + available - model.avatarSize
            : model.horizontalMargin
        avatar.frame = CGRect(
            x: avatarX,
            y: 1,
            width: model.avatarSize,
            height: model.avatarSize
        )
        let tailInset = resolved.tailInset
        let bubbleRail = model.mine
            ? model.horizontalMargin + available - avatarReserve
            : model.horizontalMargin + avatarReserve
        let bubbleX = model.mine
            ? bubbleRail - resolved.bubbleWidth + tailInset
            : bubbleRail - tailInset
        bubble.frame = CGRect(
            x: bubbleX,
            y: 0,
            width: resolved.bubbleWidth,
            height: resolved.bubbleHeight
        )
        let bodyX = bubble.frame.minX + (model.mine ? 0 : tailInset)
        let bodyWidth = resolved.bubbleWidth - tailInset
        let textY = model.bubblePadV + resolved.senderHeight
        let textX = bodyX + model.bubblePadH
        textLabel.frame = CGRect(
            x: textX - bubble.frame.minX,
            y: textY,
            width: resolved.textWidth,
            height: resolved.textHeight
        )
        senderLabel.isHidden = model.senderName.isEmpty
        senderLabel.textAlignment = model.mine ? .right : .left
        senderLabel.frame = CGRect(
            x: bodyX + model.bubblePadH,
            y: model.bubblePadV,
            width: max(0, bodyWidth - model.bubblePadH * 2),
            height: resolved.senderHeight
        )
        let metaWidth = WhatsAppChatLayout.metadataWidth(
            time: model.metaText,
            tickCount: model.tickCount
        )
        if resolved.inlineMetadata {
            metadata.frame = CGRect(
                x: textX + resolved.textWidth + WhatsAppChatLayout.inlineMetadataGap,
                y: textY + max(0, (resolved.textHeight - WhatsAppChatLayout.metadataHeight) / 2),
                width: metaWidth,
                height: WhatsAppChatLayout.metadataHeight
            )
        } else {
            metadata.frame = CGRect(
                x: bodyX + bodyWidth - model.bubblePadH - metaWidth,
                y: bubble.frame.maxY - model.bubblePadV - WhatsAppChatLayout.metadataHeight,
                width: metaWidth,
                height: WhatsAppChatLayout.metadataHeight
            )
        }
    }

    static func height(for model: NativeChatTextRowModel, width: CGFloat) -> CGFloat {
        let available = max(1, width - model.horizontalMargin * 2)
        let resolved = resolvedLayout(model, width: available)
        return resolved.bubbleHeight + model.bottomGap
    }

    private static func resolvedLayout(
        _ model: NativeChatTextRowModel,
        width: CGFloat
    ) -> NativeTextLayout {
        let senderHeight: CGFloat = model.senderName.isEmpty
            ? 0
            : WhatsAppChatLayout.senderHeight
        let usable = width - (model.reservesAvatarSpace
            ? model.avatarSize + model.avatarGap
            : 0)
        let maxBubble = max(80, min(model.maxBubbleWidth, usable))
        let tailInset: CGFloat = model.showTail
            ? WhatsAppChatLayout.tailInset
            : 0
        let maxBodyWidth = max(1, maxBubble - tailInset)
        let maxTextWidth = max(
            1,
            maxBodyWidth - model.bubblePadH * 2
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        paragraph.lineBreakMode = .byWordWrapping
        let text = ClassicEmojiSet.expand(model.text) as NSString
        let bounds = text.boundingRect(
            with: CGSize(width: maxTextWidth, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: pfUIFont(L.chatFontSize),
                .paragraphStyle: paragraph
            ],
            context: nil
        )
        let lineHeight = ceil(pfUIFont(L.chatFontSize).lineHeight)
        let fullTextHeight = max(lineHeight, ceil(bounds.height))
        let textPixelWidth = min(
            maxTextWidth,
            ceil(text.size(withAttributes: [.font: pfUIFont(L.chatFontSize)]).width)
        )
        let metadataWidth = WhatsAppChatLayout.metadataWidth(
            time: model.metaText,
            tickCount: model.tickCount
        )
        let singleLine = !model.text.contains("\n") && fullTextHeight <= lineHeight + 2
        let canPlaceMetadataInline = singleLine
            && textPixelWidth
                + WhatsAppChatLayout.inlineMetadataGap
                + metadataWidth <= maxTextWidth
        let textWidth: CGFloat
        let textHeight: CGFloat
        let bodyWidth: CGFloat
        let metaHeight: CGFloat
        if canPlaceMetadataInline {
            textWidth = max(1, textPixelWidth)
            textHeight = lineHeight
            bodyWidth = max(
                56,
                model.bubblePadH * 2
                    + textPixelWidth
                    + WhatsAppChatLayout.inlineMetadataGap
                    + metadataWidth
            )
            metaHeight = lineHeight
        } else {
            textWidth = maxTextWidth
            textHeight = fullTextHeight
            bodyWidth = singleLine
                ? min(
                    maxBodyWidth,
                    max(56, textPixelWidth + model.bubblePadH * 2)
                )
                : maxBodyWidth
            metaHeight = WhatsAppChatLayout.metadataHeight
        }
        let bubbleWidth = min(maxBubble, bodyWidth + tailInset)
        let bubbleHeight = model.bubblePadV * 2
            + senderHeight
            + textHeight
            + (canPlaceMetadataInline
                ? 0
                : WhatsAppChatLayout.metadataGap + metaHeight)
        return NativeTextLayout(
            senderHeight: senderHeight,
            textHeight: textHeight,
            metaHeight: metaHeight,
            bubbleHeight: bubbleHeight,
            bubbleWidth: bubbleWidth,
            textWidth: textWidth,
            inlineMetadata: canPlaceMetadataInline,
            tailInset: tailInset
        )
    }
}

final class NativeChatTimeRowView: UIView {
    private let label = UILabel()
    private let capsule = UIView()
    private let blur = UIVisualEffectView(effect: nil)
    private let tint = UIView()
    private var plain = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        capsule.clipsToBounds = true
        capsule.layer.cornerCurve = .continuous
        blur.isUserInteractionEnabled = false
        tint.isUserInteractionEnabled = false
        capsule.addSubview(blur)
        capsule.addSubview(tint)
        label.textAlignment = .center
        label.font = pfUIFont(11.5)
        label.textColor = .secondaryLabel
        capsule.addSubview(label)
        addSubview(capsule)
        updateAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
            || previousTraitCollection?.accessibilityContrast
                != traitCollection.accessibilityContrast {
            updateAppearance()
        }
    }

    private func updateAppearance() {
        capsule.isHidden = plain
        guard !plain else { return }
        if UIAccessibility.isReduceTransparencyEnabled {
            blur.effect = nil
            tint.backgroundColor = .secondarySystemBackground
            capsule.layer.borderWidth = 0
        } else {
            blur.effect = UIBlurEffect(style: traitCollection.userInterfaceStyle == .dark
                                       ? .systemUltraThinMaterialDark
                                       : .systemUltraThinMaterialLight)
            let surface = ChatSurfaceMaterial.uiSystem(
                dark: traitCollection.userInterfaceStyle == .dark,
                plain: false
            )
            tint.backgroundColor = surface.fill
            capsule.layer.borderColor = surface.border.cgColor
            capsule.layer.borderWidth = 0.6
        }
        setNeedsLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, plain: Bool) {
        self.plain = plain
        label.text = text
        accessibilityLabel = text
        updateAppearance()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !plain else {
            label.frame = bounds
            return
        }
        let textSize = label.sizeThatFits(CGSize(width: max(1, bounds.width - 24),
                                                 height: .greatestFiniteMagnitude))
        let width = min(bounds.width, ceil(textSize.width) + 18)
        let height = ceil(textSize.height) + 8
        capsule.frame = CGRect(x: (bounds.width - width) / 2,
                               y: (bounds.height - height) / 2,
                               width: width,
                               height: height)
        capsule.layer.cornerRadius = height / 2
        blur.frame = capsule.bounds
        tint.frame = capsule.bounds
        label.frame = capsule.bounds.insetBy(dx: 9, dy: 4)
    }

    static func height(plain: Bool) -> CGFloat {
        let line = ceil(pfUIFont(11.5).lineHeight)
        return plain ? max(28, line + 8) : max(34, line + 18)
    }
}
