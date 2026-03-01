import SwiftUI
import Foundation

struct AIView: View {
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""

    @State private var insight: String = ""
    @State private var status: String = ""
    @State private var isLoading: Bool = false

    // ✅ Your backend on Mac LAN
    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    var body: some View {
        VStack(spacing: 16) {
            Text("Quack AI")
                .font(.largeTitle.bold())

            Text("AI insight based on your latest vitals stored in Snowflake.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            Divider()

            if solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Please link/paste your Solana wallet address first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Button {
                        Task { await loadInsight() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView() }
                            Text(isLoading ? "Loading..." : "Refresh Insight")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Spacer()

                    Button("Clear") {
                        insight = ""
                        status = ""
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !insight.isEmpty {
                            Text(insight)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Text(isLoading ? "Thinking…" : "Tap “Refresh Insight” to generate an insight.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }

                        if !status.isEmpty {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("AI")
        .task {
            // auto-load once if wallet exists
            if !solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await loadInsight()
            }
        }
    }

    // MARK: - Networking

    private func loadInsight() async {
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wallet.isEmpty else {
            status = "Missing wallet."
            return
        }

        isLoading = true
        status = "Contacting AI…"
        defer { isLoading = false }

        do {
            let text = try await fetchVitalsInsight(wallet: wallet, limit: 120)
            insight = text
            status = "✅ Updated"
        } catch {
            status = "❌ \(error.localizedDescription)"
        }
    }

    private func fetchVitalsInsight(wallet: String, limit: Int) async throws -> String {
        let url = backendBaseURL.appendingPathComponent("ai/vitals-insight")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "wallet": wallet,
            "limit": limit
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AIView", code: code, userInfo: [
                NSLocalizedDescriptionKey: "Server error \(code): \(msg)"
            ])
        }

        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ok = obj["ok"] as? Bool,
            ok == true
        else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AIView", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected response: \(txt)"
            ])
        }

        return (obj["insight"] as? String) ?? "(no insight returned)"
    }
}
