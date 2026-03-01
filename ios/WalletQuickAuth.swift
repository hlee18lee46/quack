// WalletQuickAuth.swift

import SwiftUI
import UIKit

final class WalletQuickAuth: ObservableObject {
    static let shared = WalletQuickAuth()

    @Published var publicKey: String? {
        didSet {
            if let pk = publicKey {
                UserDefaults.standard.set(pk, forKey: "wallet")
            } else {
                UserDefaults.standard.removeObject(forKey: "wallet")
            }
        }
    }

    // Must match your URL Scheme in Xcode → Target → Info → URL Types
    private let callback = "vitalsdemo://phantom-callback"

    init() {
        // Restore saved wallet (if any)
        if let saved = UserDefaults.standard.string(forKey: "wallet") {
            self.publicKey = saved
        }
    }

    /// Open Phantom and ask the user to sign a short message.
    /// Phantom will return public_key + signature + message to our callback URL.
    func connect() {
        let message = "Login to SmartSpectra • \(Int(Date().timeIntervalSince1970))"
        let encodedMsg = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Phantom universal link (works on iOS with Phantom installed)
        let urlStr = "https://phantom.app/ul/v1/signMessage?message=\(encodedMsg)&redirect_link=\(callback)"
        guard let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    /// Handle the callback from Phantom and extract the public key.
    /// Expect: vitalsdemo://phantom-callback?public_key=...&signature=...&message=...
    func handleCallback(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let q = comps.queryItems else { return }

        let pk = q.first(where: { $0.name == "public_key" })?.value
        // If you want later: let sig = q.first(where: { $0.name == "signature" })?.value
        //                    let msg = q.first(where: { $0.name == "message" })?.value

        DispatchQueue.main.async {
            self.publicKey = pk
        }
    }

    /// Clear the current wallet and remove it from storage.
    func disconnect() {
        publicKey = nil
    }
}
