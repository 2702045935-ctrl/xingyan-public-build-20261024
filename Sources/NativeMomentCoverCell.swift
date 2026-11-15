import SwiftUI
import UIKit

struct NativeMomentCoverConfiguration {
    let width: CGFloat
    let height: CGFloat
    let coverPath: String
    let showsSetup: Bool
    let showsChange: Bool
    let ownerName: String
    let avatarPath: String
    let signature: String?
    let isDark: Bool
    let onToggleLock: () -> Void
    let onSetCover: () -> Void
    let onChangeCover: () -> Void
}

final class NativeMomentCoverCell: UICollectionViewCell {
    static func preferredHeight(_ configuration: NativeMomentCoverConfiguration) -> CGFloat {
        max(1, configuration.height)
    }

    private let fallbackView = UIView()
    private let fallbackGradient = CAGradientLayer()
    private let fallbackImage = UIImageView(image: UIImage(named: "moments-cover"))
    private let coverImage = NativeMomentImage()
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()
    private let setupPanel = UIView()
    private let setupIconBackground = UIView()
    private let setupIcon = UIImageView(image: UIImage(systemName: "photo.badge.plus"))
    private let setupTitle = UILabel()
    private let setupSubtitle = UILabel()
    private let setupButton = UIButton(type: .system)
    private let changeButton = UIButton(type: .system)
    private let nameLabel = UILabel()
    private let avatarImage = NativeMomentImage()
    private let avatarFallback = UILabel()
    private let signatureLabel = UILabel()
    private var configuration: NativeMomentCoverConfiguration?

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
        coverImage.reset()
        avatarImage.reset()
    }

    func configure(_ configuration: NativeMomentCoverConfiguration) {
        self.configuration = configuration
        contentView.backgroundColor = UIColor(C.pageBg)

        let hasCover = !configuration.coverPath.isEmpty
        fallbackView.isHidden = hasCover
        fallbackImage.isHidden = hasCover || fallbackImage.image == nil
        coverImage.isHidden = !hasCover
        if hasCover {
            coverImage.set(path: configuration.coverPath, maxSide: 2560)
        } else {
            coverImage.reset()
        }

        let setupVisible = !hasCover && configuration.showsSetup
        setupPanel.isHidden = !setupVisible
        changeButton.isHidden = !hasCover || !configuration.showsChange

        nameLabel.text = configuration.ownerName
        avatarImage.set(path: configuration.avatarPath, maxSide: 160)
        avatarFallback.text = String(configuration.ownerName.prefix(1))
        avatarFallback.isHidden = !configuration.avatarPath.isEmpty
        let signature = (configuration.signature ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        signatureLabel.text = signature
        signatureLabel.isHidden = signature.isEmpty

        let dark = configuration.isDark
        topGradient.colors = dark
            ? [UIColor.black.withAlphaComponent(0.96).cgColor,
               UIColor.black.withAlphaComponent(0.70).cgColor,
               UIColor.clear.cgColor]
            : [UIColor.black.withAlphaComponent(UIConfig.num("momentTopMask", 0.20)).cgColor,
               UIColor.clear.cgColor]
        bottomGradient.colors = dark
            ? [UIColor.clear.cgColor,
               UIColor.black.withAlphaComponent(0.78).cgColor,
               UIColor.black.withAlphaComponent(0.96).cgColor]
            : [UIColor.clear.cgColor,
               UIColor.black.withAlphaComponent(0.22).cgColor,
               UIColor.black.withAlphaComponent(0.36).cgColor]
        signatureLabel.backgroundColor = UIColor(white: dark ? 0 : 1, alpha: 0.62)
        signatureLabel.textColor = UIColor(C.label)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration else { return }
        let width = bounds.width
        let height = configuration.height

        fallbackView.frame = bounds
        fallbackGradient.frame = fallbackView.bounds
        fallbackImage.frame = fallbackView.bounds
        coverImage.frame = bounds
        coverImage.layer.cornerRadius = 0

        let topHeight = max(L.safeTop + 56, UIConfig.num("momentTopMaskH", 150))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topGradient.frame = CGRect(x: 0, y: 0, width: width, height: topHeight)
        topGradient.locations = configuration.isDark ? [0, 0.62, 1] : [0, 1]
        let bottomHeight = L.coverH * 0.62
        bottomGradient.frame = CGRect(x: 0, y: max(0, height - bottomHeight),
                                      width: width, height: bottomHeight)
        bottomGradient.locations = configuration.isDark ? [0, 0.42, 1] : [0, 0.42, 1]
        CATransaction.commit()

        let panelWidth = min(286, max(1, width - 48))
        let panelHeight: CGFloat = 206
        setupPanel.frame = CGRect(x: (width - panelWidth) / 2,
                                  y: max(0, (height - panelHeight) / 2),
                                  width: panelWidth, height: panelHeight)
        setupPanel.layer.cornerRadius = 22
        setupIconBackground.frame = CGRect(x: (panelWidth - 46) / 2, y: 18,
                                           width: 46, height: 46)
        setupIconBackground.layer.cornerRadius = 23
        setupIcon.frame = CGRect(x: 12, y: 12, width: 22, height: 22)
        setupTitle.frame = CGRect(x: 12, y: 74, width: panelWidth - 24, height: 22)
        setupSubtitle.frame = CGRect(x: 12, y: 101, width: panelWidth - 24, height: 38)
        setupButton.frame = CGRect(x: (panelWidth - 118) / 2, y: 151,
                                   width: 118, height: 38)
        setupButton.layer.cornerRadius = 19

        changeButton.frame = CGRect(x: 12, y: max(0, height - 44),
                                    width: 88, height: 32)
        changeButton.layer.cornerRadius = 16

        let avatarSize = L.coverAvatar
        let signatureText = signatureLabel.isHidden ? "" : (signatureLabel.text ?? "")
        let signatureHeight: CGFloat = signatureText.isEmpty
            ? 0
            : min(42, ceil((signatureText as NSString).boundingRect(
                with: CGSize(width: avatarSize + 56, height: 42),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: signatureLabel.font as Any],
                context: nil
            ).height) + 7)
        let profileBottom = height - 10
        if signatureHeight > 0 {
            signatureLabel.frame = CGRect(x: width - 16 - avatarSize - 28,
                                          y: profileBottom - signatureHeight,
                                          width: avatarSize + 56,
                                          height: signatureHeight)
            signatureLabel.layer.cornerRadius = 6
            avatarImage.frame = CGRect(x: width - 16 - avatarSize,
                                       y: signatureLabel.frame.minY - 4 - avatarSize,
                                       width: avatarSize, height: avatarSize)
        } else {
            avatarImage.frame = CGRect(x: width - 16 - avatarSize,
                                       y: profileBottom - avatarSize,
                                       width: avatarSize, height: avatarSize)
        }
        avatarImage.layer.cornerRadius = 8
        avatarFallback.frame = avatarImage.frame
        avatarFallback.layer.cornerRadius = 8
        nameLabel.frame = CGRect(x: max(16, width - 16 - 220),
                                 y: profileBottom - 24 - 22,
                                 width: min(220, width - 32), height: 22)
    }

    private func setupViews() {
        contentView.clipsToBounds = true
        clipsToBounds = true

        fallbackGradient.colors = [
            UIColor(hex: 0x0D3B66).cgColor,
            UIColor(hex: 0x1D6FB8).cgColor,
            UIColor(hex: 0x0099FF).cgColor
        ]
        fallbackGradient.startPoint = CGPoint(x: 0, y: 0)
        fallbackGradient.endPoint = CGPoint(x: 1, y: 1)
        fallbackView.layer.addSublayer(fallbackGradient)
        fallbackImage.contentMode = .scaleAspectFill
        fallbackImage.clipsToBounds = true
        fallbackView.addSubview(fallbackImage)
        contentView.addSubview(fallbackView)

        coverImage.clipsToBounds = true
        contentView.addSubview(coverImage)

        topGradient.startPoint = CGPoint(x: 0.5, y: 0)
        topGradient.endPoint = CGPoint(x: 0.5, y: 1)
        bottomGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bottomGradient.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(topGradient)
        contentView.layer.addSublayer(bottomGradient)

        setupPanel.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        setupPanel.layer.cornerRadius = 22
        setupPanel.layer.borderWidth = 0.7
        setupPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        setupIconBackground.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        setupIconBackground.layer.cornerRadius = 23
        setupIcon.tintColor = .white
        setupIcon.contentMode = .scaleAspectFit
        setupIconBackground.addSubview(setupIcon)
        setupPanel.addSubview(setupIconBackground)

        setupTitle.text = Tr("设置生活圈封面")
        setupTitle.font = pfUIFont(16.5, .semibold)
        setupTitle.textColor = .white
        setupTitle.textAlignment = .center
        setupPanel.addSubview(setupTitle)

        setupSubtitle.text = Tr("从相册选一张图，让朋友一眼记住你")
        setupSubtitle.font = pfUIFont(12.2)
        setupSubtitle.textColor = UIColor.white.withAlphaComponent(0.82)
        setupSubtitle.textAlignment = .center
        setupSubtitle.numberOfLines = 2
        setupPanel.addSubview(setupSubtitle)

        setupButton.setTitle(Tr("立即设置"), for: .normal)
        setupButton.titleLabel?.font = pfUIFont(14.5, .semibold)
        setupButton.setTitleColor(.white, for: .normal)
        setupButton.backgroundColor = UIColor(C.green).withAlphaComponent(0.92)
        setupButton.layer.borderWidth = 0.8
        setupButton.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        setupButton.addAction(
            UIAction { [weak self] _ in self?.configuration?.onSetCover() },
            for: .touchUpInside
        )
        setupPanel.addSubview(setupButton)
        contentView.addSubview(setupPanel)

        changeButton.setTitle(Tr("换封面"), for: .normal)
        changeButton.titleLabel?.font = pfUIFont(12.5, .medium)
        changeButton.setTitleColor(.white, for: .normal)
        changeButton.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        changeButton.layer.borderWidth = 0.7
        changeButton.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        changeButton.addAction(
            UIAction { [weak self] _ in self?.configuration?.onChangeCover() },
            for: .touchUpInside
        )
        contentView.addSubview(changeButton)

        nameLabel.font = pfUIFont(17, .semibold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .right
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.layer.shadowColor = UIColor.black.withAlphaComponent(0.55).cgColor
        nameLabel.layer.shadowRadius = 4
        nameLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        contentView.addSubview(nameLabel)

        avatarFallback.font = pfUIFont(20, .semibold)
        avatarFallback.textColor = UIColor(C.label)
        avatarFallback.textAlignment = .center
        avatarFallback.backgroundColor = UIColor(C.pageBg)
        avatarFallback.clipsToBounds = true
        contentView.addSubview(avatarImage)
        contentView.addSubview(avatarFallback)

        signatureLabel.font = pfUIFont(12.5)
        signatureLabel.textAlignment = .center
        signatureLabel.numberOfLines = 2
        signatureLabel.lineBreakMode = .byTruncatingTail
        signatureLabel.clipsToBounds = true
        contentView.addSubview(signatureLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(coverTapped(_:)))
        tap.cancelsTouchesInView = false
        contentView.addGestureRecognizer(tap)
    }

    @objc private func coverTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: contentView)
        if setupButton.frame.contains(convert(point, to: setupPanel))
            || changeButton.frame.contains(point) {
            return
        }
        configuration?.onToggleLock()
    }
}
