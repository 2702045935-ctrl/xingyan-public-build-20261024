import SwiftUI
import UIKit

/// Re-enables UIKit's edge-pop recognizer when a screen hides the navigation
/// bar. Screens that use this bridge must not also install a custom swipe-back
/// recognizer, otherwise both gestures can compete for the same first pixels.
struct NativeInteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.attach()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var attachedNavigation: UINavigationController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            attach()
        }

        func attach() {
            guard let navigation = navigationController ?? parent?.navigationController else {
                return
            }
            attachedNavigation = navigation
            guard let gesture = navigation.interactivePopGestureRecognizer else {
                return
            }
            gesture.delegate = self
            gesture.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation = attachedNavigation ?? navigationController else {
                return false
            }
            return navigation.viewControllers.count > 1
                && !navigation.isTransitioning
        }

    }
}

private extension UINavigationController {
    var isTransitioning: Bool {
        transitionCoordinator?.isAnimated == true
    }
}
