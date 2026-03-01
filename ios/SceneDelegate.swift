import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let winScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: winScene)
        window.rootViewController = UIHostingController(rootView: RootTabsView())
        self.window = window
        window.makeKeyAndVisible()
    }

    // Handle Phantom wallet callback: vitalsdemo://phantom-callback?public_key=...
    func scene(_ scene: UIScene,
               openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

        if url.absoluteString.hasPrefix("vitalsdemo://phantom-callback") {
            WalletQuickAuth.shared.handleCallback(url)
        }
    }
}
