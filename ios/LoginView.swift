import SwiftUI

struct LoginView: View {
    @ObservedObject var auth = WalletQuickAuth.shared

    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""

    @State private var wallet: String = ""
    @State private var status: String = "Open Phantom to copy your wallet address, then paste it below to link your wallet."
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // 🦆 Quack Logo
            Image("quack")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .padding(.top, 20)
            Text("Login")
                .font(.largeTitle.bold())

            Text("Link your Solana wallet to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            // 🔑 Phantom quick-launch button (for convenience)
            WalletConnectButton()

            Divider().padding(.vertical, 4)

            // Wallet input
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallet Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Paste Solana wallet (base58)", text: $wallet)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    Button("Clear") {
                        wallet = ""
                    }
                    .buttonStyle(.bordered)
                }

                if !solanaPublicKey.isEmpty {
                    Text("Currently linked: \(shortKey(solanaPublicKey))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            Button {
                hideKeyboard()
                linkSolanaWallet()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                    }
                    Text(isLoading ? "Linking..." : "Link Solana Wallet")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || wallet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !solanaPublicKey.isEmpty {
                Button(role: .destructive) {
                    solanaPublicKey = ""
                    status = "Wallet unlinked."
                } label: {
                    Text("Unlink")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider().padding(.vertical, 8)

            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding()
        .navigationTitle("Login")
        .onAppear {
            // Pre-fill input with linked wallet if present
            if !solanaPublicKey.isEmpty && wallet.isEmpty {
                wallet = solanaPublicKey
                status = "Wallet already linked. You can replace it and link again if needed."
            }
        }
    }

    // MARK: - Link

    private func linkSolanaWallet() {
        let trimmed = wallet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Please paste your wallet address first."
            return
        }

        isLoading = true
        status = "Linking wallet…"

        // Keep it simple: store locally (no network)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.solanaPublicKey = trimmed
            self.isLoading = false
            self.status = "✅ Linked wallet: \(self.shortKey(trimmed))"
        }
    }

    // MARK: - Helpers

    private func shortKey(_ key: String) -> String {
        guard key.count > 10 else { return key }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
    }
}
// MARK: - WalletConnectButton (opens Phantom)

struct WalletConnectButton: View {
    @ObservedObject var auth = WalletQuickAuth.shared

    var body: some View {
        HStack {
            Text("Phantom Wallet")
                .font(.headline)
            Spacer()
            Button {
                auth.connect()   // opens Phantom (universal link / deep link)
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open Phantom")
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
