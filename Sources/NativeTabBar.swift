import SwiftUI
import UIKit

/// 只替换底栏；页面、顶栏、导航和键盘布局继续使用 B2103 原实现。
struct NativeTabBar: UIViewRepresentable {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
    let badge: Int
    let contactsDot: Bool
    let momentsDot: Bool
    let meDot: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.items = [
            UITabBarItem(title: C.tabText0, image: UIImage(systemName: "message"),
                         selectedImage: UIImage(systemName: "message.fill")),
            UITabBarItem(title: C.tabText1, image: UIImage(systemName: "person.2"),
                         selectedImage: UIImage(systemName: "person.2.fill")),
            UITabBarItem(title: C.tabText2, image: UIImage(systemName: "safari"),
                         selectedImage: UIImage(systemName: "safari")),
            UITabBarItem(title: C.tabText3, image: UIImage(systemName: "person.crop.circle"),
                         selectedImage: UIImage(systemName: "person.crop.circle.fill"))
        ]
        applyColors(bar)
        refresh(bar)
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        _ = scheme
        applyColors(bar)
        if let item = bar.items?[safe: selection], bar.selectedItem !== item {
            bar.selectedItem = item
        }
        refresh(bar)
    }

    private func applyColors(_ bar: UITabBar) {
        bar.tintColor = UIColor(C.green)
        bar.unselectedItemTintColor = UIColor(C.subLabel)
    }

    private func refresh(_ bar: UITabBar) {
        guard let items = bar.items, items.count == 4 else { return }
        items[0].badgeValue = badge > 0 ? (badge > 99 ? "99+" : "\(badge)") : nil
        items[1].badgeValue = contactsDot ? "●" : nil
        items[2].badgeValue = momentsDot ? "●" : nil
        items[3].badgeValue = meDot ? "●" : nil
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<Int>

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
            selection.wrappedValue = index
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
