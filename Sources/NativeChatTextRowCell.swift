import UIKit

struct NativeChatTextRowModel {
    var messageID: String
    var text: String
    var mine: Bool
    var senderName: String
    var senderNameColor: UIColor
    var avatarPath: String
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
    var bubbleGlass: Bool
    var showsAvatar: Bool = true
    var reservesAvatarSpace: Bool = true
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
    var glass = false {
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
        let tail: CGFloat = showTail ? 6 : 0
        let body = CGRect(
            x: mine ? 0 : tail,
            y: 0,
            width: max(0, bounds.width - tail),
            height: bounds.height
        )
        let path = UIBezierPath(
            roundedRect: body,
            cornerRadius: glass ? min(22, body.height / 2) : 7
        )
        if showTail {
            let tipY = min(22, max(13, body.height * 0.28))
            if mine {
                path.move(to: CGPoint(x: body.maxX - 1, y: tipY - 5))
                path.addLine(to: CGPoint(x: bounds.maxX, y: tipY))
                path.addLine(to: CGPoint(x: body.maxX - 1, y: tipY + 5))
            } else {
                path.move(to: CGPoint(x: body.minX + 1, y: tipY - 5))
                path.addLine(to: CGPoint(x: bounds.minX, y: tipY))
                path.addLine(to: CGPoint(x: body.minX + 1, y: tipY + 5))
            }
        }
        path.close()
        let dark = traitCollection.userInterfaceStyle == .dark
        let surface = ChatSurfaceMaterial.uiBubble(
            base: fillColor,
            mine: mine,
            dark: dark,
            glass: glass
        )
        surface.fill.setFill()
        path.fill()
        guard glass, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        path.addClip()
        let colors = [
            surface.highlight.cgColor,
            UIColor.clear.cgColor,
            surface.shade.cgColor
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.52, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: bounds.height),
                options: []
            )
        }
        context.restoreGState()
        surface.border.setStroke()
        path.lineWidth = 0.8
        path.stroke()
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

final class NativeChatTextRowView: UIView {
    private let avatar = NativeStaticAvatarView()
    private let senderLabel = UILabel()
    private let bubble = NativeChatBubbleBackground()
    private let textLabel = UILabel()
    private var model: NativeChatTextRowModel?
    private var onTap: (() -> Void)?
    private var onLongPress: (() -> Void)?
    private var onAvatarTap: (() -> Void)?
    private var cachedLayoutWidth: CGFloat = -1
    private var cachedLayout: (
        nameHeight: CGFloat,
        textHeight: CGFloat,
        bubbleHeight: CGFloat,
        bubbleWidth: CGFloat
    )?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        senderLabel.numberOfLines = 1
        senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        textLabel.numberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        addSubview(avatar)
        addSubview(senderLabel)
        addSubview(bubble)
        bubble.addSubview(textLabel)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.42
        long.cancelsTouchesInView = false
        long.delaysTouchesBegan = false
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
            avatar.configure(path: next.avatarPath, name: next.senderName)
        }
        senderLabel.text = next.senderName
        senderLabel.textColor = next.senderNameColor
        bubble.fillColor = next.bubbleColor
        bubble.mine = next.mine
        bubble.showTail = next.showTail
        bubble.glass = next.bubbleGlass
        textLabel.attributedText = attributedText(next)
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

    private func attributedText(_ model: NativeChatTextRowModel) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
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
        let raw = value.string as NSString
        let regex = try? NSRegularExpression(pattern: "@[^\\s，。！？,!?]+")
        regex?.enumerateMatches(in: value.string,
                                range: NSRange(location: 0, length: raw.length)) {
            match, _, _ in
            guard let range = match?.range else { return }
            value.addAttribute(.foregroundColor, value: model.mentionColor, range: range)
        }
        return value
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }
        let available = max(1, bounds.width - model.horizontalMargin * 2)
        let resolved: (
            nameHeight: CGFloat,
            textHeight: CGFloat,
            bubbleHeight: CGFloat,
            bubbleWidth: CGFloat
        )
        if let cachedLayout, abs(cachedLayoutWidth - available) < 0.5 {
            resolved = cachedLayout
        } else {
            resolved = Self.resolvedLayout(model, width: available)
            cachedLayout = resolved
            cachedLayoutWidth = available
        }
        let top = resolved.nameHeight
        let avatarReserve = model.reservesAvatarSpace
            ? model.avatarSize + model.avatarGap
            : 0
        let avatarX = model.mine
            ? model.horizontalMargin + available - model.avatarSize
            : model.horizontalMargin
        avatar.frame = CGRect(x: avatarX, y: top, width: model.avatarSize, height: model.avatarSize)
        let tailInset: CGFloat = model.showTail ? 6 : 0
        let bubbleX = model.mine
            ? model.horizontalMargin + available - resolved.bubbleWidth + tailInset
            : model.horizontalMargin + avatarReserve - tailInset
        bubble.frame = CGRect(
            x: bubbleX,
            y: top,
            width: resolved.bubbleWidth,
            height: resolved.bubbleHeight
        )
        textLabel.frame = CGRect(
            x: (model.mine ? 0 : tailInset) + model.bubblePadH,
            y: model.bubblePadV,
            width: resolved.bubbleWidth - tailInset - model.bubblePadH * 2,
            height: resolved.textHeight
        )
        senderLabel.isHidden = model.senderName.isEmpty
        senderLabel.textAlignment = model.mine ? .right : .left
        let nameX = model.mine
            ? model.horizontalMargin
            : model.horizontalMargin + avatarReserve
        let nameWidth = available - avatarReserve
        senderLabel.frame = CGRect(x: nameX, y: 0, width: max(0, nameWidth), height: resolved.nameHeight)
    }

    static func height(for model: NativeChatTextRowModel, width: CGFloat) -> CGFloat {
        let available = max(1, width - model.horizontalMargin * 2)
        let resolved = resolvedLayout(model, width: available)
        return resolved.nameHeight + resolved.bubbleHeight + model.bottomGap
    }

    private static func resolvedLayout(
        _ model: NativeChatTextRowModel,
        width: CGFloat
    ) -> (nameHeight: CGFloat, textHeight: CGFloat, bubbleHeight: CGFloat, bubbleWidth: CGFloat) {
        let nameHeight: CGFloat = model.senderName.isEmpty ? 0 : 17
        let usable = width - (model.reservesAvatarSpace
            ? model.avatarSize + model.avatarGap
            : 0)
        let maxBubble = max(80, min(model.maxBubbleWidth, usable))
        let tailInset: CGFloat = model.showTail ? 6 : 0
        let textWidth = max(1, maxBubble - tailInset - model.bubblePadH * 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.lineBreakMode = .byWordWrapping
        let text = ClassicEmojiSet.expand(model.text) as NSString
        let bounds = text.boundingRect(
            with: CGSize(width: textWidth, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: pfUIFont(L.chatFontSize),
                .paragraphStyle: paragraph
            ],
            context: nil
        )
        let textHeight = max(17, ceil(bounds.height))
        let textPixelWidth = min(
            textWidth,
            ceil(text.size(withAttributes: [.font: pfUIFont(L.chatFontSize)]).width)
        )
        let bubbleWidth = min(
            maxBubble,
            max(44, textPixelWidth + model.bubblePadH * 2 + tailInset)
        )
        let bubbleHeight = textHeight + model.bubblePadV * 2
        return (nameHeight, textHeight, bubbleHeight, bubbleWidth)
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
