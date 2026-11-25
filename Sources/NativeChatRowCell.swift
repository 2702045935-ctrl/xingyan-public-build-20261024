import UIKit

enum NativeChatRowMetrics {
    private static var cachedDynamicScale: CGFloat?
    private static var cachedCombinedScale: CGFloat?

    static var dynamicScale: CGFloat {
        if let cachedDynamicScale { return cachedDynamicScale }
        let base: CGFloat = 17
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: base)
        let resolved = min(1.35, max(1, scaled / base))
        cachedDynamicScale = resolved
        return resolved
    }

    static var combinedScale: CGFloat {
        if let cachedCombinedScale { return cachedCombinedScale }
        let resolved = dynamicScale * CareMode.scale
        cachedCombinedScale = resolved
        return resolved
    }

    static var rowHeight: CGFloat {
        max(73, (73 + (combinedScale - 1) * 34).rounded())
    }

    static func invalidateScaleCache() {
        cachedDynamicScale = nil
        cachedCombinedScale = nil
    }

    static func font(_ size: CGFloat,
                     weight: UIFont.Weight,
                     textStyle: UIFont.TextStyle) -> UIFont {
        let preferred = size * CareMode.scale
        let scaled = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: preferred)
        return .systemFont(ofSize: min(size * combinedScale, scaled), weight: weight)
    }
}

struct NativeChatRowConfiguration {
    var title: String
    var titleColor: UIColor
    var isLight: Bool
    var preview: String
    var mentionPrefix: String
    var previewKind: String
    var highlightMention: Bool
    var previewColor: UIColor
    var time: String
    var timeColor: UIColor
    var rowBackground: UIColor
    var dividerColor: UIColor
    var showsDivider: Bool = true
    var badgeRing: UIColor
    var chatId: String
    var avatarPaths: [String]
    var groupMemberIds: [String]
    var avatarIsGroup: Bool
    var showOnline: Bool
    var musicListening: Bool
    var moodIcon: String
    var unread: Int
    var unreadMuted: Bool
    var isManuallyUnread: Bool
    var levelText: String
    var memberText: String
    var memberColor: UIColor?
    var onOpen: () -> Void
    var onAvatar: (() -> Void)?
    var onUnread: () -> Void
    var onHide: () -> Void
    var onDelete: () -> Void
    var onPin: (Bool) -> Void
    var isPinned: Bool
}

private final class NativeChatAvatarPrefetchLoader {
    static let shared = NativeChatAvatarPrefetchLoader()

    private let lock = NSLock()
    private var inFlight = Set<String>()

    func prefetch(paths: [String]) {
        for raw in paths {
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let key = ImageCacheKey.stablePath(path)
            guard ImageStore.shared.get(key + "#150") == nil,
                  ImageStore.shared.get(key) == nil else { continue }
            lock.lock()
            guard inFlight.count < 64 else {
                lock.unlock()
                break
            }
            guard inFlight.insert(key).inserted else {
                lock.unlock()
                continue
            }
            lock.unlock()

            Task(priority: .utility) {
                var data = await Task.detached(priority: .utility) {
                    ImageStore.shared.diskRead(key)
                        ?? ImageStore.shared.diskRead(path)
                }.value
                if data == nil, let url = API.shared.assetURL(path) {
                    data = try? await API.shared.imageData(url)
                }
                let image = await Task.detached(priority: .utility) {
                    data.flatMap {
                        RemoteImage.downsampled($0, maxSide: 150)
                            ?? UIImage(data: $0)
                    }
                }.value
                if let image {
                    ImageStore.shared.putAvatar(key + "#150", image)
                    ImageStore.shared.putAvatar(key, image)
                }
                self.lock.lock()
                self.inFlight.remove(key)
                self.lock.unlock()
            }
        }
    }
}

enum NativeChatAvatarPrefetcher {
    static func prefetch(_ configuration: NativeChatRowConfiguration) {
        NativeChatAvatarPrefetchLoader.shared.prefetch(paths: configuration.avatarPaths)
        if configuration.avatarIsGroup,
           configuration.avatarPaths.filter({ !$0.isEmpty }).count < 4 {
            let chatId = configuration.chatId
            let memberIds = configuration.groupMemberIds
            Task { @MainActor in
                NativeGroupAvatarCache.shared.paths(
                    chatId: chatId,
                    memberIds: memberIds
                ) { paths in
                    NativeChatAvatarPrefetchLoader.shared.prefetch(paths: paths)
                }
            }
        }
    }
}

final class NativeChatRowCell: UITableViewCell {
    private static let previewAccentInk = UIColor(hex: 0xFA5151)

    private let foreground = UIView()
    private let avatarView = NativeChatAvatarView()
    private let titleLabel = UILabel()
    private let levelLabel = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
    private let memberLabel = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
    private let previewLabel = UILabel()
    private let timeLabel = UILabel()
    private let unreadLabel = PaddingLabel(insets: .zero)
    private let unreadBell = UIImageView()
    private let divider = UIView()
    private let pressOverlay = UIView()
    private var configuration: NativeChatRowConfiguration?
    private var avatarSignature = ""
    private var accessibilitySignature = ""
    private var openGuardUntil: TimeInterval = 0

    private let rowLeading: CGFloat = 16
    private let avatarSize: CGFloat = 48
    private let avatarGap: CGFloat = 13
    private let rowTrailing: CGFloat = 20
    private let timeSlotWidth: CGFloat = 68
    private let timeSlotGap: CGFloat = 8
    private let dividerLeading: CGFloat = 77
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuration = nil
        titleLabel.text = nil
        previewLabel.attributedText = nil
        timeLabel.text = nil
        levelLabel.text = nil
        memberLabel.text = nil
        unreadLabel.text = nil
        levelLabel.isHidden = true
        memberLabel.isHidden = true
        unreadLabel.isHidden = true
        divider.isHidden = true
        foreground.transform = .identity
        unreadBell.isHidden = true
        pressOverlay.backgroundColor = .clear
        openGuardUntil = 0
        avatarView.invalidate()
        avatarSignature = ""
        accessibilitySignature = ""
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        foreground.frame = bounds
        pressOverlay.frame = foreground.bounds
        avatarView.frame = CGRect(x: rowLeading, y: (bounds.height - avatarSize) / 2,
                                  width: avatarSize, height: avatarSize)
        let textX = rowLeading + avatarSize + avatarGap
        let titleWidth = max(
            1,
            bounds.width - textX - rowTrailing - timeSlotWidth - timeSlotGap
        )
        let titleHeight: CGFloat = 22
        levelLabel.sizeToFit()
        memberLabel.sizeToFit()
        let badgeWidth = (
            levelLabel.isHidden ? 0 : levelLabel.bounds.width + 4
        ) + (
            memberLabel.isHidden ? 0 : memberLabel.bounds.width + 4
        )
        let titleTextWidth = max(1, titleWidth - min(72, badgeWidth))
        titleLabel.frame = CGRect(x: 0, y: 0,
                                  width: titleTextWidth, height: titleHeight)
        let resolvedTitleHeight = max(titleHeight, ceil(titleLabel.font.lineHeight))
        let previewHeight = max(19, ceil(previewLabel.font.lineHeight))
        let timeHeight = max(18, ceil(timeLabel.font.lineHeight))
        let titlePreviewGap: CGFloat = 3
        let contentHeight = resolvedTitleHeight + titlePreviewGap + previewHeight
        let contentTop = max(5, (bounds.height - contentHeight) / 2)
        let unread = configuration?.unread ?? 0
        let badgeScale = min(1.4, max(1, unreadLabel.font.pointSize / 10))
        let unreadWidth: CGFloat = configuration?.isManuallyUnread == true
            ? 16
            : (configuration?.unreadMuted == true
                ? 8
                : (unread > 99 ? 28 : (unread > 9 ? 23 : 18)) * badgeScale)
        let unreadHeight = max(18, ceil(unreadLabel.font.lineHeight) + 6)
        titleLabel.frame = CGRect(x: textX,
                                  y: contentTop,
                                  width: titleWidth,
                                  height: resolvedTitleHeight)
        previewLabel.frame = CGRect(x: textX,
                                    y: contentTop + resolvedTitleHeight + titlePreviewGap,
                                    width: titleWidth,
                                    height: previewHeight)
        timeLabel.frame = CGRect(x: bounds.width - rowTrailing - timeSlotWidth,
                                 y: contentTop + (resolvedTitleHeight - timeHeight) / 2 - 3,
                                 width: timeSlotWidth, height: timeHeight)
        unreadLabel.sizeToFit()
        unreadLabel.frame = CGRect(x: bounds.width - rowTrailing - unreadWidth,
                                   y: previewLabel.frame.midY - unreadHeight / 2,
                                   width: unreadWidth,
                                   height: unreadHeight)
        unreadLabel.layer.cornerRadius = configuration?.unreadMuted == true
            ? min(4, unreadHeight / 2)
            : unreadHeight / 2
        unreadBell.frame = CGRect(x: bounds.width - rowTrailing - 16,
                                  y: previewLabel.frame.midY - 8,
                                  width: 16,
                                  height: 16)
        layoutTitleBadges()
        divider.frame = CGRect(x: dividerLeading, y: bounds.height - 0.5,
                               width: bounds.width - dividerLeading, height: 0.5)
    }

    func configure(_ configuration: NativeChatRowConfiguration) {
        self.configuration = configuration
        backgroundColor = configuration.rowBackground
        foreground.backgroundColor = configuration.rowBackground
        let opaque = configuration.rowBackground.cgColor.alpha >= 0.999
        isOpaque = opaque
        foreground.isOpaque = opaque
        foreground.layer.isOpaque = opaque
        contentView.isOpaque = true
        titleLabel.text = configuration.title
        titleLabel.textColor = configuration.titleColor
        titleLabel.font = NativeChatRowMetrics.font(17, weight: .medium, textStyle: .headline)
        previewLabel.font = NativeChatRowMetrics.font(14,
                                                     weight: .regular,
                                                     textStyle: .body)
        timeLabel.font = NativeChatRowMetrics.font(12,
                                                  weight: .regular,
                                                  textStyle: .footnote)
        previewLabel.attributedText = styledPreview(configuration)
        timeLabel.text = configuration.time
        timeLabel.textColor = configuration.timeColor
        divider.backgroundColor = configuration.dividerColor
        divider.isHidden = !configuration.showsDivider
        unreadBell.isHidden = !configuration.isManuallyUnread
        unreadBell.image = UIImage(systemName: "bell.fill")
        unreadBell.tintColor = configuration.timeColor
        unreadBell.contentMode = .scaleAspectFit
        unreadLabel.isHidden = configuration.isManuallyUnread || configuration.unread <= 0
        if !configuration.isManuallyUnread, configuration.unread > 0 {
            if configuration.unreadMuted {
                unreadLabel.text = "●"
                unreadLabel.font = NativeChatRowMetrics.font(7, weight: .bold,
                                                             textStyle: .caption2)
                unreadLabel.backgroundColor = configuration.timeColor
                unreadLabel.textColor = configuration.timeColor
                unreadLabel.layer.cornerRadius = 4
                unreadLabel.frame.size.width = 8
            } else {
                unreadLabel.text = configuration.unread > 99 ? "99+" : "\(configuration.unread)"
                unreadLabel.font = NativeChatRowMetrics.font(10, weight: .bold,
                                                             textStyle: .caption2)
                unreadLabel.backgroundColor = .systemRed
                unreadLabel.textColor = .white
                unreadLabel.layer.cornerRadius = 9
            }
            unreadLabel.layer.borderWidth = 1.5
            unreadLabel.layer.borderColor = configuration.badgeRing.cgColor
            unreadLabel.clipsToBounds = true
            unreadLabel.textAlignment = .center
        }

        levelLabel.isHidden = configuration.levelText.isEmpty
        levelLabel.font = NativeChatRowMetrics.font(8.5, weight: .semibold,
                                                    textStyle: .caption2)
        levelLabel.text = configuration.levelText
        memberLabel.isHidden = configuration.memberText.isEmpty
        memberLabel.font = NativeChatRowMetrics.font(8.5, weight: .semibold,
                                                     textStyle: .caption2)
        memberLabel.text = configuration.memberText
        memberLabel.backgroundColor = configuration.memberColor
        let nextAvatarSignature = [
            configuration.avatarPaths.joined(separator: "\u{1F}"),
            configuration.groupMemberIds.joined(separator: "\u{1F}"),
            configuration.chatId,
            configuration.avatarIsGroup ? "1" : "0",
            configuration.showOnline ? "1" : "0",
            configuration.musicListening ? "1" : "0",
            configuration.moodIcon
        ].joined(separator: "\u{1E}")
        if avatarSignature != nextAvatarSignature {
            avatarSignature = nextAvatarSignature
            avatarView.configure(paths: configuration.avatarPaths,
                                 chatId: configuration.chatId,
                                 memberIds: configuration.groupMemberIds,
                                 group: configuration.avatarIsGroup,
                                 online: configuration.showOnline,
                                 listening: configuration.musicListening,
                                 mood: configuration.moodIcon)
        }
        configureAccessibility(configuration)
        setNeedsLayout()
    }

    private func styledPreview(_ configuration: NativeChatRowConfiguration) -> NSAttributedString {
        let text = configuration.mentionPrefix + configuration.preview
        let prefixLength = (configuration.mentionPrefix as NSString).length
        let bodyLength = (configuration.preview as NSString).length
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: previewLabel.font as Any,
                .foregroundColor: configuration.previewColor
            ]
        )
        if prefixLength > 0 {
            result.addAttributes([
                .font: NativeChatRowMetrics.font(14,
                                                weight: .medium,
                                                textStyle: .body),
                .foregroundColor: Self.previewAccentInk
            ], range: NSRange(location: 0, length: prefixLength))
        }

        let bodyRange = NSRange(location: prefixLength, length: bodyLength)
        guard bodyLength > 0 else { return result }
        let body = configuration.preview
        let bodyText = body as NSString
        let kind = configuration.previewKind

        let draftRegex = try! NSRegularExpression(
            pattern: "(\\[(?:草稿|Draft|Черновик)\\])|^(?:草稿[:：]|Draft:|Черновик:)"
        )
        if kind == "draft" || body.contains("草稿")
            || body.localizedCaseInsensitiveContains("draft") {
            if let match = draftRegex.firstMatch(
                in: body,
                range: NSRange(location: 0, length: bodyText.length)
            ) {
                result.addAttribute(
                    .foregroundColor,
                    value: Self.previewAccentInk,
                    range: NSRange(location: prefixLength + match.range.location,
                                   length: match.range.length)
                )
            }
            return result
        }

        if body.contains("发送失败")
            || body.contains("[失败]")
            || body.localizedCaseInsensitiveContains("failed to send") {
            result.addAttribute(
                .foregroundColor,
                value: Self.previewAccentInk,
                range: bodyRange
            )
            return result
        }

        if let tag = Self.tokenRegex.firstMatch(
               in: body,
               range: NSRange(location: 0, length: bodyText.length)
           ) {
            let token = bodyText.substring(with: tag.range)
            if let color = Self.previewTokenColor(token,
                                                  isLight: configuration.isLight) {
                result.addAttributes([
                    .font: NativeChatRowMetrics.font(14,
                                                    weight: .medium,
                                                    textStyle: .body),
                    .foregroundColor: color
                ], range: NSRange(location: prefixLength + tag.range.location,
                                  length: tag.range.length))
            }
        } else if let color = Self.previewKindColor(kind,
                                                    isLight: configuration.isLight) {
            result.addAttribute(.foregroundColor, value: color, range: bodyRange)
        }

        if configuration.highlightMention {
            let range = NSRange(location: 0, length: bodyText.length)
            for match in Self.mentionRegex.matches(in: body, range: range) {
                result.addAttributes([
                    .font: NativeChatRowMetrics.font(14,
                                                    weight: .medium,
                                                    textStyle: .body),
                    .foregroundColor: Self.previewAccentInk
                ], range: NSRange(location: prefixLength + match.range.location,
                                  length: match.range.length))
            }
        }
        return result
    }

    private static let mentionRegex = try! NSRegularExpression(
        pattern: "@[^\\s，。！？、；：:,!?;()\\[\\]{}<>]+"
    )

    private static let tokenRegex = try! NSRegularExpression(pattern: "\\[[^\\]]+\\]")

    private static func previewTokenColor(_ token: String, isLight: Bool) -> UIColor? {
        /* 微信会话列表中的图片、视频、文件等标签统一保持次级灰，
           只对“有人@我”、草稿和发送失败使用强调色。 */
        return nil
    }

    private static func previewKindColor(_ kind: String, isLight: Bool) -> UIColor? {
        return nil
    }

    private func setupViews() {
        selectionStyle = .none
        backgroundConfiguration = .clear()
        contentView.clipsToBounds = true
        contentView.isOpaque = true
        backgroundColor = .clear

        foreground.clipsToBounds = true
        foreground.isOpaque = true
        contentView.isUserInteractionEnabled = false
        contentView.addSubview(foreground)
        foreground.addSubview(avatarView)
        foreground.addSubview(titleLabel)
        foreground.addSubview(previewLabel)
        foreground.addSubview(timeLabel)
        foreground.addSubview(unreadLabel)
        foreground.addSubview(unreadBell)
        foreground.addSubview(divider)
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.backgroundColor = .clear
        foreground.addSubview(pressOverlay)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        previewLabel.font = .systemFont(ofSize: 14, weight: .regular)
        previewLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        timeLabel.textAlignment = .right
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.75
        unreadLabel.textAlignment = .center
        unreadBell.isHidden = true
        unreadLabel.font = .systemFont(ofSize: 10, weight: .bold)
        unreadLabel.adjustsFontSizeToFitWidth = true
        unreadLabel.minimumScaleFactor = 0.9
        levelLabel.font = .monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
        levelLabel.textColor = .secondaryLabel
        levelLabel.backgroundColor = UIColor.secondarySystemFill
        levelLabel.layer.cornerRadius = 4
        levelLabel.clipsToBounds = true
        memberLabel.font = .systemFont(ofSize: 8.5, weight: .semibold)
        memberLabel.textColor = .white
        memberLabel.layer.cornerRadius = 4
        memberLabel.clipsToBounds = true
    }

    private func layoutTitleBadges() {
        let baseWidth = min(titleLabel.intrinsicContentSize.width,
                            max(1, titleLabel.bounds.width))
        var x = titleLabel.frame.maxX - titleLabel.bounds.width + baseWidth + 5
        if !levelLabel.isHidden {
            levelLabel.sizeToFit()
            levelLabel.frame.origin = CGPoint(x: x, y: titleLabel.frame.midY - levelLabel.bounds.height / 2)
            foreground.addSubview(levelLabel)
            x = levelLabel.frame.maxX + 4
        }
        if !memberLabel.isHidden {
            memberLabel.sizeToFit()
            memberLabel.frame.origin = CGPoint(x: x, y: titleLabel.frame.midY - memberLabel.bounds.height / 2)
            foreground.addSubview(memberLabel)
        }
    }

    func setTouchPressed(_ pressed: Bool) {
        let color: UIColor
        if configuration?.isLight == true {
            color = pressed ? UIColor.black.withAlphaComponent(0.045) : .clear
        } else {
            color = pressed ? UIColor.white.withAlphaComponent(0.07) : .clear
        }
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : (pressed ? 0.07 : 0.14)
        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.pressOverlay.backgroundColor = color
        }
    }

    @discardableResult
    func openFromSelection() -> Bool {
        guard let configuration else { return false }
        let now = Date.timeIntervalSinceReferenceDate
        guard now >= openGuardUntil else { return true }
        openGuardUntil = now + 0.35
        configuration.onOpen()
        return true
    }

    private func localized(_ zh: String, _ en: String, _ ru: String) -> String {
        if Lang.isRussian { return ru }
        if Lang.isEnglish { return en }
        return zh
    }

    private func configureAccessibility(_ configuration: NativeChatRowConfiguration) {
        let signature = [
            configuration.title,
            configuration.preview,
            configuration.mentionPrefix,
            configuration.time,
            String(configuration.unread),
            configuration.isPinned ? "1" : "0",
            Lang.code
        ].joined(separator: "\u{1E}")
        guard accessibilitySignature != signature else { return }
        accessibilitySignature = signature
        isAccessibilityElement = true
        accessibilityTraits = .button
        let unread = configuration.unread > 0
            ? localized("\(configuration.unread) 条未读",
                        "\(configuration.unread) unread",
                        "\(configuration.unread) непрочитанных")
            : ""
        accessibilityLabel = [
            configuration.title,
            unread,
            configuration.time,
            configuration.mentionPrefix + configuration.preview
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "，")
        accessibilityHint = localized("打开聊天，向左滑动可查看更多操作",
                                      "Open chat. Swipe left for more actions",
                                      "Открыть чат. Смахните влево для дополнительных действий")

        let pinTitle = configuration.isPinned
            ? localized("取消置顶", "Unpin", "Открепить")
            : localized("置顶", "Pin", "Закрепить")
        let unreadTitle = localized("标为未读", "Mark unread", "Отметить непрочитанным")
        let hideTitle = localized("不显示", "Hide", "Скрыть")
        let deleteTitle = localized("删除", "Delete", "Удалить")

        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: pinTitle) { [weak self] _ in
                guard let self, let current = self.configuration else { return false }
                current.onPin(!current.isPinned)
                return true
            },
            UIAccessibilityCustomAction(name: unreadTitle) { [weak self] _ in
                guard let action = self?.configuration?.onUnread else { return false }
                action()
                return true
            },
            UIAccessibilityCustomAction(name: hideTitle) { [weak self] _ in
                guard let action = self?.configuration?.onHide else { return false }
                action()
                return true
            },
            UIAccessibilityCustomAction(name: deleteTitle) { [weak self] _ in
                guard let self, let action = self.configuration?.onDelete else { return false }
                presentNativeChatDeleteConfirmation(from: self) {
                    action()
                }
                return true
            }
        ]
    }

    override func accessibilityActivate() -> Bool {
        guard let configuration else { return false }
        configuration.onOpen()
        return true
    }

}

private final class PaddingLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

private final class NativeChatAvatarView: UIView {
    private let tileContainer = UIView()
    private let tileViews = (0..<4).map { _ in UIImageView() }
    private var tilePaths = Array(repeating: "", count: 4)
    private var requestedPaths = Array(repeating: "", count: 4)
    private let moodLabel = UILabel()
    private let onlineDot = UIView()
    private let musicRing = CAShapeLayer()
    private let musicOrbit = UIView()
    private let musicNote = UIImageView()
    private var token = UUID()
    private var listening = false
    private var sourceSignature = ""

    var hasVisibleImage: Bool {
        tileViews.contains { !$0.isHidden && $0.image != nil }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        tileContainer.clipsToBounds = true
        tileContainer.layer.cornerRadius = 25
        tileContainer.layer.cornerCurve = .continuous
        tileContainer.backgroundColor = UIColor.secondarySystemFill
        musicRing.fillColor = UIColor.clear.cgColor
        musicRing.strokeColor = UIColor(hex: 0x25D366).cgColor
        musicRing.lineWidth = 2
        musicRing.lineCap = .round
        musicRing.isHidden = true
        layer.addSublayer(musicRing)
        addSubview(tileContainer)
        tileViews.forEach {
            $0.contentMode = .scaleAspectFill
            $0.clipsToBounds = true
            $0.backgroundColor = UIColor.tertiarySystemFill
            tileContainer.addSubview($0)
        }
        moodLabel.font = .systemFont(ofSize: 9)
        moodLabel.textAlignment = .center
        moodLabel.backgroundColor = .systemBackground
        moodLabel.layer.cornerRadius = 8.5
        moodLabel.clipsToBounds = true
        addSubview(moodLabel)
        onlineDot.backgroundColor = UIColor(hex: 0x4FD229)
        onlineDot.layer.cornerRadius = 7
        addSubview(onlineDot)
        musicOrbit.isUserInteractionEnabled = false
        musicOrbit.isHidden = true
        addSubview(musicOrbit)
        musicNote.image = UIImage(systemName: "music.note")
        musicNote.tintColor = .white
        musicNote.contentMode = .scaleAspectFit
        musicNote.backgroundColor = UIColor(hex: 0x25D366)
        musicNote.layer.cornerRadius = 7.5
        musicNote.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
        musicNote.layer.borderWidth = 0.8
        musicOrbit.addSubview(musicNote)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tileContainer.frame = bounds
        tileContainer.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        let gap: CGFloat = 1.2
        let visibleCount = tileViews.filter { !$0.isHidden }.count
        if visibleCount <= 1 {
            tileViews[0].frame = bounds
        } else if visibleCount == 2 {
            tileViews[0].frame = CGRect(x: 0, y: 0, width: (bounds.width - gap) / 2, height: bounds.height)
            tileViews[1].frame = CGRect(x: tileViews[0].frame.maxX + gap, y: 0,
                                        width: (bounds.width - gap) / 2, height: bounds.height)
        } else if visibleCount == 3 {
            let largeWidth = (bounds.width - gap) * 0.64
            let smallWidth = bounds.width - gap - largeWidth
            let smallHeight = (bounds.height - gap) / 2
            tileViews[0].frame = CGRect(x: 0, y: 0,
                                        width: largeWidth, height: bounds.height)
            tileViews[1].frame = CGRect(x: largeWidth + gap, y: 0,
                                        width: smallWidth, height: smallHeight)
            tileViews[2].frame = CGRect(x: largeWidth + gap, y: smallHeight + gap,
                                        width: smallWidth, height: smallHeight)
        } else {
            let halfW = (bounds.width - gap) / 2
            let halfH = (bounds.height - gap) / 2
            tileViews[0].frame = CGRect(x: 0, y: 0, width: halfW, height: halfH)
            tileViews[1].frame = CGRect(x: halfW + gap, y: 0, width: halfW, height: halfH)
            tileViews[2].frame = CGRect(x: 0, y: halfH + gap, width: halfW, height: halfH)
            tileViews[3].frame = CGRect(x: halfW + gap, y: halfH + gap, width: halfW, height: halfH)
        }
        moodLabel.frame = CGRect(x: bounds.width - 16, y: bounds.height - 16, width: 17, height: 17)
        onlineDot.frame = CGRect(x: bounds.width - 14, y: bounds.height - 14, width: 14, height: 14)
        let ringRect = bounds.insetBy(dx: -2.2, dy: -2.2)
        musicRing.frame = bounds
        musicRing.path = UIBezierPath(ovalIn: ringRect).cgPath
        musicRing.lineDashPattern = [
            NSNumber(value: Double(max(7, bounds.width * 0.18))),
            NSNumber(value: Double(max(5, bounds.width * 0.11)))
        ]
        musicOrbit.frame = bounds
        musicNote.frame = CGRect(
            x: (bounds.width - 15) / 2,
            y: -7,
            width: 15,
            height: 15
        )
    }

    func invalidate() {
        token = UUID()
        sourceSignature = ""
        requestedPaths = Array(repeating: "", count: 4)
        stopMusicOrbit()
    }

    func configure(paths: [String],
                   chatId: String,
                   memberIds: [String],
                   group: Bool,
                   online: Bool,
                   listening: Bool,
                   mood: String) {
        let shown = group ? Array(paths.prefix(4)) : Array(paths.prefix(1))
        let nextSourceSignature = [
            shown.joined(separator: "\u{1F}"),
            chatId,
            memberIds.prefix(4).joined(separator: "\u{1F}"),
            group ? "1" : "0"
        ].joined(separator: "\u{1E}")
        let sourceChanged = nextSourceSignature != sourceSignature
        if sourceChanged {
            sourceSignature = nextSourceSignature
            token = UUID()
            apply(paths: shown)
        }
        let requestToken = token
        if sourceChanged,
           group,
           !chatId.hasPrefix("stress-chat-"),
           shown.filter({ !$0.isEmpty }).count < max(1, min(4, memberIds.count)) {
            NativeGroupAvatarCache.shared.paths(chatId: chatId, memberIds: memberIds) { [weak self] resolved in
                guard let self, self.token == requestToken else { return }
                self.apply(paths: Array(resolved.prefix(4)))
                self.setNeedsLayout()
            }
        }
        onlineDot.isHidden = !online
        moodLabel.isHidden = online || mood.isEmpty
        moodLabel.text = mood
        self.listening = listening
        musicRing.isHidden = !listening
        musicOrbit.isHidden = !listening
        if listening {
            startMusicOrbit()
        } else {
            stopMusicOrbit()
        }
        setNeedsLayout()
    }

    private func startMusicOrbit() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            musicOrbit.layer.removeAnimation(forKey: "music-orbit")
            musicOrbit.transform = .identity
            return
        }
        guard musicOrbit.layer.animation(forKey: "music-orbit") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 3.4
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        musicOrbit.layer.add(spin, forKey: "music-orbit")
    }

    private func stopMusicOrbit() {
        musicOrbit.layer.removeAnimation(forKey: "music-orbit")
        musicOrbit.transform = .identity
    }

    private func apply(paths: [String]) {
        let requestToken = token
        let shown = Array(paths.prefix(4))
        for (index, imageView) in tileViews.enumerated() {
            let path = index < shown.count ? shown[index] : ""
            let cacheKey = ImageCacheKey.stablePath(path)
            let visible = index < max(1, shown.count)
            let changed = tilePaths[index] != cacheKey || imageView.isHidden != !visible
            imageView.isHidden = !visible
            if changed || path.isEmpty {
                tilePaths[index] = cacheKey
                requestedPaths[index] = ""
                imageView.image = nil
                imageView.backgroundColor = UIColor.tertiarySystemFill
            }
            guard visible, !path.isEmpty else { continue }
            if tilePaths[index] == cacheKey,
               imageView.image != nil || requestedPaths[index] == cacheKey {
                continue
            }
            requestedPaths[index] = cacheKey
            load(path: path, cacheKey: cacheKey) { [weak self, weak imageView] image in
                guard let self, self.token == requestToken, let imageView else { return }
                if self.requestedPaths[index] == cacheKey {
                    self.requestedPaths[index] = ""
                }
                if let image {
                    ImageStore.shared.putAvatar(cacheKey + "#150", image)
                    ImageStore.shared.putAvatar(cacheKey, image)
                    if imageView.image == nil {
                        imageView.image = image
                    } else {
                        UIView.transition(with: imageView,
                                          duration: 0.12,
                                          options: [.transitionCrossDissolve,
                                                    .beginFromCurrentState,
                                                    .allowUserInteraction]) {
                            imageView.image = image
                        }
                    }
                }
            }
        }
    }

    private func load(path: String,
                      cacheKey: String,
                      completion: @escaping (UIImage?) -> Void) {
        let thumbnailKey = cacheKey + "#150"
        if let hit = ImageStore.shared.get(thumbnailKey)
            ?? ImageStore.shared.get(cacheKey)
            ?? ImageStore.shared.get(path + "#150")
            ?? ImageStore.shared.get(path) {
            completion(hit)
            return
        }
        Task {
            let diskData = await Task.detached(priority: .userInitiated) {
                ImageStore.shared.diskRead(cacheKey)
                    ?? ImageStore.shared.diskRead(path)
            }.value
            var data = diskData
            if let url = API.shared.assetURL(path) {
                let diskImage = data.flatMap {
                    RemoteImage.downsampled($0, maxSide: 150)
                }
                if diskImage == nil {
                    data = try? await API.shared.imageData(url)
                }
            }
            guard let data else {
                await MainActor.run { completion(nil) }
                return
            }
            let image = await Task.detached(priority: .userInitiated) {
                RemoteImage.downsampled(data, maxSide: 150) ?? UIImage(data: data)
            }.value
            if let image {
                ImageStore.shared.put(thumbnailKey, image)
                Task.detached(priority: .background) {
                    ImageStore.shared.diskWrite(cacheKey, data)
                }
            }
            await MainActor.run { completion(image) }
        }
    }
}

@MainActor
private final class NativeGroupAvatarCache {
    static let shared = NativeGroupAvatarCache()
    private var cached: [String: [String]] = [:]
    private var cacheOrder: [String] = []
    private var running: [String: Task<[String], Never>] = [:]

    func paths(chatId: String,
               memberIds: [String],
               completion: @escaping @MainActor ([String]) -> Void) {
        if let hit = cached[chatId] {
            completion(hit)
            return
        }
        if let task = running[chatId] {
            Task {
                let paths = await task.value
                completion(paths)
            }
            return
        }
        let ids = Array(memberIds.prefix(4))
        let task = Task { () -> [String] in
            guard let result = try? await API.shared.chatMembers(chatId: chatId) else {
                return ids.map { _ in "" }
            }
            let byId = Dictionary(uniqueKeysWithValues: result.members.map { ($0.id, $0) })
            let ordered = ids.count >= 4
                ? ids
                : Array(result.members.prefix(4)).map(\.id)
            return ordered.map { byId[$0]?.avatarPath ?? "" }
        }
        running[chatId] = task
        Task {
            let paths = await task.value
            cached[chatId] = paths
            cacheOrder.append(chatId)
            running[chatId] = nil
            if cacheOrder.count > 1_500 {
                let dropped = cacheOrder.prefix(300)
                cacheOrder.removeFirst(dropped.count)
                for id in dropped {
                    cached.removeValue(forKey: id)
                }
            }
            completion(paths)
        }
    }
}
