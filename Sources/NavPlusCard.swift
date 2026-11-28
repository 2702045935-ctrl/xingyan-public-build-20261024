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

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.accessibilityLabel = title
        button.accessibilityHint = Tr("轻点打开菜单")
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = tint
        configuration.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.configuration = configuration
        button.accessibilityLabel = title
        button.accessibilityHint = Tr("轻点打开菜单")
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
