// DisableInteractivePopGesture.swift
// Turns off the system swipe-back gesture on map screens. A finger exploring
// the left edge of a map would otherwise pull the screen away. Back stays
// available through the navigation bar button and the map's own gestures.

import SwiftUI
import UIKit

extension View {
    func disableInteractivePopGesture() -> some View {
        background(PopGestureDisabler().frame(width: 0, height: 0))
    }
}

/// Refuses every interactive pop gesture it is the delegate of.
final class PopGestureBlocker: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureBlocker()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    static func install(on navigationController: UINavigationController) {
        var recognizers: [UIGestureRecognizer] = []
        if let edge = navigationController.interactivePopGestureRecognizer {
            recognizers.append(edge)
        }
        // iOS 18 and later also pop on a swipe from anywhere on the screen.
        let selector = NSSelectorFromString("interactiveContentPopGestureRecognizer")
        if navigationController.responds(to: selector),
           let content = navigationController.perform(selector)?.takeUnretainedValue() as? UIGestureRecognizer {
            recognizers.append(content)
        }
        for recognizer in recognizers {
            recognizer.delegate = shared
        }
    }
}

private struct PopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DisablerController {
        DisablerController()
    }

    func updateUIViewController(_ controller: DisablerController, context: Context) {
        controller.apply()
    }

    final class DisablerController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
            // SwiftUI can attach the navigation controller just after appearing.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            if let navigationController = findNavigationController() {
                PopGestureBlocker.install(on: navigationController)
            }
        }

        private func findNavigationController() -> UINavigationController? {
            if let navigationController { return navigationController }
            var ancestor = parent
            while let current = ancestor {
                if let nav = current as? UINavigationController { return nav }
                if let nav = current.navigationController { return nav }
                ancestor = current.parent
            }
            return search(view.window?.rootViewController)
        }

        private func search(_ controller: UIViewController?) -> UINavigationController? {
            guard let controller else { return nil }
            if let nav = controller as? UINavigationController { return nav }
            for child in controller.children {
                if let nav = search(child) { return nav }
            }
            return search(controller.presentedViewController)
        }
    }
}
