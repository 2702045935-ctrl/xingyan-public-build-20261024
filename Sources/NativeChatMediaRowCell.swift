import UIKit

enum NativeChatMediaKind {
    case image(path: String, pixel: CGSize)
    case images(paths: [String])
    case video(cover: String, seconds: Int, w: Int, h: Int)
    case file(name: String, path: String, bytes: Int, type: String)
}

struct NativeChatMediaRowModel {
    var messageID: String
    var kind: NativeChatMediaKind
    var mine: Bool
    var senderName: String
    var senderNameColor: UIColor
    var avatarPath: String
    var avatarName: String
    var avatarSize: CGFloat
    var maxBubbleWidth: CGFloat
    var horizontalMargin: CGFloat
    var avatarGap: CGFloat
    var bottomGap: CGFloat
    var primaryColor: UIColor
    var secondaryColor: UIColor
    var bubbleColor: UIColor
    var showTail: Bool
    var bubbleGlass: Bool
    var showsAvatar: Bool = true
    var reservesAvatarSpace: Bool = true
    var metaText: String
    var metaColor: UIColor
    var tickCount: Int
    var tickColor: UIColor
}

private final class NativeMediaImageView: UIImageView {
    private var requestedPath = ""
    private var requestToken = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentMode = .scaleAspectFill
        backgroundColor = UIColor.secondarySystemFill
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(path: String, maxPixel: CGFloat) {
        guard path != requestedPath || image == nil else { return }
        requestedPath = path
        requestToken = UUID()
        let token = requestToken
        image = nil
        guard !path.isEmpty else { return }
        let key = ImageCacheKey.stablePath(path)
        if let hit = ImageStore.shared.get(key) ?? ImageStore.shared.get(path) {
            image = hit
            return
        }
        Task {
            if let disk = await Task.detached(priority: .utility, operation: {
                ImageStore.shared.diskRead(key)
            }).value,
               let image = await Task.detached(priority: .utility, operation: {
                   UIImage(data: disk)
               }).value {
                await MainActor.run {
                    guard self.requestToken == token else { return }
                    ImageStore.shared.put(key, image)
                    self.image = image
                }
                return
            }
            guard let url = API.shared.assetURL(path) else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if !API.shared.token.isEmpty {
                request.setValue("Bearer \(API.shared.token)",
                                 forHTTPHeaderField: "Authorization")
            }
            guard let (data, response) = try? await API.shared.session.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode,
                  status < 400,
                  let source = UIImage(data: data) else { return }
            let target = CGSize(width: maxPixel, height: maxPixel)
            let decoded = await Task.detached(priority: .utility, operation: {
                source.preparingThumbnail(of: target) ?? source
            }).value
            await MainActor.run {
                guard self.requestToken == token else { return }
                ImageStore.shared.put(key, decoded)
                self.image = decoded
            }
        }
    }
}

final class NativeChatMediaRowView: UIView, UIGestureRecognizerDelegate {
    static let reuseID = "NativeChatMediaRowView"

    private var model: NativeChatMediaRowModel?
    private let avatar = NativeStaticAvatarView()
    private let senderLabel = UILabel()
    private let bubble = NativeChatBubbleBackground()
    private let metadata = NativeMessageMetadataView()
    private let imageView = NativeMediaImageView()
    private let extraImageViews: [NativeMediaImageView] = (0..<3).map { _ in
        NativeMediaImageView()
    }
    private let fileIcon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let badgeLabel = UILabel()
    private let playView = UIImageView(image: UIImage(systemName: "play.fill"))
    private let durationLabel = UILabel()
    private var tapRecognizer: UITapGestureRecognizer?
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private var avatarRecognizer: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentViewSetup()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func contentViewSetup() {
        addSubview(avatar)
        addSubview(bubble)
        addSubview(imageView)
        extraImageViews.forEach { addSubview($0) }
        addSubview(fileIcon)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(badgeLabel)
        addSubview(playView)
        addSubview(durationLabel)
        addSubview(senderLabel)
        addSubview(metadata)

        senderLabel.font = pfUIFont(12.5, .semibold)
        senderLabel.numberOfLines = 1
        senderLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = pfUIFont(15, .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.font = pfUIFont(12)
        detailLabel.numberOfLines = 1
        titleLabel.textColor = UIColor.label
        detailLabel.textColor = UIColor.secondaryLabel
        avatar.isUserInteractionEnabled = true

        imageView.layer.cornerRadius = 8
        imageView.layer.cornerCurve = .continuous
        fileIcon.tintColor = UIColor.white
        fileIcon.contentMode = .scaleAspectFit
        fileIcon.layer.cornerRadius = 10
        fileIcon.layer.cornerCurve = .continuous
        fileIcon.backgroundColor = UIColor.systemIndigo

        badgeLabel.font = pfUIFont(11, .semibold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        badgeLabel.layer.cornerRadius = 12
        badgeLabel.layer.cornerCurve = .continuous
        badgeLabel.clipsToBounds = true

        playView.tintColor = .white
        playView.contentMode = .scaleAspectFit
        playView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        playView.layer.cornerRadius = 22
        playView.layer.cornerCurve = .continuous

        durationLabel.font = pfUIFont(10.5, .semibold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        durationLabel.layer.cornerRadius = 8
        durationLabel.layer.cornerCurve = .continuous
        durationLabel.clipsToBounds = true
    }

    func configure(_ next: NativeChatMediaRowModel) {
        model = next
        avatar.isHidden = !next.showsAvatar
        if next.showsAvatar {
            avatar.configure(path: next.avatarPath, name: next.avatarName)
        }
        let mediaStyle: Bool
        switch next.kind {
        case .image, .images, .video:
            mediaStyle = true
        case .file:
            mediaStyle = false
        }
        senderLabel.text = next.senderName
        senderLabel.textColor = mediaStyle ? .white : next.senderNameColor
        senderLabel.textAlignment = .left
        senderLabel.backgroundColor = mediaStyle && !next.senderName.isEmpty
            ? UIColor.black.withAlphaComponent(0.30)
            : .clear
        senderLabel.layer.cornerRadius = 4
        senderLabel.layer.cornerCurve = .continuous
        senderLabel.clipsToBounds = true
        bubble.fillColor = next.bubbleColor
        bubble.mine = next.mine
        bubble.showTail = next.showTail
        bubble.glass = next.bubbleGlass
        metadata.configure(
            time: next.metaText,
            tickCount: next.tickCount,
            tickColor: next.tickColor,
            textColor: mediaStyle ? .white : next.metaColor,
            mediaStyle: mediaStyle
        )

        imageView.isHidden = true
        extraImageViews.forEach { $0.isHidden = true }
        fileIcon.isHidden = true
        titleLabel.isHidden = true
        detailLabel.isHidden = true
        badgeLabel.isHidden = true
        playView.isHidden = true
        durationLabel.isHidden = true

        switch next.kind {
        case .image(let path, _):
            imageView.isHidden = false
            imageView.configure(path: path, maxPixel: 720)
        case .images(let paths):
            imageView.isHidden = false
            imageView.configure(path: paths.first ?? "", maxPixel: 720)
            let visible = MultiImageMosaic.visibleCount(for: paths.count)
            for (index, view) in extraImageViews.enumerated()
                where index + 1 < visible {
                view.isHidden = false
                view.configure(path: paths[index + 1], maxPixel: 720)
            }
            badgeLabel.isHidden = true
        case .video(let cover, let seconds, _, _):
            imageView.isHidden = false
            imageView.configure(path: cover, maxPixel: 720)
            playView.isHidden = false
            durationLabel.isHidden = seconds <= 0
            durationLabel.text = " \(max(0, seconds))s "
        case .file(let name, let path, let bytes, let type):
            fileIcon.isHidden = false
            titleLabel.isHidden = false
            detailLabel.isHidden = false
            titleLabel.text = name
            titleLabel.textColor = next.primaryColor
            detailLabel.textColor = next.secondaryColor
            detailLabel.text = type + " · " + Self.byteText(bytes)
            fileIcon.image = UIImage(systemName: Self.fileSymbol(name: name, path: path))
        }
        setNeedsLayout()
    }

    func setActions(onTap: @escaping () -> Void,
                    onLongPress: @escaping () -> Void,
                    onAvatar: @escaping () -> Void) {
        if tapRecognizer == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            addGestureRecognizer(tap)
            tapRecognizer = tap
        }
        if longPressRecognizer == nil {
            let long = UILongPressGestureRecognizer(
                target: self,
                action: #selector(longPressed(_:))
            )
            long.minimumPressDuration = 0.42
            long.cancelsTouchesInView = false
            long.delaysTouchesBegan = false
            long.delegate = self
            addGestureRecognizer(long)
            longPressRecognizer = long
        }
        if avatarRecognizer == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
            tap.cancelsTouchesInView = false
            avatar.addGestureRecognizer(tap)
            avatarRecognizer = tap
        }
        self.tapAction = onTap
        self.longPressAction = onLongPress
        avatarAction = onAvatar
    }

    private var tapAction: (() -> Void)?
    private var longPressAction: (() -> Void)?
    private var avatarAction: (() -> Void)?

    @objc private func tapped() { tapAction?() }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        longPressAction?()
    }

    @objc private func avatarTapped() { avatarAction?() }

    func bubbleWindowFrame() -> CGRect {
        convert(bubble.frame, to: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        bubble.frame.contains(touch.location(in: self))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }
        let available = max(1, bounds.width - model.horizontalMargin * 2)
        let avatarReserve = model.reservesAvatarSpace
            ? model.avatarSize + model.avatarGap
            : 0
        let avatarX = model.mine
            ? model.horizontalMargin + available - model.avatarSize
            : model.horizontalMargin
        avatar.frame = CGRect(x: avatarX, y: 1,
                              width: model.avatarSize, height: model.avatarSize)

        let bubbleWidth = Self.bubbleWidth(for: model, available: available)
        let bubbleHeight = Self.bubbleHeight(for: model, width: bubbleWidth)
        let tailInset: CGFloat = model.showTail
            ? WhatsAppChatLayout.tailInset
            : 0
        let bubbleRail = model.mine
            ? model.horizontalMargin + available - avatarReserve
            : model.horizontalMargin + avatarReserve
        let bubbleX = model.mine
            ? bubbleRail - bubbleWidth + tailInset
            : bubbleRail - tailInset
        bubble.frame = CGRect(x: bubbleX, y: 0,
                              width: bubbleWidth, height: bubbleHeight)
        // Native media subviews live in the row coordinate space, not inside
        // the bubble. Anchor their body to the bubble itself and reserve the
        // tail-only strip so images and file cards cannot drift out of frame.
        let body = CGRect(
            x: bubble.frame.minX + (model.mine ? 0 : tailInset),
            y: bubble.frame.minY,
            width: max(1, bubbleWidth - tailInset),
            height: bubbleHeight
        )
        let overlaySender: Bool
        let isFile: Bool
        switch model.kind {
        case .file:
            overlaySender = false
            isFile = true
        case .image, .images, .video:
            overlaySender = true
            isFile = false
        }
        senderLabel.isHidden = model.senderName.isEmpty
        if !model.senderName.isEmpty {
            if overlaySender {
                let font = senderLabel.font ?? UIFont.systemFont(
                    ofSize: 12.5,
                    weight: .semibold
                )
                let textWidth = ceil(
                    (model.senderName as NSString).size(
                        withAttributes: [.font: font]
                    ).width
                )
                senderLabel.frame = CGRect(
                    x: body.minX + 7,
                    y: body.minY + 7,
                    width: min(max(24, textWidth + 10), max(24, body.width - 14)),
                    height: 18
                )
            } else {
                senderLabel.frame = CGRect(
                    x: body.minX + WhatsAppChatLayout.bubblePadH,
                    y: body.minY + WhatsAppChatLayout.bubblePadV,
                    width: max(
                        0,
                        body.width - WhatsAppChatLayout.bubblePadH * 2
                    ),
                    height: WhatsAppChatLayout.senderHeight
                )
            }
        }
        let contentBody: CGRect
        if isFile {
            let top = model.senderName.isEmpty
                ? body.minY + 2
                : body.minY + WhatsAppChatLayout.bubblePadV
                    + WhatsAppChatLayout.senderHeight
            contentBody = CGRect(
                x: body.minX,
                y: top,
                width: body.width,
                height: max(
                    1,
                    body.maxY - top - WhatsAppChatLayout.metadataHeight - 8
                )
            )
        } else {
            contentBody = body
        }
        if case .images(let paths) = model.kind {
            layoutImageGrid(paths: paths, in: body)
        } else {
            imageView.frame = body
        }

        let playSide: CGFloat = 44
        playView.frame = CGRect(
            x: body.midX - playSide / 2,
            y: body.midY - playSide / 2,
            width: playSide,
            height: playSide
        )
        durationLabel.frame = CGRect(x: body.minX + 7, y: body.maxY - 24,
                                     width: 38, height: 18)
        if case .images = model.kind {
            // The mosaic owns the badge frame because it covers the final tile.
        } else {
            badgeLabel.frame = CGRect(x: body.maxX - 32, y: body.maxY - 32,
                                      width: 26, height: 24)
        }

        fileIcon.frame = CGRect(x: contentBody.minX + 12,
                                y: contentBody.midY - 20,
                                width: 40, height: 40)
        let textX = fileIcon.frame.maxX + 11
        titleLabel.frame = CGRect(
            x: textX,
            y: contentBody.midY - 18,
            width: max(20, contentBody.maxX - textX - 14),
            height: 21
        )
        detailLabel.frame = CGRect(
            x: textX,
            y: contentBody.midY + 3,
            width: max(20, contentBody.maxX - textX - 14),
            height: 17
        )
        let metaWidth = WhatsAppChatLayout.metadataWidth(
            time: model.metaText,
            tickCount: model.tickCount
        )
        metadata.frame = CGRect(
            x: body.maxX - 7 - metaWidth,
            y: body.maxY - (overlaySender ? 22 : 15),
            width: metaWidth,
            height: overlaySender ? 16 : WhatsAppChatLayout.metadataHeight
        )
    }

    private func layoutImageGrid(paths: [String], in body: CGRect) {
        let views = [imageView] + extraImageViews
        let visible = MultiImageMosaic.visibleCount(for: paths.count)
        let frames = MultiImageMosaic.frames(count: paths.count, in: body)
        for (index, view) in views.enumerated() {
            guard index < visible, index < frames.count else {
                view.isHidden = true
                continue
            }
            view.isHidden = false
            let frame = frames[index]
            view.frame = frame
            view.layer.cornerRadius = min(12, min(frame.width, frame.height) * 0.18)
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
        }

        if paths.count > visible, let last = frames.last {
            badgeLabel.isHidden = false
            badgeLabel.text = "+\(paths.count - visible)"
            badgeLabel.font = pfUIFont(20, .semibold)
            badgeLabel.textColor = .white
            badgeLabel.textAlignment = .center
            badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.34)
            badgeLabel.layer.cornerRadius = min(12, min(last.width, last.height) * 0.18)
            badgeLabel.layer.cornerCurve = .continuous
            badgeLabel.clipsToBounds = true
            badgeLabel.frame = last
        } else {
            badgeLabel.isHidden = true
        }
    }

    static func height(for model: NativeChatMediaRowModel, width: CGFloat) -> CGFloat {
        let available = max(1, width - model.horizontalMargin * 2)
        let bubbleWidth = bubbleWidth(for: model, available: available)
        return bubbleHeight(for: model, width: bubbleWidth) + model.bottomGap
    }

    private static func bubbleWidth(for model: NativeChatMediaRowModel,
                                    available: CGFloat) -> CGFloat {
        let tail: CGFloat = model.showTail ? WhatsAppChatLayout.tailInset : 0
        let avatarReserve = model.reservesAvatarSpace
            ? model.avatarSize + model.avatarGap
            : 0
        let usable = max(80, min(model.maxBubbleWidth,
                                 available - avatarReserve))
        switch model.kind {
        case .image(_, let pixel):
            let thumb: CGSize
            if pixel.width > 1, pixel.height > 1 {
                thumb = ImageBubble.looksLikeSticker(pixel)
                    ? CGSize(width: 120, height: 120)
                    : ImageBubble.thumb(pixel)
            } else {
                thumb = CGSize(width: 150, height: 150)
            }
            return min(usable, thumb.width + tail)
        case .images:
            return min(usable, 229 + tail)
        case .video(_, _, let w, let h):
            let size = videoBubbleSize(w: w, h: h)
            return min(usable, size.width + tail)
        case .file:
            return min(224 + tail, usable)
        }
    }

    private static func bubbleHeight(for model: NativeChatMediaRowModel,
                                     width: CGFloat) -> CGFloat {
        switch model.kind {
        case .image(_, let pixel):
            guard pixel.width > 1, pixel.height > 1 else { return 150 }
            return ImageBubble.looksLikeSticker(pixel)
                ? 120
                : ImageBubble.thumb(pixel).height
        case .images(let paths):
            return MultiImageMosaic
                .containerSize(for: paths.count, width: 229)
                .height
        case .video(_, _, let w, let h):
            return videoBubbleSize(w: w, h: h).height
        case .file:
            return 86 + (model.senderName.isEmpty
                ? 0
                : WhatsAppChatLayout.senderHeight + 3)
        }
    }

    private static func byteText(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(max(0, bytes)) B"
    }

    private static func fileSymbol(name: String, path: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z": return "archivebox.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.on.rectangle.fill"
        case "mp3", "m4a", "wav": return "waveform"
        case "mp4", "mov": return "video.fill"
        default: return path.isEmpty ? "doc.fill" : "doc.fill"
        }
    }
}
