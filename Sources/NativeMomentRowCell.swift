import SwiftUI
import UIKit
import AVFoundation

struct NativeMomentActions {
    let openComments: (Moment) -> Void
    let openImage: (Moment, Int) -> Void
    let openVideo: (URL) -> Void
    let openAvatar: (User) -> Void
    let openLikes: ([MomentLike]) -> Void
    let avatarPathFor: (String) -> String
    let isFriend: (String) -> Bool
    let like: (Moment) -> Void
    let more: (Moment) -> Void
}

private final class NativeMomentImageStore {
    static let shared = NativeMomentImageStore()

    func cached(path: String, maxSide: CGFloat) -> UIImage? {
        let key = cacheKey(path, maxSide: maxSide)
        if let memory = ImageStore.shared.get(key) ?? ImageStore.shared.getBestAvailable(path) {
            return memory
        }
        guard let data = ImageStore.shared.diskRead(key),
              let image = UIImage(data: data) else { return nil }
        ImageStore.shared.put(key, image)
        return image
    }

    func load(path: String, maxSide: CGFloat,
              completion: @escaping (UIImage?) -> Void) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            completion(nil)
            return
        }
        if let image = cached(path: normalized, maxSide: maxSide) {
            completion(image)
            return
        }
        guard let url = API.shared.assetURL(normalized) else {
            completion(nil)
            return
        }
        let key = cacheKey(normalized, maxSide: maxSide)
        Task.detached(priority: .utility) {
            guard let data = try? await API.shared.assetData(url),
                  let full = UIImage(data: data) else {
                await MainActor.run { completion(nil) }
                return
            }
            let image = full.momentResized(maxSide: maxSide)
            ImageStore.shared.diskWrite(key, data)
            if let image {
                ImageStore.shared.put(key, image)
            }
            await MainActor.run { completion(image) }
        }
    }

    private func cacheKey(_ path: String, maxSide: CGFloat) -> String {
        ImageCacheKey.stablePath(path) + "#moment-\(Int(maxSide.rounded()))"
    }
}

private extension UIImage {
    func momentResized(maxSide: CGFloat) -> UIImage? {
        guard max(size.width, size.height) > maxSide else { return self }
        let ratio = maxSide / max(size.width, size.height)
        let target = CGSize(width: max(1, size.width * ratio),
                            height: max(1, size.height * ratio))
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private final class NativeMomentImageView: UIImageView {
    private var requestID = UUID()
    private let placeholder = UIImageView()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(C.searchBg)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        isUserInteractionEnabled = false
        placeholder.tintColor = UIColor(C.subLabel).withAlphaComponent(0.62)
        placeholder.contentMode = .scaleAspectFit
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 22),
            placeholder.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(path: String, maxSide: CGFloat, symbol: String? = nil) {
        requestID = UUID()
        let current = requestID
        image = nil
        placeholder.image = symbol.flatMap { UIImage(systemName: $0) }
        placeholder.isHidden = image != nil
        NativeMomentImageStore.shared.load(path: path, maxSide: maxSide) { [weak self] loaded in
            guard let self, self.requestID == current else { return }
            self.image = loaded
            self.placeholder.isHidden = loaded != nil
        }
    }

    func reset() {
        requestID = UUID()
        image = nil
        placeholder.image = nil
        placeholder.isHidden = false
    }
}

private enum NativeMomentTextLayout {
    static func normalized(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            ) }
        var out: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun > 1 { continue }
            } else {
                blankRun = 0
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum NativeMomentTimelineMetrics {
    static let horizontalInset: CGFloat = 22
    static let trailingInset: CGFloat = 20
    static let avatar: CGFloat = 43
    static let avatarGap: CGFloat = 11
    static let contentInset = horizontalInset + avatar + avatarGap
}

private final class NativeMomentLikeParticleBurst: UIView {
    func burst() {
        layer.removeAllAnimations()
        subviews.forEach { $0.removeFromSuperview() }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let count = reduceMotion ? 6 : 14
        let origin = CGPoint(x: bounds.maxX - 92, y: bounds.midY + 2)
        for index in 0..<count {
            let particle = UIView(frame: CGRect(
                x: origin.x,
                y: origin.y,
                width: index.isMultiple(of: 2) ? 4 : 3,
                height: index.isMultiple(of: 2) ? 4 : 3
            ))
            particle.backgroundColor = UIColor(hex: 0xFF3B4D)
            particle.layer.cornerRadius = particle.bounds.width / 2
            addSubview(particle)
            let angle = Double(index) / Double(count) * Double.pi * 2
            let distance = reduceMotion ? 13.0 : 24.0
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance - 8
            UIView.animate(
                withDuration: reduceMotion ? 0.22 : 0.52,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                particle.center = CGPoint(
                    x: origin.x + dx,
                    y: origin.y + dy
                )
                particle.alpha = 0
                particle.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
            } completion: { _ in
                particle.removeFromSuperview()
            }
        }
    }
}

private final class NativeMomentAvatarView: UIImageView {
    private var requestID = UUID()

    init(size: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        layer.cornerRadius = size / 2
        clipsToBounds = true
        contentMode = .scaleAspectFill
        backgroundColor = UIColor(C.searchBg)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(path: String, size: CGFloat) {
        requestID = UUID()
        let current = requestID
        let key = ImageCacheKey.avatar(path)
        if let cached = ImageStore.shared.get(key) ?? ImageStore.shared.getBestAvailable(path) {
            image = cached
            return
        }
        image = nil
        NativeMomentImageStore.shared.load(path: path, maxSide: max(80, size * 3)) {
            [weak self] loaded in
            guard let self, self.requestID == current, let loaded else { return }
            self.image = loaded
            ImageStore.shared.putAvatar(key, loaded)
        }
    }

    func setPlaceholder(_ text: String) {
        requestID = UUID()
        image = NativeMomentAvatarView.letterImage(text)
    }

    private static func letterImage(_ text: String) -> UIImage {
        let side: CGFloat = 72
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            UIColor(C.searchBg).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            let value = String(text.prefix(1)) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: pfUIFont(27, .semibold),
                .foregroundColor: UIColor(C.subLabel)
            ]
            let size = value.size(withAttributes: attrs)
            value.draw(at: CGPoint(x: (side - size.width) / 2,
                                   y: (side - size.height) / 2),
                       withAttributes: attrs)
        }
    }
}

private final class NativeMomentMediaControl: UIControl {
    let imageView = NativeMomentImageView()
    private let videoSurface = UIView()
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var playbackActive = false
    private let playCircle = UIView()
    private let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
    private let durationLabel = UILabel()
    private let pinnedLabel = UILabel()
    private let pinnedIcon = UIImageView(image: UIImage(systemName: "pin.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        videoSurface.translatesAutoresizingMaskIntoConstraints = false
        videoSurface.isUserInteractionEnabled = false
        addSubview(videoSurface)
        NSLayoutConstraint.activate([
            videoSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoSurface.topAnchor.constraint(equalTo: topAnchor),
            videoSurface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        playCircle.translatesAutoresizingMaskIntoConstraints = false
        playCircle.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        playCircle.layer.cornerRadius = 27
        playCircle.isUserInteractionEnabled = false
        addSubview(playCircle)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.tintColor = .white
        playIcon.contentMode = .scaleAspectFit
        playCircle.addSubview(playIcon)
        NSLayoutConstraint.activate([
            playCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            playCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            playCircle.widthAnchor.constraint(equalToConstant: 54),
            playCircle.heightAnchor.constraint(equalToConstant: 54),
            playIcon.centerXAnchor.constraint(equalTo: playCircle.centerXAnchor, constant: 1.5),
            playIcon.centerYAnchor.constraint(equalTo: playCircle.centerYAnchor),
            playIcon.widthAnchor.constraint(equalToConstant: 21),
            playIcon.heightAnchor.constraint(equalToConstant: 21)
        ])

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = pfUIFont(11.5, .medium)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        durationLabel.layer.cornerRadius = 9
        durationLabel.clipsToBounds = true
        durationLabel.textAlignment = .center
        durationLabel.isHidden = true
        addSubview(durationLabel)
        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            durationLabel.heightAnchor.constraint(equalToConstant: 20),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        pinnedLabel.translatesAutoresizingMaskIntoConstraints = false
        pinnedLabel.font = pfUIFont(10.5, .semibold)
        pinnedLabel.textColor = .white
        pinnedLabel.text = Tr("置顶")
        pinnedLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        pinnedLabel.layer.cornerRadius = 10
        pinnedLabel.clipsToBounds = true
        pinnedLabel.textAlignment = .center
        pinnedLabel.isHidden = true
        addSubview(pinnedLabel)
        pinnedIcon.translatesAutoresizingMaskIntoConstraints = false
        pinnedIcon.tintColor = .white
        pinnedIcon.contentMode = .scaleAspectFit
        addSubview(pinnedIcon)
        NSLayoutConstraint.activate([
            pinnedIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            pinnedIcon.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            pinnedIcon.widthAnchor.constraint(equalToConstant: 9),
            pinnedIcon.heightAnchor.constraint(equalToConstant: 9),
            pinnedLabel.leadingAnchor.constraint(equalTo: pinnedIcon.trailingAnchor, constant: 4),
            pinnedLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            pinnedLabel.heightAnchor.constraint(equalToConstant: 22),
            pinnedLabel.widthAnchor.constraint(equalToConstant: 48)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureImage(path: String, radius: CGFloat) {
        imageView.set(path: path, maxSide: 1440, symbol: "photo")
        clearVideo()
        playCircle.isHidden = true
        pinnedLabel.isHidden = true
        pinnedIcon.isHidden = true
        durationLabel.isHidden = true
        layer.cornerRadius = radius
        layer.borderWidth = 0.6
        layer.borderColor = UIColor(C.label).withAlphaComponent(0.075).cgColor
    }

    func configureVideo(cover: String,
                        videoPath: String,
                        seconds: Int,
                        pinned: Bool,
                        radius: CGFloat) {
        imageView.set(path: cover, maxSide: 1440, symbol: "video")
        clearVideo()
        if let url = API.shared.assetURL(videoPath) {
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .pause
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = videoSurface.bounds
            videoSurface.layer.addSublayer(layer)
            self.player = player
            playerLayer = layer
            if playbackActive { player.playImmediately(atRate: 1) }
        }
        playCircle.isHidden = false
        pinnedLabel.isHidden = !pinned
        pinnedIcon.isHidden = !pinned
        durationLabel.isHidden = seconds <= 0
        durationLabel.text = String(format: "  %02d:%02d  ",
                                    max(0, seconds) / 60, max(0, seconds) % 60)
        layer.cornerRadius = radius
        layer.borderWidth = 0.6
        layer.borderColor = UIColor(C.label).withAlphaComponent(0.075).cgColor
    }

    func setPlaybackActive(_ active: Bool) {
        playbackActive = active
        guard let player else { return }
        if active {
            player.playImmediately(atRate: 1)
        } else {
            player.pause()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = videoSurface.bounds
    }

    private func clearVideo() {
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
}

final class NativeMomentRowCell: UITableViewCell {
    static let reuseIdentifier = "NativeMomentRowCell"

    private let rootStack = UIStackView()
    private let stressView = UIView()
    private let stressLabel = UILabel()
    private let dayView = UIView()
    private let dayLabel = UILabel()
    private let cardHost = UIView()
    private let card = UIView()
    private let cardStack = UIStackView()

    private let promotionView = UIView()
    private let promotionLabel = UILabel()
    private let sponsorLabel = UILabel()
    private let adLabel = UILabel()

    private let headerView = UIView()
    private let avatar = NativeMomentAvatarView(
        size: NativeMomentTimelineMetrics.avatar
    )
    private let detailStack = UIStackView()
    private let nameRow = UIStackView()
    private let nameLabel = UILabel()
    private let pinnedIcon = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let timeLabel = UILabel()
    private let moreButton = UIButton(type: .system)

    private let bodyView = UITextView()
    private let mediaCanvas = UIView()
    private var mediaControls: [NativeMomentMediaControl] = []
    private var mediaWidthConstraint: NSLayoutConstraint!
    private var mediaHeightConstraint: NSLayoutConstraint!

    private let actionHost = UIView()
    private let actionPill = UIView()
    private let actionStack = UIStackView()
    private let likeButton = UIButton(type: .system)
    private let commentButton = UIButton(type: .system)
    private let actionMoreButton = UIButton(type: .system)
    private let likeBurst = NativeMomentLikeParticleBurst()

    private let socialView = UIView()
    private let socialStack = UIStackView()
    private let likesButton = UIControl()
    private let likeAvatars = UIView()
    private let likeSummaryLabel = UILabel()
    private let likesChevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    private let footerView = UIView()
    private let footerSpinner = UIActivityIndicatorView(style: .medium)
    private let footerLabel = UILabel()

    private var moment: Moment?
    private var actions: NativeMomentActions?
    private var optimisticLiked: Bool?
    private var topInset: NSLayoutConstraint!
    private var likeAvatarsWidth: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = UIColor(C.pageBg)
        contentView.backgroundColor = UIColor(C.pageBg)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        moment = nil
        actions = nil
        optimisticLiked = nil
        bodyView.attributedText = nil
        mediaCanvas.subviews.forEach { $0.removeFromSuperview() }
        mediaControls.forEach { $0.setPlaybackActive(false) }
        mediaControls.removeAll(keepingCapacity: true)
        socialStack.arrangedSubviews.forEach {
            socialStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        likeAvatars.subviews.forEach { $0.removeFromSuperview() }
    }

    static func prefetch(_ moment: Moment) {
        let avatar = moment.author?.avatarPath ?? ""
        if !avatar.isEmpty {
            NativeMomentImageStore.shared.load(path: avatar, maxSide: 120) { _ in }
        }
        for path in moment.images ?? [] {
            NativeMomentImageStore.shared.load(path: path, maxSide: 1440) { _ in }
        }
        if let cover = moment.videoCover, !cover.isEmpty {
            NativeMomentImageStore.shared.load(path: cover, maxSide: 1440) { _ in }
        }
    }

    func configure(item: NativeMomentFeedItem,
                   actions: NativeMomentActions,
                   stressText: String?,
                   footerText: String?,
                   footerWaiting: Bool) {
        moment = item.moment
        self.actions = actions
        optimisticLiked = nil
        backgroundColor = UIColor(C.pageBg)
        contentView.backgroundColor = UIColor(C.pageBg)
        topInset.constant = item.isFirst ? 18 : 0

        stressView.isHidden = stressText == nil
        stressLabel.text = stressText
        dayView.isHidden = !item.showsDayHeader
        dayLabel.text = item.dayText

        configurePromotion(item.moment.promotion)
        configureHeader(item.moment, actions: actions)
        configureBody(item.moment, actions: actions)
        configureMedia(item.moment, actions: actions)
        configureActions(item.moment, actions: actions)
        configureSocial(item.moment, actions: actions)
        configureFooter(text: footerText,
                        waiting: footerWaiting,
                        isLast: item.isLast)
    }

    func setPlaybackActive(_ active: Bool) {
        mediaControls.forEach { $0.setPlaybackActive(active) }
    }

    private func configureHierarchy() {
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        topInset = rootStack.topAnchor.constraint(equalTo: contentView.topAnchor)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topInset,
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        configureStressView()
        configureDayView()
        configureCard()
        configureFooter()

        rootStack.addArrangedSubview(stressView)
        rootStack.addArrangedSubview(dayView)
        rootStack.addArrangedSubview(cardHost)
        rootStack.addArrangedSubview(footerView)
    }

    private func configureStressView() {
        stressView.backgroundColor = UIColor(C.pageBg)
        stressLabel.translatesAutoresizingMaskIntoConstraints = false
        stressLabel.font = pfUIFont(12, .medium)
        stressLabel.textColor = UIColor(C.subLabel)
        stressView.addSubview(stressLabel)
        NSLayoutConstraint.activate([
            stressView.heightAnchor.constraint(equalToConstant: 28),
            stressLabel.leadingAnchor.constraint(equalTo: stressView.leadingAnchor,
                                                  constant: L.momentPadH),
            stressLabel.centerYAnchor.constraint(equalTo: stressView.centerYAnchor)
        ])
    }

    private func configureDayView() {
        dayView.backgroundColor = UIColor(C.pageBg)
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.font = pfUIFont(13)
        dayLabel.textColor = UIColor(C.subLabel)
        dayView.addSubview(dayLabel)
        NSLayoutConstraint.activate([
            dayLabel.leadingAnchor.constraint(equalTo: dayView.leadingAnchor,
                                              constant: L.momentPadH),
            dayLabel.trailingAnchor.constraint(lessThanOrEqualTo: dayView.trailingAnchor,
                                               constant: -L.momentPadH),
            dayLabel.topAnchor.constraint(equalTo: dayView.topAnchor, constant: 14),
            dayLabel.bottomAnchor.constraint(equalTo: dayView.bottomAnchor, constant: -2)
        ])
    }

    private func configureCard() {
        cardHost.backgroundColor = UIColor(C.pageBg)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(C.pageBg)
        card.layer.cornerRadius = 0
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0
        card.layer.borderColor = UIColor.clear.cgColor
        cardHost.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor)
        ])

        cardStack.axis = .vertical
        cardStack.alignment = .fill
        cardStack.spacing = 0
        cardStack.isLayoutMarginsRelativeArrangement = true
        cardStack.layoutMargins = UIEdgeInsets(
            top: 14,
            left: NativeMomentTimelineMetrics.horizontalInset,
            bottom: 14,
            right: NativeMomentTimelineMetrics.trailingInset
        )
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        likeBurst.translatesAutoresizingMaskIntoConstraints = false
        likeBurst.isUserInteractionEnabled = false
        card.addSubview(likeBurst)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            likeBurst.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            likeBurst.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            likeBurst.topAnchor.constraint(equalTo: card.topAnchor),
            likeBurst.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        configurePromotionView()
        configureHeaderView()
        configureBodyView()
        configureMediaCanvas()
        configureActionHost()
        configureSocialView()
        cardStack.addArrangedSubview(promotionView)
        cardStack.addArrangedSubview(headerView)
        cardStack.setCustomSpacing(12, after: promotionView)
    }

    private func configurePromotionView() {
        promotionView.backgroundColor = UIColor(Color.dyn(0xFBF7F1, 0x211C16))
        promotionView.layer.cornerRadius = 11
        promotionView.layer.cornerCurve = .continuous
        promotionView.layer.borderWidth = 0.6
        promotionView.layer.borderColor = UIColor(hex: 0xA66B28).withAlphaComponent(0.12).cgColor
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        promotionLabel.font = pfUIFont(9.5, .bold)
        promotionLabel.textColor = UIColor(hex: 0xA66B28)
        promotionLabel.backgroundColor = UIColor(hex: 0xF4E7D5)
        promotionLabel.textAlignment = .center
        promotionLabel.layer.cornerRadius = 10
        promotionLabel.clipsToBounds = true
        sponsorLabel.font = pfUIFont(11.5, .medium)
        sponsorLabel.textColor = UIColor(C.subLabel)
        sponsorLabel.lineBreakMode = .byTruncatingTail
        adLabel.font = pfUIFont(9.5, .medium)
        adLabel.textColor = UIColor(C.subLabel).withAlphaComponent(0.7)
        adLabel.text = Tr("广告")
        stack.addArrangedSubview(promotionLabel)
        stack.addArrangedSubview(sponsorLabel)
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(adLabel)
        promotionView.addSubview(stack)
        NSLayoutConstraint.activate([
            promotionView.heightAnchor.constraint(equalToConstant: 34),
            promotionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            promotionLabel.heightAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: promotionView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: promotionView.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: promotionView.centerYAnchor)
        ])
    }

    private func configureHeaderView() {
        avatar.contentMode = .scaleAspectFill
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                           action: #selector(openAuthor)))

        nameLabel.font = momentUIFont(16.5, .semibold, relativeTo: .headline)
        nameLabel.textColor = UIColor(C.link)
        nameLabel.lineBreakMode = .byTruncatingTail
        pinnedIcon.tintColor = UIColor(C.subLabel)
        pinnedIcon.contentMode = .scaleAspectFit
        pinnedIcon.translatesAutoresizingMaskIntoConstraints = false
        pinnedIcon.widthAnchor.constraint(equalToConstant: 10).isActive = true
        pinnedIcon.heightAnchor.constraint(equalToConstant: 10).isActive = true

        nameRow.arrangedSubviews.forEach {
            nameRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(pinnedIcon)
        nameRow.addArrangedSubview(UIView())
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 5
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.isUserInteractionEnabled = true
        nameRow.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                            action: #selector(openAuthor)))
        timeLabel.font = momentUIFont(12.5, .regular, relativeTo: .caption1)
        timeLabel.textColor = UIColor(C.subLabel)
        timeLabel.lineBreakMode = .byTruncatingTail

        moreButton.tintColor = UIColor(C.subLabel)
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
            forImageIn: .normal
        )
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let nameLine = UIView()
        nameLine.addSubview(nameRow)
        nameLine.addSubview(moreButton)
        NSLayoutConstraint.activate([
            nameLine.heightAnchor.constraint(equalToConstant: 24),
            nameRow.leadingAnchor.constraint(equalTo: nameLine.leadingAnchor),
            nameRow.trailingAnchor.constraint(
                lessThanOrEqualTo: moreButton.leadingAnchor,
                constant: -4
            ),
            nameRow.topAnchor.constraint(equalTo: nameLine.topAnchor),
            nameRow.bottomAnchor.constraint(equalTo: nameLine.bottomAnchor),
            moreButton.trailingAnchor.constraint(equalTo: nameLine.trailingAnchor),
            moreButton.centerYAnchor.constraint(equalTo: nameLine.centerYAnchor)
        ])

        detailStack.axis = .vertical
        detailStack.alignment = .fill
        detailStack.spacing = 0
        detailStack.addArrangedSubview(nameLine)
        detailStack.addArrangedSubview(bodyView)
        detailStack.addArrangedSubview(mediaCanvas)
        detailStack.addArrangedSubview(timeLabel)
        detailStack.addArrangedSubview(actionHost)
        detailStack.addArrangedSubview(socialView)
        detailStack.setCustomSpacing(4, after: nameLine)
        detailStack.setCustomSpacing(8, after: bodyView)
        detailStack.setCustomSpacing(8, after: mediaCanvas)
        detailStack.setCustomSpacing(10, after: timeLabel)
        detailStack.setCustomSpacing(10, after: actionHost)

        let row = UIStackView(arrangedSubviews: [avatar, detailStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = NativeMomentTimelineMetrics.avatarGap
        row.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            row.topAnchor.constraint(equalTo: headerView.topAnchor),
            row.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
        ])
    }

    private func configureBodyView() {
        bodyView.backgroundColor = .clear
        bodyView.isEditable = false
        bodyView.isScrollEnabled = false
        bodyView.isSelectable = true
        bodyView.textContainerInset = .zero
        bodyView.textContainer.lineFragmentPadding = 0
        bodyView.adjustsFontForContentSizeCategory = true
        bodyView.delegate = self
        bodyView.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                              action: #selector(openComments)))
    }

    private func configureMediaCanvas() {
        mediaCanvas.translatesAutoresizingMaskIntoConstraints = false
        mediaCanvas.clipsToBounds = false
        mediaWidthConstraint = mediaCanvas.widthAnchor.constraint(equalToConstant: 1)
        mediaHeightConstraint = mediaCanvas.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([mediaWidthConstraint, mediaHeightConstraint])
    }

    private func configureActionHost() {
        actionHost.backgroundColor = .clear
        actionPill.backgroundColor = UIColor(C.label).withAlphaComponent(0.045)
        actionPill.layer.cornerRadius = 16
        actionPill.layer.borderWidth = 0.6
        actionPill.layer.borderColor = UIColor(C.label).withAlphaComponent(0.055).cgColor
        actionPill.translatesAutoresizingMaskIntoConstraints = false
        actionHost.addSubview(actionPill)
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.spacing = 2
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionPill.addSubview(actionStack)
        NSLayoutConstraint.activate([
            actionHost.heightAnchor.constraint(equalToConstant: 32),
            actionPill.trailingAnchor.constraint(equalTo: actionHost.trailingAnchor),
            actionPill.topAnchor.constraint(equalTo: actionHost.topAnchor),
            actionPill.bottomAnchor.constraint(equalTo: actionHost.bottomAnchor),
            actionPill.leadingAnchor.constraint(greaterThanOrEqualTo: actionHost.leadingAnchor),
            actionStack.leadingAnchor.constraint(equalTo: actionPill.leadingAnchor, constant: 3),
            actionStack.trailingAnchor.constraint(equalTo: actionPill.trailingAnchor, constant: -3),
            actionStack.topAnchor.constraint(equalTo: actionPill.topAnchor),
            actionStack.bottomAnchor.constraint(equalTo: actionPill.bottomAnchor)
        ])
        configureIconButton(likeButton, action: #selector(toggleLike))
        configureIconButton(commentButton, action: #selector(openComments))
        configureIconButton(actionMoreButton, action: #selector(showMore))
        likeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        commentButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        actionMoreButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        actionStack.addArrangedSubview(likeButton)
        actionStack.addArrangedSubview(commentButton)
        actionStack.addArrangedSubview(actionMoreButton)
    }

    private func configureSocialView() {
        socialView.backgroundColor = UIColor(Color.dyn(0xF7F7F9, 0x121214))
        socialView.layer.cornerRadius = 15
        socialView.layer.cornerCurve = .continuous
        socialView.layer.borderWidth = 0.6
        socialView.layer.borderColor = UIColor(C.label).withAlphaComponent(0.055).cgColor
        socialStack.axis = .vertical
        socialStack.alignment = .fill
        socialStack.spacing = 8
        socialStack.isLayoutMarginsRelativeArrangement = true
        socialStack.layoutMargins = UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        socialStack.translatesAutoresizingMaskIntoConstraints = false
        socialView.addSubview(socialStack)
        NSLayoutConstraint.activate([
            socialStack.leadingAnchor.constraint(equalTo: socialView.leadingAnchor),
            socialStack.trailingAnchor.constraint(equalTo: socialView.trailingAnchor),
            socialStack.topAnchor.constraint(equalTo: socialView.topAnchor),
            socialStack.bottomAnchor.constraint(equalTo: socialView.bottomAnchor)
        ])

        likeAvatars.translatesAutoresizingMaskIntoConstraints = false
        likeAvatars.heightAnchor.constraint(equalToConstant: 24).isActive = true
        likeSummaryLabel.font = momentUIFont(13, .medium, relativeTo: .caption1)
        likeSummaryLabel.textColor = UIColor(C.label)
        likeSummaryLabel.lineBreakMode = .byTruncatingTail
        likesChevron.tintColor = UIColor(C.subLabel)
        likesChevron.contentMode = .scaleAspectFit
        likesChevron.translatesAutoresizingMaskIntoConstraints = false
        likesChevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
        likesChevron.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let row = UIStackView(arrangedSubviews: [likeAvatars, likeSummaryLabel,
                                                UIView(), likesChevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        likesButton.addSubview(row)
        likesButton.addTarget(self, action: #selector(openLikes), for: .touchUpInside)
        NSLayoutConstraint.activate([
            likesButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            row.leadingAnchor.constraint(equalTo: likesButton.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: likesButton.trailingAnchor),
            row.topAnchor.constraint(equalTo: likesButton.topAnchor),
            row.bottomAnchor.constraint(equalTo: likesButton.bottomAnchor)
        ])
    }

    private func configureFooter() {
        footerView.backgroundColor = UIColor(C.pageBg)
        footerSpinner.translatesAutoresizingMaskIntoConstraints = false
        footerSpinner.color = UIColor(C.subLabel)
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = pfUIFont(13)
        footerLabel.textColor = UIColor(C.subLabel)
        footerLabel.numberOfLines = 0
        footerLabel.textAlignment = .center
        footerView.addSubview(footerSpinner)
        footerView.addSubview(footerLabel)
        NSLayoutConstraint.activate([
            footerSpinner.leadingAnchor.constraint(equalTo: footerView.leadingAnchor,
                                                   constant: 16),
            footerSpinner.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
            footerLabel.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 16),
            footerLabel.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -16),
            footerLabel.topAnchor.constraint(equalTo: footerView.topAnchor, constant: 8),
            footerLabel.bottomAnchor.constraint(equalTo: footerView.bottomAnchor, constant: -8)
        ])
    }

    private func configurePromotion(_ promotion: MomentPromotion?) {
        promotionView.isHidden = promotion == nil
        guard let promotion else { return }
        promotionLabel.text = "  " + (promotion.label ?? Tr("推广")).uppercased() + "  "
        sponsorLabel.text = promotion.sponsor ?? promotion.disclosure ?? Tr("品牌内容")
    }

    private func configureHeader(_ moment: Moment, actions: NativeMomentActions) {
        let avatarPath = moment.author?.avatarPath ?? ""
        if avatarPath.isEmpty {
            avatar.setPlaceholder(moment.author?.name ?? Tr("星"))
        } else {
            avatar.set(path: avatarPath, size: NativeMomentTimelineMetrics.avatar)
        }
        nameLabel.text = moment.author?.name ?? ""
        pinnedIcon.isHidden = moment.pinned != true
        var time = TimeFmt.ago(moment.createdAt)
        if let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            time += "  ·  " + location
        }
        timeLabel.text = time
        self.actions = actions
    }

    private func configureBody(_ moment: Moment, actions: NativeMomentActions) {
        let text = moment.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        bodyView.isHidden = text.isEmpty
        guard !text.isEmpty else {
            bodyView.attributedText = nil
            return
        }
        let normalized = NativeMomentTextLayout.normalized(text)
        let linked = RichText.lines(normalized, size: 16.5)
        let value = NSMutableAttributedString(attributedString: NSAttributedString(linked))
        let range = NSRange(location: 0, length: value.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        value.addAttributes([
            .font: momentUIFont(16.5, .regular, relativeTo: .body),
            .foregroundColor: UIColor(C.label),
            .paragraphStyle: paragraph
        ], range: range)
        value.enumerateAttribute(.link, in: range) { link, linkRange, _ in
            guard link != nil else { return }
            value.addAttribute(.foregroundColor,
                               value: UIColor(hex: 0x576B95),
                               range: linkRange)
        }
        bodyView.attributedText = value
        bodyView.linkTextAttributes = [
            .foregroundColor: UIColor(hex: 0x576B95)
        ]
        self.actions = actions
    }

    private func configureMedia(_ moment: Moment, actions: NativeMomentActions) {
        mediaControls.forEach { $0.setPlaybackActive(false) }
        mediaControls.removeAll(keepingCapacity: true)
        mediaCanvas.subviews.forEach { $0.removeFromSuperview() }
        let images = moment.images ?? []
        let video = moment.video ?? ""
        mediaCanvas.isHidden = images.isEmpty && video.isEmpty
        guard !mediaCanvas.isHidden else { return }

        let cardWidth = max(
            220,
            (window?.bounds.width ?? L.width) - NativeMomentTimelineMetrics.contentInset
                - NativeMomentTimelineMetrics.trailingInset
        )
        if !video.isEmpty {
            let ratio = CGFloat(max(1, moment.videoH ?? 4))
                / CGFloat(max(1, moment.videoW ?? 5))
            let height = min(430, max(cardWidth * 0.62, cardWidth * ratio))
            let control = NativeMomentMediaControl()
            control.translatesAutoresizingMaskIntoConstraints = false
            control.configureVideo(cover: moment.videoCover ?? "",
                                   videoPath: video,
                                   seconds: moment.videoSeconds ?? 0,
                                   pinned: moment.pinned == true,
                                   radius: 18)
            mediaControls.append(control)
            control.addAction(UIAction { [weak self] _ in
                guard let self, let moment = self.moment else { return }
                let raw = moment.video ?? ""
                let full = raw.hasPrefix("http") ? raw : API.shared.base + raw
                if let url = URL(string: full) { actions.openVideo(url) }
            }, for: .touchUpInside)
            mediaCanvas.addSubview(control)
            mediaWidthConstraint.constant = cardWidth
            mediaHeightConstraint.constant = height
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: mediaCanvas.leadingAnchor),
                control.topAnchor.constraint(equalTo: mediaCanvas.topAnchor),
                control.widthAnchor.constraint(equalToConstant: cardWidth),
                control.heightAnchor.constraint(equalToConstant: height)
            ])
            return
        }

        if images.count == 1 {
            let path = images[0]
            let size = moment.imageSizes?[path]
            let knownSize = (size?.count ?? 0) >= 2 && (size?[1] ?? 0) > 0
                ? CGSize(width: CGFloat(size![0]), height: CGFloat(size![1]))
                : nil
            let fitted = MomentMediaLayout.singleImageSize(knownSize: knownSize,
                                                            width: cardWidth)
            let control = NativeMomentMediaControl()
            control.translatesAutoresizingMaskIntoConstraints = false
            control.configureImage(path: path,
                                   radius: MomentMediaLayout.singleRadius)
            mediaControls.append(control)
            control.addAction(UIAction { [weak self] _ in
                guard let moment = self?.moment else { return }
                actions.openImage(moment, 0)
            }, for: .touchUpInside)
            mediaCanvas.addSubview(control)
            mediaWidthConstraint.constant = fitted.width
            mediaHeightConstraint.constant = fitted.height
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: mediaCanvas.leadingAnchor),
                control.topAnchor.constraint(equalTo: mediaCanvas.topAnchor),
                control.widthAnchor.constraint(equalToConstant: fitted.width),
                control.heightAnchor.constraint(equalToConstant: fitted.height)
            ])
            return
        }

        let columns = MomentMediaLayout.columns(for: images.count)
        let cellSize = MomentMediaLayout.gridCellSize(count: images.count,
                                                       width: cardWidth)
        let gap = MomentMediaLayout.gap
        let rowCount = Int(ceil(Double(images.count) / Double(columns)))
        let gridWidth = cellSize.width * CGFloat(columns)
            + gap * CGFloat(max(0, columns - 1))
        let gridHeight = cellSize.height * CGFloat(rowCount)
            + gap * CGFloat(max(0, rowCount - 1))
        let gridHost = UIView()
        gridHost.translatesAutoresizingMaskIntoConstraints = false
        mediaCanvas.addSubview(gridHost)
        mediaWidthConstraint.constant = gridWidth
        mediaHeightConstraint.constant = gridHeight
        NSLayoutConstraint.activate([
            gridHost.leadingAnchor.constraint(equalTo: mediaCanvas.leadingAnchor),
            gridHost.topAnchor.constraint(equalTo: mediaCanvas.topAnchor),
            gridHost.widthAnchor.constraint(equalToConstant: gridWidth),
            gridHost.heightAnchor.constraint(equalToConstant: gridHeight)
        ])
        for (index, path) in images.enumerated() {
            let row = index / columns
            let column = index % columns
            let control = NativeMomentMediaControl()
            control.translatesAutoresizingMaskIntoConstraints = false
            control.configureImage(path: path,
                                   radius: MomentMediaLayout.gridRadius)
            mediaControls.append(control)
            control.addAction(UIAction { [weak self] _ in
                guard let moment = self?.moment else { return }
                actions.openImage(moment, index)
            }, for: .touchUpInside)
            gridHost.addSubview(control)
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(
                    equalTo: gridHost.leadingAnchor,
                    constant: CGFloat(column) * (cellSize.width + gap)
                ),
                control.topAnchor.constraint(
                    equalTo: gridHost.topAnchor,
                    constant: CGFloat(row) * (cellSize.height + gap)
                ),
                control.widthAnchor.constraint(equalToConstant: cellSize.width),
                control.heightAnchor.constraint(equalToConstant: cellSize.height)
            ])
        }
    }

    private func configureActions(_ moment: Moment, actions: NativeMomentActions) {
        let liked = optimisticLiked ?? (moment.likedByMe == true)
        let likeCount = (moment.likes ?? []).count
            + (optimisticLiked == nil || optimisticLiked == moment.likedByMe
               ? 0 : (optimisticLiked == true ? 1 : -1))
        var likeConfig = UIButton.Configuration.plain()
        likeConfig.image = UIImage(systemName: liked ? "heart.fill" : "heart")
        likeConfig.title = likeCount > 0 ? "\(likeCount)" : nil
        likeConfig.imagePadding = 5
        likeConfig.baseForegroundColor = liked ? UIColor(hex: 0xFF3B4D)
                                                : UIColor(C.subLabel)
        likeConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9,
                                                           bottom: 0, trailing: 9)
        likeConfig.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        likeConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = self.momentUIFont(12.5, .medium, relativeTo: .caption1)
                return out
            }
        likeButton.configuration = likeConfig

        let comments = moment.comments ?? []
        var commentConfig = UIButton.Configuration.plain()
        commentConfig.image = UIImage(systemName: "bubble.right")
        commentConfig.title = comments.isEmpty ? nil : "\(comments.count)"
        commentConfig.imagePadding = 5
        commentConfig.baseForegroundColor = UIColor(C.subLabel)
        commentConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9,
                                                              bottom: 0, trailing: 9)
        commentConfig.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 17.5, weight: .regular)
        commentConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = self.momentUIFont(12.5, .medium, relativeTo: .caption1)
                return out
            }
        commentButton.configuration = commentConfig

        var moreConfig = UIButton.Configuration.plain()
        moreConfig.image = UIImage(systemName: "ellipsis")
        moreConfig.baseForegroundColor = UIColor(C.subLabel)
        moreConfig.contentInsets = .zero
        moreConfig.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 16.5, weight: .semibold)
        actionMoreButton.configuration = moreConfig
        self.actions = actions
    }

    private func configureSocial(_ moment: Moment, actions: NativeMomentActions) {
        socialStack.arrangedSubviews.forEach {
            socialStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let likes = stableOrderedLikes(moment.likes ?? [],
                                       actions: actions)
        let comments = moment.comments ?? []
        socialView.isHidden = likes.isEmpty && comments.isEmpty
        guard !socialView.isHidden else { return }

        if !likes.isEmpty {
            likeAvatars.subviews.forEach { $0.removeFromSuperview() }
            let visible = Array(likes.prefix(6))
            for (index, like) in visible.enumerated() {
                let path = like.userId.map(actions.avatarPathFor) ?? ""
                let avatar = NativeMomentAvatarView(size: 24)
                avatar.layer.borderWidth = 2
                avatar.layer.borderColor = UIColor(
                    Color.dyn(0xF7F7F9, 0x121214)
                ).cgColor
                if path.isEmpty {
                    avatar.setPlaceholder(like.nickname ?? Tr("星"))
                } else {
                    avatar.set(path: path, size: 24)
                }
                avatar.translatesAutoresizingMaskIntoConstraints = false
                likeAvatars.addSubview(avatar)
                NSLayoutConstraint.activate([
                    avatar.leadingAnchor.constraint(equalTo: likeAvatars.leadingAnchor,
                                                    constant: CGFloat(index) * 17),
                    avatar.topAnchor.constraint(equalTo: likeAvatars.topAnchor)
                ])
            }
            var avatarWidth = CGFloat(max(0, visible.count - 1)) * 17 + 24
            if likes.count > 6 {
                let more = PaddedLabel()
                more.translatesAutoresizingMaskIntoConstraints = false
                more.text = "+\(likes.count - 6)"
                more.font = .systemFont(ofSize: 9.5, weight: .bold)
                more.textAlignment = .center
                more.textColor = UIColor(C.subLabel)
                more.backgroundColor = UIColor(C.label).withAlphaComponent(0.07)
                more.layer.cornerRadius = 12
                more.clipsToBounds = true
                more.layer.borderWidth = 2
                more.layer.borderColor = UIColor(
                    Color.dyn(0xF7F7F9, 0x121214)
                ).cgColor
                likeAvatars.addSubview(more)
                NSLayoutConstraint.activate([
                    more.leadingAnchor.constraint(equalTo: likeAvatars.leadingAnchor,
                                                  constant: CGFloat(visible.count) * 17),
                    more.topAnchor.constraint(equalTo: likeAvatars.topAnchor),
                    more.widthAnchor.constraint(equalToConstant: 24),
                    more.heightAnchor.constraint(equalToConstant: 24)
                ])
                avatarWidth = CGFloat(visible.count) * 17 + 24
            }
            if let likeAvatarsWidth {
                likeAvatarsWidth.constant = avatarWidth
            } else {
                let constraint = likeAvatars.widthAnchor.constraint(
                    equalToConstant: avatarWidth
                )
                constraint.isActive = true
                likeAvatarsWidth = constraint
            }
            likeSummaryLabel.text = likeSummary(likes, moment: moment)
            socialStack.addArrangedSubview(likesButton)
        }

        for comment in comments.prefix(2) {
            let label = UILabel()
            label.numberOfLines = 2
            label.font = momentUIFont(13.5, .regular, relativeTo: .caption1)
            label.textColor = UIColor(C.label)
            let name = comment.nickname ?? ""
            let reply = comment.replyToName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let content = comment.content ?? ""
            label.text = reply.isEmpty
                ? "\(name)：\(content)"
                : "\(name) 回复 \(reply)：\(content)"
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                               action: #selector(openComments)))
            socialStack.addArrangedSubview(label)
        }

        if comments.count > 2 {
            let button = UIButton(type: .system)
            button.contentHorizontalAlignment = .leading
            button.setTitle(Lang.isEnglish
                            ? "View all \(comments.count) comments"
                            : "查看全部 \(comments.count) 条评论",
                            for: .normal)
            button.setTitleColor(UIColor(C.label).withAlphaComponent(0.72), for: .normal)
            button.titleLabel?.font = momentUIFont(13, .medium, relativeTo: .caption1)
            button.addTarget(self, action: #selector(openComments), for: .touchUpInside)
            socialStack.addArrangedSubview(button)
        }
    }

    private func configureFooter(text: String?, waiting: Bool, isLast: Bool) {
        footerView.isHidden = !isLast || text == nil
        guard isLast, let text else { return }
        footerLabel.text = text
        if waiting {
            footerSpinner.startAnimating()
            footerSpinner.isHidden = false
            footerLabel.textAlignment = .center
            footerLabel.text = "       " + text
        } else {
            footerSpinner.stopAnimating()
            footerSpinner.isHidden = true
            footerLabel.textAlignment = .center
        }
    }

    private func stableOrderedLikes(_ likes: [MomentLike],
                                    actions: NativeMomentActions) -> [MomentLike] {
        var seen = Set<String>()
        let unique = likes.filter { like in
            let key = like.userId?.isEmpty == false
                ? like.userId! : (like.nickname ?? UUID().uuidString)
            return seen.insert(key).inserted
        }
        return unique.filter { actions.isFriend($0.userId ?? "") }
            + unique.filter { !actions.isFriend($0.userId ?? "") }
    }

    private func likeSummary(_ likes: [MomentLike], moment: Moment) -> String {
        let names = likes.compactMap(\.nickname).filter { !$0.isEmpty }
        let count = likes.count
        if Lang.isEnglish {
            switch names.count {
            case 0: return count == 1 ? "1 person likes this" : "\(count) people like this"
            case 1: return count > 1 ? "\(names[0]) and \(count - 1) others" : names[0]
            case 2: return count > 2 ? "\(names[0]), \(names[1]) and \(count - 2) others"
                : "\(names[0]) and \(names[1])"
            default: return "\(names[0]), \(names[1]) and \(count - 2) others"
            }
        }
        switch names.count {
        case 0: return "\(count) 人觉得不错"
        case 1: return count > 1 ? "\(names[0])等 \(count) 人" : names[0]
        case 2: return count > 2 ? "\(names[0])、\(names[1])等 \(count) 人"
            : "\(names[0])、\(names[1])"
        default: return "\(names[0])、\(names[1])等 \(count) 人"
        }
    }

    private func configureIconButton(_ button: UIButton, action: Selector) {
        button.tintColor = UIColor(C.subLabel)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func momentUIFont(_ size: CGFloat, _ weight: Font.Weight,
                              relativeTo style: UIFont.TextStyle) -> UIFont {
        let preferred = max(11, size * fontScale * CareMode.scale)
        let scaled = UIFontMetrics(forTextStyle: style)
            .scaledValue(for: preferred).rounded()
        if !AppFontPrefs.family.isEmpty,
           let name = pfName(weight),
           let font = UIFont(name: name, size: scaled) {
            return font
        }
        let uiWeight: UIFont.Weight = weight == .semibold ? .semibold
            : (weight == .medium ? .medium : (weight == .bold ? .bold : .regular))
        return .systemFont(ofSize: scaled, weight: uiWeight)
    }

    @objc private func openComments() {
        guard let moment else { return }
        actions?.openComments(moment)
    }

    @objc private func openAuthor() {
        guard let user = moment?.author else { return }
        actions?.openAvatar(user)
    }

    @objc private func showMore() {
        guard let moment else { return }
        actions?.more(moment)
    }

    @objc private func toggleLike() {
        guard let moment else { return }
        let base = optimisticLiked ?? (moment.likedByMe == true)
        optimisticLiked = !base
        if !base {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            likeBurst.burst()
        }
        configureActions(moment, actions: actions!)
    }

    @objc private func openLikes() {
        guard let moment, let actions else { return }
        actions.openLikes(stableOrderedLikes(moment.likes ?? [], actions: actions))
    }
}

extension NativeMomentRowCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL,
                  in characterRange: NSRange,
                  interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL)
        return false
    }
}

private final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 4, dy: 2))
    }
}
