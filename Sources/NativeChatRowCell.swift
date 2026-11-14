import UIKit

struct NativeChatRowConfiguration {
    var title: String
    var titleColor: UIColor
    var preview: String
    var mentionPrefix: String
    var previewColor: UIColor
    var time: String
    var timeColor: UIColor
    var rowBackground: UIColor
    var dividerColor: UIColor
    var badgeRing: UIColor
    var avatarPaths: [String]
    var avatarIsGroup: Bool
    var showOnline: Bool
    var moodIcon: String
    var unread: Int
    var unreadMuted: Bool
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

final class NativeChatRowCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    private let foreground = UIView()
    private let avatarView = NativeChatAvatarView()
    private let titleLabel = UILabel()
    private let levelLabel = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
    private let memberLabel = PaddingLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
    private let previewLabel = UILabel()
    private let timeLabel = UILabel()
    private let unreadLabel = PaddingLabel(insets: .zero)
    private let divider = UIView()
    private let pinActions = UIStackView()
    private let leftActions = UIStackView()
    private var configuration: NativeChatRowConfiguration?
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private weak var frozenScroll: UIScrollView?

    private let rowLeading: CGFloat = 16
    private let avatarSize: CGFloat = 50
    private let avatarGap: CGFloat = 11
    private let rowTrailing: CGFloat = 16
    private let dividerLeading: CGFloat = 77
    private let actionWidth: CGFloat = 50
    private let actionGap: CGFloat = 10
    private let actionInset: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuration = nil
        foreground.transform = .identity
        offset = 0
        startOffset = 0
        frozenScroll?.isScrollEnabled = true
        frozenScroll = nil
        avatarView.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        foreground.frame = bounds
        avatarView.frame = CGRect(x: rowLeading, y: (bounds.height - avatarSize) / 2,
                                  width: avatarSize, height: avatarSize)
        let trailingWidth: CGFloat = 66
        let textX = rowLeading + avatarSize + avatarGap
        let textWidth = max(1, bounds.width - textX - rowTrailing - trailingWidth - 8)
        let titleHeight: CGFloat = 22
        titleLabel.frame = CGRect(x: 0, y: 0, width: textWidth, height: titleHeight)
        levelLabel.sizeToFit()
        memberLabel.sizeToFit()
        previewLabel.frame = CGRect(x: textX, y: bounds.midY + 4,
                                    width: textWidth, height: 19)
        titleLabel.frame.origin = CGPoint(x: textX, y: bounds.midY - titleHeight - 1)
        timeLabel.frame = CGRect(x: bounds.width - rowTrailing - trailingWidth,
                                 y: bounds.midY - 20,
                                 width: trailingWidth, height: 18)
        unreadLabel.sizeToFit()
        let unreadWidth = max(18, unreadLabel.bounds.width)
        unreadLabel.frame = CGRect(x: bounds.width - rowTrailing - unreadWidth,
                                   y: bounds.midY + 2,
                                   width: unreadWidth,
                                   height: 18)
        rebuildTitleRow()
        divider.frame = CGRect(x: dividerLeading, y: bounds.height - 0.5,
                               width: bounds.width - dividerLeading, height: 0.5)
        pinActions.frame = CGRect(x: actionInset, y: 0,
                                  width: actionWidth + actionInset * 2,
                                  height: bounds.height)
        leftActions.frame = CGRect(x: bounds.width - (actionWidth * 3 + actionGap * 2 + actionInset),
                                   y: 0,
                                   width: actionWidth * 3 + actionGap * 2 + actionInset,
                                   height: bounds.height)
    }

    func configure(_ configuration: NativeChatRowConfiguration) {
        self.configuration = configuration
        backgroundColor = configuration.rowBackground
        foreground.backgroundColor = configuration.rowBackground
        titleLabel.text = configuration.title
        titleLabel.textColor = configuration.titleColor
        previewLabel.text = configuration.preview
        previewLabel.textColor = configuration.previewColor
        timeLabel.text = configuration.time
        timeLabel.textColor = configuration.timeColor
        divider.backgroundColor = configuration.dividerColor
        unreadLabel.isHidden = configuration.unread <= 0
        if configuration.unread > 0 {
            if configuration.unreadMuted {
                unreadLabel.text = "●"
                unreadLabel.font = .systemFont(ofSize: 7, weight: .bold)
                unreadLabel.backgroundColor = configuration.timeColor
                unreadLabel.textColor = configuration.timeColor
                unreadLabel.layer.cornerRadius = 4
                unreadLabel.frame.size.width = 8
            } else {
                unreadLabel.text = configuration.unread > 99 ? "99+" : "\(configuration.unread)"
                unreadLabel.font = .systemFont(ofSize: 9.5, weight: .bold)
                unreadLabel.backgroundColor = .systemBlue
                unreadLabel.textColor = .white
                unreadLabel.layer.cornerRadius = 9
            }
            unreadLabel.layer.borderWidth = 1.5
            unreadLabel.layer.borderColor = configuration.badgeRing.cgColor
            unreadLabel.clipsToBounds = true
            unreadLabel.textAlignment = .center
        }

        levelLabel.isHidden = configuration.levelText.isEmpty
        levelLabel.text = configuration.levelText
        memberLabel.isHidden = configuration.memberText.isEmpty
        memberLabel.text = configuration.memberText
        memberLabel.backgroundColor = configuration.memberColor
        avatarView.configure(paths: configuration.avatarPaths,
                             group: configuration.avatarIsGroup,
                             online: configuration.showOnline,
                             mood: configuration.moodIcon)
        rebuildActions()
        setNeedsLayout()
    }

    private func setupViews() {
        backgroundConfiguration = .clear()
        contentView.clipsToBounds = true
        backgroundColor = .clear

        pinActions.axis = .horizontal
        pinActions.alignment = .center
        pinActions.spacing = 0
        pinActions.isHidden = true
        leftActions.axis = .horizontal
        leftActions.alignment = .center
        leftActions.spacing = actionGap
        leftActions.isHidden = true
        contentView.addSubview(pinActions)
        contentView.addSubview(leftActions)

        foreground.clipsToBounds = true
        contentView.addSubview(foreground)
        foreground.addSubview(avatarView)
        foreground.addSubview(titleLabel)
        foreground.addSubview(previewLabel)
        foreground.addSubview(timeLabel)
        foreground.addSubview(unreadLabel)
        foreground.addSubview(divider)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        previewLabel.font = .systemFont(ofSize: 15, weight: .regular)
        previewLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        timeLabel.textAlignment = .right
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.75
        unreadLabel.textAlignment = .center
        unreadLabel.font = .systemFont(ofSize: 9.5, weight: .bold)
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

    private func rebuildTitleRow() {
        layer.sublayers?.removeAll(where: { $0.name == "title-badges" })
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

    private func rebuildActions() {
        pinActions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        leftActions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let configuration else { return }

        let pinTitle = configuration.isPinned ? localized("取消置顶", "Unpin", "Открепить")
            : localized("置顶", "Pin", "Закрепить")
        pinActions.addArrangedSubview(makeAction(symbol: "pin.fill",
                                                 title: pinTitle,
                                                 background: UIColor(hex: 0x0A84FF)) { [weak self] in
            guard let self, let configuration = self.configuration else { return }
            configuration.onPin(!configuration.isPinned)
            self.closeActions()
        })
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pinActions.addArrangedSubview(spacer)

        leftActions.addArrangedSubview(makeAction(symbol: "envelope.badge.fill",
                                                  title: localized("标为未读", "Unread", "Непрочитано"),
                                                  background: UIColor(hex: 0x28986C)) { [weak self] in
            self?.configuration?.onUnread()
            self?.closeActions()
        })
        leftActions.addArrangedSubview(makeAction(symbol: "eye.slash.fill",
                                                  title: localized("不显示", "Hide", "Скрыть"),
                                                  background: UIColor(hex: 0x7B8087)) { [weak self] in
            self?.configuration?.onHide()
            self?.closeActions()
        })
        leftActions.addArrangedSubview(makeAction(symbol: "trash.fill",
                                                  title: localized("删除", "Delete", "Удалить"),
                                                  background: .systemRed) { [weak self] in
            self?.configuration?.onDelete()
            self?.closeActions()
        })
    }

    private func makeAction(symbol: String,
                            title: String,
                            background: UIColor,
                            action: @escaping () -> Void) -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        config.baseBackgroundColor = background
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        button.configuration = config
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: actionWidth),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -7),
            button.widthAnchor.constraint(equalToConstant: actionWidth),
            button.heightAnchor.constraint(equalToConstant: actionWidth),
            label.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 1),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        foreground.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        foreground.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard offset == 0 else {
            closeActions()
            return
        }
        let point = gesture.location(in: foreground)
        if point.x <= rowLeading + avatarSize + 10, let onAvatar = configuration?.onAvatar {
            onAvatar()
        } else {
            configuration?.onOpen()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let configuration else { return }
        let translation = gesture.translation(in: foreground).x
        let velocity = gesture.velocity(in: foreground).x
        switch gesture.state {
        case .began:
            startOffset = offset
            frozenScroll = enclosingScrollView()
            frozenScroll?.isScrollEnabled = false
            NotificationCenter.default.post(name: .chrisRowSwipe, object: nil)
        case .changed:
            let raw = startOffset + translation
            offset = resisted(raw)
            foreground.transform = CGAffineTransform(translationX: offset, y: 0)
            pinActions.isHidden = offset <= 0
            leftActions.isHidden = offset >= 0
        case .ended, .cancelled, .failed:
            frozenScroll?.isScrollEnabled = true
            frozenScroll = nil
            let projected = offset + velocity * 0.14
            if projected > actionInset + actionWidth * 0.34 {
                open(offset: actionInset + actionWidth, animated: true)
            } else if projected < -(actionInset + actionWidth * 3 + actionGap * 2) * 0.34 {
                open(offset: -(actionInset + actionWidth * 3 + actionGap * 2), animated: true)
            } else {
                closeActions()
            }
            if -offset > bounds.width * 0.72 {
                configuration.onDelete()
            } else if offset > bounds.width * 0.72 {
                configuration.onPin(!configuration.isPinned)
            }
        default:
            break
        }
    }

    private func resisted(_ raw: CGFloat) -> CGFloat {
        let limit = max(90, bounds.width * 0.24)
        if raw > 0, raw > actionInset + actionWidth {
            let extra = raw - (actionInset + actionWidth)
            return actionInset + actionWidth + limit * extra / (extra + 90)
        }
        let leftBase = actionInset + actionWidth * 3 + actionGap * 2
        if raw < 0, -raw > leftBase {
            let extra = -raw - leftBase
            return -(leftBase + limit * extra / (extra + 90))
        }
        return raw
    }

    private func open(offset target: CGFloat, animated: Bool) {
        offset = target
        pinActions.isHidden = target <= 0
        leftActions.isHidden = target >= 0
        let updates = { self.foreground.transform = CGAffineTransform(translationX: target, y: 0) }
        if animated {
            UIView.animate(withDuration: 0.26,
                           delay: 0,
                           usingSpringWithDamping: 0.86,
                           initialSpringVelocity: 0.5,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: updates)
        } else {
            updates()
        }
    }

    private func closeActions() {
        open(offset: 0, animated: true)
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }

    private func localized(_ zh: String, _ en: String, _ ru: String) -> String {
        if Lang.isRussian { return ru }
        if Lang.isEnglish { return en }
        return zh
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: foreground)
        return abs(velocity.x) >= 18 && abs(velocity.x) >= abs(velocity.y) * 1.12
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
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
    private let tileViews = (0..<4).map { _ in UIImageView() }
    private let moodLabel = UILabel()
    private let onlineDot = UIView()
    private var token = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 25
        layer.cornerCurve = .continuous
        backgroundColor = UIColor.secondarySystemFill
        tileViews.forEach {
            $0.contentMode = .scaleAspectFill
            $0.clipsToBounds = true
            $0.backgroundColor = UIColor.tertiarySystemFill
            addSubview($0)
        }
        moodLabel.font = .systemFont(ofSize: 9)
        moodLabel.textAlignment = .center
        moodLabel.backgroundColor = .systemBackground
        moodLabel.layer.cornerRadius = 8.5
        moodLabel.clipsToBounds = true
        addSubview(moodLabel)
        onlineDot.backgroundColor = UIColor(hex: 0x4FD229)
        onlineDot.layer.cornerRadius = 7
        onlineDot.layer.borderColor = UIColor.systemBackground.cgColor
        onlineDot.layer.borderWidth = 1.5
        addSubview(onlineDot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 1.2
        let visibleCount = tileViews.filter { !$0.isHidden }.count
        if visibleCount <= 1 {
            tileViews[0].frame = bounds
        } else if visibleCount == 2 {
            tileViews[0].frame = CGRect(x: 0, y: 0, width: (bounds.width - gap) / 2, height: bounds.height)
            tileViews[1].frame = CGRect(x: tileViews[0].frame.maxX + gap, y: 0,
                                        width: (bounds.width - gap) / 2, height: bounds.height)
        } else {
            let halfW = (bounds.width - gap) / 2
            let halfH = (bounds.height - gap) / 2
            tileViews[0].frame = CGRect(x: 0, y: 0, width: halfW, height: halfH)
            tileViews[1].frame = CGRect(x: halfW + gap, y: 0, width: halfW, height: halfH)
            tileViews[2].frame = CGRect(x: 0, y: halfH + gap, width: halfW, height: halfH)
            tileViews[3].frame = CGRect(x: halfW + gap, y: halfH + gap, width: halfW, height: halfH)
        }
        moodLabel.frame = CGRect(x: bounds.width - 16, y: bounds.height - 16, width: 17, height: 17)
        onlineDot.frame = CGRect(x: bounds.width - 16, y: bounds.height - 16, width: 14, height: 14)
    }

    func reset() {
        token = UUID()
        tileViews.forEach {
            $0.image = nil
            $0.isHidden = false
        }
        moodLabel.isHidden = true
        onlineDot.isHidden = true
    }

    func configure(paths: [String], group: Bool, online: Bool, mood: String) {
        token = UUID()
        let requestToken = token
        let shown = group ? Array(paths.prefix(4)) : Array(paths.prefix(1))
        for (index, imageView) in tileViews.enumerated() {
            imageView.isHidden = index >= max(1, shown.count)
            imageView.image = nil
            imageView.backgroundColor = UIColor.tertiarySystemFill
            let path = index < shown.count ? shown[index] : ""
            guard !path.isEmpty else { continue }
            load(path: path) { [weak self, weak imageView] image in
                guard let self, self.token == requestToken, let imageView else { return }
                imageView.image = image
            }
        }
        onlineDot.isHidden = !online
        onlineDot.layer.borderColor = UIColor.secondarySystemBackground.cgColor
        moodLabel.isHidden = online || mood.isEmpty
        moodLabel.text = mood
        setNeedsLayout()
    }

    private func load(path: String, completion: @escaping (UIImage?) -> Void) {
        if let hit = ImageStore.shared.get(path + "#150") ?? ImageStore.shared.get(path) {
            completion(hit)
            return
        }
        Task {
            let diskData = await Task.detached(priority: .userInitiated) {
                ImageStore.shared.diskRead(path)
            }.value
            var data = diskData
            if data == nil, let url = API.shared.assetURL(path) {
                data = try? await API.shared.imageData(url)
            }
            guard let data else {
                await MainActor.run { completion(nil) }
                return
            }
            let image = await Task.detached(priority: .userInitiated) {
                RemoteImage.downsampled(data, maxSide: 150)
            }.value
            if let image {
                ImageStore.shared.put(path + "#150", image)
                Task.detached(priority: .background) {
                    ImageStore.shared.diskWrite(path, data)
                }
            }
            await MainActor.run { completion(image) }
        }
    }
}
