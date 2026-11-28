import SwiftUI
import UIKit

struct NativeNavMenuAction {
    let id: String
    let title: String
    let symbol: String
    let destructive: Bool
    let action: () -> Void

    init(id: String,
         title: String,
         symbol: String,
         destructive: Bool = false,
         action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.destructive = destructive
        self.action = action
    }
}

struct NativeNavMenuButton: UIViewRepresentable {
    let title: String
    let symbol: String
    let tint: UIColor
    let items: [NativeNavMenuAction]
    var showsGlassBackground = true

    func makeUIView(context: Context) -> NativeNavMenuControl {
        let button = NativeNavMenuControl()
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.accessibilityLabel = title
        button.accessibilityHint = Tr("轻点打开菜单")
        return button
    }

    func updateUIView(_ button: NativeNavMenuControl, context: Context) {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = tint
        configuration.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.configuration = configuration
        button.accessibilityLabel = title
        button.accessibilityHint = Tr("轻点打开菜单")
        button.setGlassBackground(showsGlassBackground)
        button.menu = UIMenu(
            title: "",
            preferredElementSize: .medium,
            children: items.map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.symbol),
                    identifier: UIAction.Identifier(item.id),
                    attributes: item.destructive ? [.destructive] : []
                ) { _ in
                    item.action()
                }
            }
        )
    }
}

final class NativeNavMenuControl: UIButton {
    private let glassView = UIVisualEffectView(effect: nil)
    private var wantsGlass = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        glassView.isUserInteractionEnabled = false
        glassView.clipsToBounds = true
        glassView.layer.cornerCurve = .continuous
        insertSubview(glassView, at: 0)
        updateGlassEffect()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setGlassBackground(_ enabled: Bool) {
        wantsGlass = enabled
        glassView.isHidden = !enabled
        updateGlassEffect()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds.insetBy(dx: 4, dy: 4)
        glassView.layer.cornerRadius = min(glassView.bounds.width,
                                           glassView.bounds.height) / 2
        bringSubviewToFront(glassView)
        if let imageView {
            bringSubviewToFront(imageView)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateGlassEffect()
        }
    }

    private func updateGlassEffect() {
        guard wantsGlass else {
            glassView.effect = nil
            return
        }
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            glassView.effect = glass
        } else {
            glassView.effect = UIBlurEffect(
                style: traitCollection.userInterfaceStyle == .dark
                    ? .systemThinMaterialDark
                    : .systemThinMaterialLight
            )
        }
    }
}
