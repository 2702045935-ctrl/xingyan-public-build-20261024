import SwiftUI
import UIKit

struct NativeMomentRowConfiguration {
    let moment: Moment
    let day: String?
    let width: CGFloat
    let likeSummary: String
    let likeAvatarPaths: [String]
    let commentLines: [String]
    let moreCommentsText: String?
    let onOpenComments: () -> Void
    let onOpenImage: (Int) -> Void
    let onOpenVideo: (URL) -> Void
    let onOpenAvatar: (User) -> Void
    let onLike: () -> Void
    let onMore: () -> Void
    let onShowLikes: () -> Void
}

private struct NativeMomentMetrics {
    let width: CGFloat
    let contentWidth: CGFloat
    let dayY: CGFloat
    let headerY: CGFloat
    let textY: CGFloat
    let textHeight: CGFloat
    let mediaY: CGFloat
    let mediaHeight: CGFloat
    let actionY: CGFloat
    let socialY: CGFloat
    let socialHeight: CGFloat
    let totalHeight: CGFloat
    let mediaColumns: Int
    let mediaCell: CGFloat
    let mediaRows: Int

    init(_ c: NativeMomentRowConfiguration) {
        width = c.width
        contentWidth = max(1, width - L.momentPadH * 2)
        dayY = c.day == nil ? 0 : 18
        let cardY: CGFloat = c.day == nil ? 0 : 50
        headerY = cardY + 18

        var y = headerY + 42
        let content = (c.moment.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            textY = 0
            textHeight = 0
        } else {
            y += 13
            textY = y
            textHeight = NativeMomentFeedCell.textHeight(content, width: contentWidth)
            y += textHeight
        }

        let images = c.moment.images ?? []
        let isVideo = !(c.moment.video ?? "").isEmpty
        if images.isEmpty && !isVideo {
            mediaY = 0
            mediaHeight = 0
            mediaColumns = 0
            mediaCell = 0
            mediaRows = 0
        } else {
            y += 13
            mediaY = y
            let grid = NativeMomentFeedCell.mediaGrid(moment: c.moment, width: contentWidth)
            mediaHeight = grid.height
            mediaColumns = grid.columns
            mediaCell = grid.cell
            mediaRows = grid.rows
            y += mediaHeight
        }

        y += 10
        actionY = y
        y += 32

        let hasSocial = !c.likeSummary.isEmpty || !c.commentLines.isEmpty || c.moreCommentsText != nil
        if hasSocial {
            y += 9
            socialY = y
            socialHeight = NativeMomentFeedCell.socialHeight(c)
            y += socialHeight
        } else {
            socialY = 0
            socialHeight = 0
        }
        totalHeight = y + 17
    }
}

final class NativeMomentFeedCell: UICollectionViewCell {
    static func preferredHeight(_ c: NativeMomentRowConfiguration) -> CGFloat {
        ceil(NativeMomentMetrics(c).totalHeight)
    }

    private let dayLabel = UILabel()
    private let avatarImage = NativeMomentImage()
    private let avatarFallback = UILabel()
    private let nameLabel = UILabel()
    private let pinImage = UIImageView()
    private let metaLabel = UILabel()
    private let headerMore = UIButton(type: .system)
    private let contentLabel = UILabel()
    private let mediaContainer = UIView()
    private let mediaImages = (0..<9).map { _ in NativeMomentImage() }
    private let mediaTapButtons = (0..<9).map { _ in UIButton(type: .custom) }
    private let videoPlay = UIView()
    private let videoPlayIcon = UIImageView(image: UIImage(systemName: "play.fill"))
    private let videoTapButton = UIButton(type: .custom)
    private let likeButton = UIButton(type: .system)
    private let commentButton = UIButton(type: .system)
    private let actionMore = UIButton(type: .system)
    private let socialContainer = UIView()
    private let socialHeart = UILabel()
    private let socialSummary = UILabel()
    private let socialTapButton = UIButton(type: .custom)
    private let socialAvatars = (0..<8).map { _ in NativeMomentImage() }
    private let socialComments = [UILabel(), UILabel()]
    private let moreCommentsButton = UIButton(type: .system)
    private let divider = UIView()
    private var configuration: NativeMomentRowConfiguration?
    private var metrics: NativeMomentMetrics?
    private var mediaFrames: [(UIView, CGRect)] = []
    private var socialFrames: [(UIView, CGRect)] = []
    private var likedOverride: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configuration = nil
        likedOverride = nil
        hideMediaPool()
        hideSocialPool()
        mediaFrames = []
        socialFrames = []
        avatarImage.reset()
    }

    func configure(_ c: NativeMomentRowConfiguration) {
        let oldMomentId = configuration?.moment.id
        let oldLiked = configuration?.moment.likedByMe
        configuration = c
        if oldMomentId != c.moment.id || oldLiked != c.moment.likedByMe {
            likedOverride = nil
        }
        metrics = NativeMomentMetrics(c)
        dayLabel.text = c.day
        dayLabel.isHidden = c.day == nil

        let author = c.moment.author
        nameLabel.text = author?.name ?? ""
        let location = (c.moment.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        metaLabel.text = location.isEmpty
            ? TimeFmt.ago(c.moment.createdAt)
            : "\(TimeFmt.ago(c.moment.createdAt)) · \(location)"
        pinImage.isHidden = c.moment.pinned != true
        avatarImage.set(path: author?.avatarPath ?? "", maxSide: 128)
        avatarFallback.text = String((author?.name ?? Tr("星")).prefix(1))
        avatarFallback.isHidden = !(author?.avatarPath ?? "").isEmpty

        let text = (c.moment.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        contentLabel.isHidden = text.isEmpty
        if !text.isEmpty {
            let attr = NSMutableAttributedString(
                attributedString: NSAttributedString(RichText.linkified(text))
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.lineBreakMode = .byWordWrapping
            attr.addAttributes([
                .font: NativeMomentType.body,
                .paragraphStyle: paragraph,
                .foregroundColor: UIColor(C.label)
            ], range: NSRange(location: 0, length: attr.length))
            contentLabel.attributedText = attr
        } else {
            contentLabel.attributedText = nil
        }

        rebuildMedia()
        rebuildSocial()
        updateLikeButton()
        contentView.backgroundColor = UIColor(C.pageBg)
        setNeedsLayout()
    }

    static func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NativeMomentType.body, .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(rect.height)
    }

    static func mediaGrid(moment: Moment, width: CGFloat) -> (height: CGFloat, columns: Int, rows: Int, cell: CGFloat) {
        if !(moment.video ?? "").isEmpty {
            let ratio = CGFloat(max(1, moment.videoH ?? 4)) / CGFloat(max(1, moment.videoW ?? 5))
            return (min(430, max(width * 0.62, width * ratio)), 1, 1, width)
        }
        let images = moment.images ?? []
        guard !images.isEmpty else { return (0, 0, 0, 0) }
        let gap: CGFloat = images.count == 1 ? 0 : 4
        if images.count == 1 {
            let size = moment.imageSizes?[images[0]]
            let ratio = (size?.count ?? 0) >= 2 && (size?[1] ?? 0) > 0
                ? CGFloat(size![0]) / CGFloat(size![1])
                : 4.0 / 3.0
            return (min(430, max(width * 0.62, width / max(0.55, ratio))), 1, 1, width)
        }
        let columns = (images.count == 2 || images.count == 4) ? 2 : 3
        let cell = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        return (cell * CGFloat(rows) + gap * CGFloat(max(0, rows - 1)), columns, rows, cell)
    }

    static func socialHeight(_ c: NativeMomentRowConfiguration) -> CGFloat {
        var h: CGFloat = 0
        let width = max(1, c.width - L.momentPadH * 2)
        if !c.likeSummary.isEmpty { h += 32 }
        for line in c.commentLines {
            if h > 0 { h += 5 }
            h += commentHeight(line, width: width)
        }
        if c.moreCommentsText != nil {
            if h > 0 { h += 5 }
            h += 18
        }
        return h
    }

    private static func commentHeight(_ text: String, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: 38),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NativeMomentType.comment],
            context: nil
        )
        return min(38, ceil(rect.height))
    }

    private func setupViews() {
        contentView.clipsToBounds = true
        clipsToBounds = true

        dayLabel.font = .systemFont(ofSize: 13)
        dayLabel.textColor = UIColor(C.subLabel)

        avatarFallback.font = .systemFont(ofSize: 18, weight: .semibold)
        avatarFallback.textColor = UIColor(C.label)
        avatarFallback.textAlignment = .center
        avatarFallback.backgroundColor = UIColor.secondarySystemFill
        avatarFallback.layer.cornerRadius = 21
        avatarFallback.layer.cornerCurve = .continuous
        avatarFallback.clipsToBounds = true
        avatarImage.layer.cornerRadius = 21
        avatarImage.clipsToBounds = true

        nameLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
        nameLabel.textColor = UIColor(C.label)
        nameLabel.lineBreakMode = .byTruncatingTail
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = UIColor(C.subLabel)
        metaLabel.lineBreakMode = .byTruncatingTail

        pinImage.image = UIImage(systemName: "pin.fill")
        pinImage.tintColor = UIColor(C.subLabel)
        pinImage.contentMode = .scaleAspectFit

        headerMore.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        headerMore.tintColor = UIColor(C.subLabel)
        headerMore.addAction(UIAction { [weak self] _ in self?.configuration?.onMore() },
                             for: .touchUpInside)

        contentLabel.numberOfLines = 0
        contentLabel.textColor = UIColor(C.label)
        contentLabel.isUserInteractionEnabled = true
        contentLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(openComments))
        )
        let longPress = UILongPressGestureRecognizer(target: self,
                                                     action: #selector(longPressContent(_:)))
        longPress.minimumPressDuration = 0.45
        contentLabel.addGestureRecognizer(longPress)

        avatarImage.isUserInteractionEnabled = true
        avatarImage.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(openAvatar))
        )
        nameLabel.isUserInteractionEnabled = true
        nameLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(openAvatar))
        )

        likeButton.addAction(UIAction { [weak self] _ in self?.likeTapped() }, for: .touchUpInside)
        commentButton.addAction(UIAction { [weak self] _ in self?.configuration?.onOpenComments() },
                                for: .touchUpInside)
        actionMore.addAction(UIAction { [weak self] _ in self?.configuration?.onMore() },
                             for: .touchUpInside)
        actionMore.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        actionMore.tintColor = UIColor(C.subLabel)

        [dayLabel, avatarImage, avatarFallback, nameLabel, pinImage, metaLabel,
         headerMore, contentLabel, mediaContainer, likeButton, commentButton,
         actionMore, socialContainer, divider].forEach {
            contentView.addSubview($0)
        }

        mediaContainer.clipsToBounds = false
        for (index, image) in mediaImages.enumerated() {
            image.layer.cornerCurve = .continuous
            image.clipsToBounds = true
            mediaContainer.addSubview(image)

            let button = mediaTapButtons[index]
            button.tag = index
            button.addAction(
                UIAction { [weak self] _ in self?.configuration?.onOpenImage(index) },
                for: .touchUpInside
            )
            mediaContainer.addSubview(button)
        }
        videoPlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        videoPlay.layer.cornerRadius = 27
        videoPlay.isUserInteractionEnabled = false
        videoPlayIcon.tintColor = .white
        videoPlayIcon.contentMode = .scaleAspectFit
        videoPlayIcon.frame = CGRect(x: 19, y: 16, width: 20, height: 22)
        videoPlay.addSubview(videoPlayIcon)
        mediaContainer.addSubview(videoPlay)
        videoTapButton.addAction(
            UIAction { [weak self] _ in
                guard let self, let raw = self.configuration?.moment.video else { return }
                let full = raw.hasPrefix("http") ? raw : API.shared.base + raw
                if let url = URL(string: full) {
                    self.configuration?.onOpenVideo(url)
                }
            },
            for: .touchUpInside
        )
        mediaContainer.addSubview(videoTapButton)
        hideMediaPool()

        socialContainer.clipsToBounds = true
        socialHeart.text = "♥"
        socialHeart.textAlignment = .center
        socialHeart.textColor = .white
        socialHeart.font = .systemFont(ofSize: 14, weight: .bold)
        socialHeart.backgroundColor = UIColor(hex: 0xF33D5E)
        socialHeart.layer.cornerRadius = 12.5
        socialHeart.clipsToBounds = true

        socialSummary.font = .systemFont(ofSize: 12.5, weight: .medium)
        socialSummary.textColor = UIColor(C.label)
        socialSummary.lineBreakMode = .byTruncatingTail

        socialTapButton.addAction(
            UIAction { [weak self] _ in self?.configuration?.onShowLikes() },
            for: .touchUpInside
        )
        for avatar in socialAvatars {
            avatar.layer.cornerRadius = 10.5
            avatar.layer.borderWidth = 1.2
            avatar.layer.borderColor = UIColor(C.pageBg).cgColor
            avatar.clipsToBounds = true
            socialContainer.addSubview(avatar)
        }
        for label in socialComments {
            label.font = .systemFont(ofSize: 13)
            label.textColor = UIColor(C.label)
            label.numberOfLines = 2
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(openComments))
            )
            socialContainer.addSubview(label)
        }
        moreCommentsButton.contentHorizontalAlignment = .left
        moreCommentsButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .medium)
        moreCommentsButton.tintColor = UIColor(C.subLabel)
        moreCommentsButton.addAction(
            UIAction { [weak self] _ in self?.configuration?.onOpenComments() },
            for: .touchUpInside
        )
        [socialHeart, socialSummary, socialTapButton, moreCommentsButton].forEach {
            socialContainer.addSubview($0)
        }
        hideSocialPool()
        divider.backgroundColor = UIColor(C.hairline)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let c = configuration, let m = metrics else { return }
        let pad = L.momentPadH
        let cellWidth = bounds.width
        if c.day != nil {
            dayLabel.frame = CGRect(x: pad, y: m.dayY, width: m.contentWidth, height: 17)
        }
        avatarImage.frame = CGRect(x: pad, y: m.headerY, width: 42, height: 42)
        avatarFallback.frame = avatarImage.frame
        let textX = pad + 42 + 11
        pinImage.frame = CGRect(x: cellWidth - pad - 96, y: m.headerY + 7, width: 10, height: 12)
        pinImage.isHidden = c.moment.pinned != true
        nameLabel.frame = CGRect(x: textX, y: m.headerY,
                                 width: max(1, cellWidth - textX - pad - 44), height: 21)
        metaLabel.frame = CGRect(x: textX, y: m.headerY + 25,
                                 width: max(1, cellWidth - textX - pad - 36), height: 17)
        headerMore.frame = CGRect(x: cellWidth - pad - 34, y: m.headerY + 2, width: 34, height: 34)

        contentLabel.isHidden = m.textHeight <= 0
        if m.textHeight > 0 {
            contentLabel.frame = CGRect(x: pad, y: m.textY, width: m.contentWidth, height: m.textHeight)
        }

        mediaContainer.frame = m.mediaHeight > 0
            ? CGRect(x: pad, y: m.mediaY, width: m.contentWidth, height: m.mediaHeight)
            : .zero
        for (view, frame) in mediaFrames { view.frame = frame }

        likeButton.frame = CGRect(x: pad, y: m.actionY,
                                  width: max(44, likeButton.bounds.width), height: 32)
        commentButton.frame = CGRect(x: likeButton.frame.maxX + 12, y: m.actionY,
                                     width: max(44, commentButton.bounds.width), height: 32)
        actionMore.frame = CGRect(x: cellWidth - pad - 34, y: m.actionY, width: 34, height: 32)

        socialContainer.isHidden = m.socialHeight <= 0
        socialContainer.frame = m.socialHeight > 0
            ? CGRect(x: pad, y: m.socialY, width: m.contentWidth, height: m.socialHeight)
            : .zero
        for (view, frame) in socialFrames { view.frame = frame }

        divider.frame = CGRect(x: pad, y: max(0, m.totalHeight - 0.5),
                               width: max(0, cellWidth - pad * 2), height: 0.5)
    }

    private func rebuildMedia() {
        hideMediaPool()
        mediaFrames = []
        guard let c = configuration, let m = metrics else { return }
        let media = c.moment
        if !(media.video ?? "").isEmpty {
            let image = mediaImages[0]
            image.isHidden = false
            image.frame = CGRect(origin: .zero, size: CGSize(width: m.contentWidth, height: m.mediaHeight))
            image.layer.cornerRadius = 12
            image.set(path: media.videoCover ?? "", maxSide: 1440)
            mediaFrames.append((image, CGRect(x: 0, y: 0, width: m.contentWidth, height: m.mediaHeight)))

            videoPlay.isHidden = false
            videoPlay.frame = CGRect(x: (m.contentWidth - 54) / 2,
                                     y: (m.mediaHeight - 54) / 2,
                                     width: 54, height: 54)
            mediaFrames.append((videoPlay, videoPlay.frame))

            videoTapButton.isHidden = false
            videoTapButton.frame = image.frame
            mediaFrames.append((videoTapButton, videoTapButton.frame))
            return
        }

        let paths = media.images ?? []
        guard !paths.isEmpty else { return }
        let gap: CGFloat = paths.count == 1 ? 0 : 4
        for (index, path) in paths.enumerated() {
            let col = index % max(1, m.mediaColumns)
            let row = index / max(1, m.mediaColumns)
            let frame = CGRect(
                x: CGFloat(col) * (m.mediaCell + gap),
                y: CGFloat(row) * (m.mediaCell + gap),
                width: paths.count == 1 ? m.contentWidth : m.mediaCell,
                height: paths.count == 1 ? m.mediaHeight : m.mediaCell
            )
            let image = mediaImages[index]
            image.isHidden = false
            image.frame = frame
            image.layer.cornerRadius = paths.count == 1 ? 12 : 8
            image.set(path: path, maxSide: paths.count == 1 ? 1440 : 960)
            mediaFrames.append((image, frame))
            let tap = mediaTapButtons[index]
            tap.isHidden = false
            tap.frame = frame
            mediaFrames.append((tap, frame))
        }
    }

    private func hideMediaPool() {
        for image in mediaImages {
            image.isHidden = true
            image.reset()
        }
        for button in mediaTapButtons {
            button.isHidden = true
        }
        videoPlay.isHidden = true
        videoTapButton.isHidden = true
    }

    private func rebuildSocial() {
        hideSocialPool()
        socialFrames = []
        guard let c = configuration, !c.likeSummary.isEmpty ||
                !c.commentLines.isEmpty || c.moreCommentsText != nil else { return }
        let contentWidth = max(1, c.width - L.momentPadH * 2)
        var y: CGFloat = 0
        if !c.likeSummary.isEmpty {
            socialHeart.isHidden = false
            socialHeart.frame = CGRect(x: 0, y: 3, width: 25, height: 25)
            socialFrames.append((socialHeart, socialHeart.frame))

            var x: CGFloat = 32
            for (index, path) in c.likeAvatarPaths.prefix(socialAvatars.count).enumerated() {
                let avatar = socialAvatars[index]
                avatar.isHidden = false
                avatar.frame = CGRect(x: x, y: 5, width: 21, height: 21)
                avatar.set(path: path, maxSide: 84)
                socialFrames.append((avatar, avatar.frame))
                x += 18
            }
            socialSummary.isHidden = false
            socialSummary.text = c.likeSummary
            socialSummary.frame = CGRect(x: x + 8, y: 2,
                                         width: max(1, contentWidth - x - 22), height: 27)
            socialFrames.append((socialSummary, socialSummary.frame))
            socialTapButton.isHidden = false
            socialTapButton.frame = CGRect(x: 0, y: 0, width: contentWidth, height: 32)
            socialFrames.append((socialTapButton, socialTapButton.frame))
            y = 32
        }

        for (index, line) in c.commentLines.prefix(socialComments.count).enumerated() {
            if y > 0 { y += 5 }
            let h = Self.commentHeight(line, width: contentWidth)
            let label = socialComments[index]
            label.isHidden = false
            label.frame = CGRect(x: 0, y: y, width: contentWidth, height: h)
            label.text = line
            socialFrames.append((label, label.frame))
            y += h
        }
        if let more = c.moreCommentsText {
            if y > 0 { y += 5 }
            moreCommentsButton.isHidden = false
            moreCommentsButton.frame = CGRect(x: 0, y: y, width: contentWidth, height: 18)
            moreCommentsButton.setTitle(more, for: .normal)
            socialFrames.append((moreCommentsButton, moreCommentsButton.frame))
        }
    }

    private func hideSocialPool() {
        socialHeart.isHidden = true
        socialSummary.isHidden = true
        socialSummary.text = nil
        socialTapButton.isHidden = true
        for avatar in socialAvatars {
            avatar.isHidden = true
            avatar.reset()
        }
        for label in socialComments {
            label.isHidden = true
            label.text = nil
        }
        moreCommentsButton.isHidden = true
        moreCommentsButton.setTitle(nil, for: .normal)
    }

    private func likeTapped() {
        guard let c = configuration else { return }
        let currentlyLiked = likedOverride ?? (c.moment.likedByMe == true)
        likedOverride = !currentlyLiked
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateLikeButton()
        c.onLike()
    }

    private func updateLikeButton() {
        guard let c = configuration else { return }
        let liked = likedOverride ?? (c.moment.likedByMe == true)
        var count = (c.moment.likes ?? []).count
        if let override = likedOverride, override != (c.moment.likedByMe == true) {
            count = max(0, count + (override ? 1 : -1))
        }
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: liked ? "heart.fill" : "heart")
        config.imagePadding = 5
        config.baseForegroundColor = liked ? UIColor(hex: 0xFF3B4D) : UIColor(C.subLabel)
        config.title = count > 0 ? "\(count)" : nil
        config.contentInsets = .zero
        likeButton.configuration = config

        var comment = UIButton.Configuration.plain()
        comment.image = UIImage(systemName: "bubble.right")
        comment.imagePadding = 5
        comment.baseForegroundColor = UIColor(C.subLabel)
        let comments = (c.moment.comments ?? []).count
        comment.title = comments > 0 ? "\(comments)" : nil
        comment.contentInsets = .zero
        commentButton.configuration = comment
        likeButton.sizeToFit()
        commentButton.sizeToFit()
    }

    @objc private func openComments() { configuration?.onOpenComments() }
    @objc private func openAvatar() {
        if let user = configuration?.moment.author { configuration?.onOpenAvatar(user) }
    }
    @objc private func longPressContent(_ g: UILongPressGestureRecognizer) {
        if g.state == .began, configuration?.moment.mine == true {
            configuration?.onMore()
        }
    }
}

private enum NativeMomentType {
    static let body = UIFont.systemFont(ofSize: 15.5)
    static let comment = UIFont.systemFont(ofSize: 13)
}

/// Large feeds prefetch many cells at once. Limit image I/O and decoding so
/// scrolling never competes with dozens of full-size media previews.
private actor NativeMomentImageGate {
    static let shared = NativeMomentImageGate(limit: 3)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class NativeMomentImage: UIImageView {
    private var token = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        backgroundColor = UIColor.secondarySystemFill
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        token = UUID()
        image = nil
    }

    func set(path: String, maxSide: CGFloat) {
        token = UUID()
        let request = token
        image = nil
        guard !path.isEmpty else { return }
        if let hit = ImageStore.shared.get(path + "#\(Int(maxSide))") ?? ImageStore.shared.get(path) {
            image = hit
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await NativeMomentImageGate.shared.acquire()
            guard self.token == request, !Task.isCancelled else {
                await NativeMomentImageGate.shared.release()
                return
            }
            var data = await Task.detached(priority: .utility) {
                ImageStore.shared.diskRead(path)
            }.value
            if data == nil, let url = API.shared.assetURL(path) {
                data = try? await API.shared.imageData(url)
            }
            guard self.token == request, !Task.isCancelled, let data else {
                await NativeMomentImageGate.shared.release()
                return
            }
            let decoded = await Task.detached(priority: .utility) {
                RemoteImage.downsampled(data, maxSide: maxSide)
            }.value
            await NativeMomentImageGate.shared.release()
            guard self.token == request, !Task.isCancelled, let decoded else { return }
            ImageStore.shared.put(path + "#\(Int(maxSide))", decoded)
            await MainActor.run {
                guard self.token == request else { return }
                self.image = decoded
            }
            Task.detached(priority: .background) {
                ImageStore.shared.diskWrite(path, data)
            }
        }
    }
}
