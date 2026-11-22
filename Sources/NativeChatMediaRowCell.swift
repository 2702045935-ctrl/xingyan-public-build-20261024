import UIKit

enum NativeChatMediaKind {
    case image(path: String, pixel: CGSize)
    case images(paths: [String])
    case video(cover: String, seconds: Int)
    case file(name: String, path: String, bytes: Int, type: String)
}

struct NativeChatMediaRowModel {
    var messageID: String
    var kind: NativeChatMediaKind
    var mine: Bool
    var senderName: String
    var senderNameColor: UIColor
    var avatarPath: String
    var avatarSize: CGFloat
    var maxBubbleWidth: CGFloat
    var horizontalMargin: CGFloat
    var avatarGap: CGFloat
    var bottomGap: CGFloat
    var primaryColor: UIColor
    var secondaryColor: UIColor
    var bubbleColor: UIColor
    var showTail: Bool
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

final class NativeChatMediaRowView: UIView {
    static let reuseID = "NativeChatMediaRowView"

    private var model: NativeChatMediaRowModel?
    private let avatar = NativeStaticAvatarView()
    private let senderLabel = UILabel()
    private let bubble = NativeChatBubbleBackground()
    private let imageView = NativeMediaImageView()
    private let fileIcon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let badgeLabel = UILabel()
    private let playView = UIImageView(image: UIImage(systemName: "play.fill"))
    private let durationLabel = UILabel()
    private var tapRecognizer: UITapGestureRecognizer?
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
        addSubview(senderLabel)
        addSubview(bubble)
        addSubview(imageView)
        addSubview(fileIcon)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(badgeLabel)
        addSubview(playView)
        addSubview(durationLabel)

        senderLabel.font = pfUIFont(12.5, .regular)
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

        imageView.layer.cornerRadius = 7
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
        avatar.configure(path: next.avatarPath, name: next.senderName)
        senderLabel.text = next.senderName
        senderLabel.textColor = next.senderNameColor
        senderLabel.textAlignment = next.mine ? .right : .left
        bubble.fillColor = next.bubbleColor
        bubble.mine = next.mine
        bubble.showTail = next.showTail

        imageView.isHidden = true
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
            badgeLabel.isHidden = paths.count < 2
            badgeLabel.text = paths.count > 1 ? "\(paths.count)" : ""
        case .video(let cover, let seconds):
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
                    onAvatar: @escaping () -> Void) {
        if tapRecognizer == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            addGestureRecognizer(tap)
            tapRecognizer = tap
        }
        if avatarRecognizer == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
            tap.cancelsTouchesInView = false
            avatar.addGestureRecognizer(tap)
            avatarRecognizer = tap
        }
        self.tapAction = onTap
        avatarAction = onAvatar
    }

    private var tapAction: (() -> Void)?
    private var avatarAction: (() -> Void)?

    @objc private func tapped() { tapAction?() }

    @objc private func avatarTapped() { avatarAction?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }
        let available = max(1, bounds.width - model.horizontalMargin * 2)
        let nameHeight: CGFloat = model.senderName.isEmpty ? 0 : 17
        let avatarX = model.mine
            ? model.horizontalMargin + available - model.avatarSize
            : model.horizontalMargin
        avatar.frame = CGRect(x: avatarX, y: nameHeight,
                              width: model.avatarSize, height: model.avatarSize)
        senderLabel.isHidden = model.senderName.isEmpty
        let nameX = model.mine
            ? model.horizontalMargin
            : model.horizontalMargin + model.avatarSize + model.avatarGap
        senderLabel.frame = CGRect(
            x: nameX,
            y: 0,
            width: max(0, available - model.avatarSize - model.avatarGap),
            height: nameHeight
        )

        let bubbleWidth = Self.bubbleWidth(for: model, available: available)
        let bubbleHeight = Self.bubbleHeight(for: model, width: bubbleWidth)
        let bubbleX = model.mine
            ? model.horizontalMargin + available - model.avatarSize - model.avatarGap - bubbleWidth
            : model.horizontalMargin + model.avatarSize + model.avatarGap
        bubble.frame = CGRect(x: bubbleX, y: nameHeight,
                              width: bubbleWidth, height: bubbleHeight)
        // Native media subviews live in the row coordinate space, not inside
        // the bubble. Anchor their body to the bubble itself and reserve the
        // tail-only strip so images and file cards cannot drift out of frame.
        let tailInset: CGFloat = model.showTail ? 6 : 0
        let body = CGRect(
            x: bubble.frame.minX + (model.mine ? 0 : tailInset),
            y: bubble.frame.minY,
            width: max(1, bubbleWidth - tailInset),
            height: bubbleHeight
        )
        imageView.frame = body

        let playSide: CGFloat = 44
        playView.frame = CGRect(
            x: body.midX - playSide / 2,
            y: body.midY - playSide / 2,
            width: playSide,
            height: playSide
        )
        durationLabel.frame = CGRect(x: body.maxX - 44, y: body.maxY - 24,
                                     width: 38, height: 18)
        badgeLabel.frame = CGRect(x: body.maxX - 32, y: body.maxY - 32,
                                  width: 26, height: 24)

        fileIcon.frame = CGRect(x: body.minX + 12, y: body.midY - 20,
                                width: 40, height: 40)
        let textX = fileIcon.frame.maxX + 11
        titleLabel.frame = CGRect(x: textX, y: body.midY - 18,
                                  width: max(20, body.maxX - textX - 14), height: 21)
        detailLabel.frame = CGRect(x: textX, y: body.midY + 3,
                                   width: max(20, body.maxX - textX - 14), height: 17)
    }

    static func height(for model: NativeChatMediaRowModel, width: CGFloat) -> CGFloat {
        let available = max(1, width - model.horizontalMargin * 2)
        let nameHeight: CGFloat = model.senderName.isEmpty ? 0 : 17
        let bubbleWidth = bubbleWidth(for: model, available: available)
        return nameHeight + bubbleHeight(for: model, width: bubbleWidth) + model.bottomGap
    }

    private static func bubbleWidth(for model: NativeChatMediaRowModel,
                                    available: CGFloat) -> CGFloat {
        switch model.kind {
        case .image(_, let pixel):
            let usable = max(100, min(model.maxBubbleWidth,
                                      available - model.avatarSize - model.avatarGap))
            guard pixel.width > 1, pixel.height > 1 else { return min(180, usable) }
            let portrait = pixel.height / max(1, pixel.width)
            return portrait > 1.2 ? min(160, usable) : usable
        case .images:
            return min(180, max(120, available - model.avatarSize - model.avatarGap))
        case .video:
            return min(220, max(170, available - model.avatarSize - model.avatarGap))
        case .file:
            return min(224, max(180, available - model.avatarSize - model.avatarGap))
        }
    }

    private static func bubbleHeight(for model: NativeChatMediaRowModel,
                                     width: CGFloat) -> CGFloat {
        switch model.kind {
        case .image(_, let pixel):
            guard pixel.width > 1, pixel.height > 1 else { return 160 }
            let ratio = pixel.height / pixel.width
            return min(230, max(96, (width - 6) * ratio))
        case .images:
            return 168
        case .video:
            return 136
        case .file:
            return 72
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
