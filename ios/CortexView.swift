
import SwiftUI
import Foundation

struct CortexView: View {
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""

    @State private var insight: String = ""
    @State private var status: String = ""
    @State private var isLoading: Bool = false

    // ✅ backend on LAN
    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    var body: some View {
        VStack(spacing: 16) {
            Text("Cortex AI")
                .font(.largeTitle.bold())

            Text("Insight generated inside Snowflake using Cortex SQL.")
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
                        Task { await loadCortexInsight() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView() }
                            Text(isLoading ? "Loading..." : "Generate Insight")
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
                            Text(isLoading ? "Thinking…" : "Tap “Generate Insight” to run Cortex.")
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
        .navigationTitle("Cortex")
    }

    private func loadCortexInsight() async {
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wallet.isEmpty else {
            status = "Missing wallet."
            return
        }

        isLoading = true
        status = "Running Snowflake Cortex…"
        defer { isLoading = false }

        do {
            let text = try await fetchCortexInsight(wallet: wallet, limit: 120)
            insight = text
            status = "✅ Updated"
        } catch {
            status = "❌ \(error.localizedDescription)"
        }
    }

    private func fetchCortexInsight(wallet: String, limit: Int) async throws -> String {
        let url = backendBaseURL.appendingPathComponent("ai/cortex/vitals-insight")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["wallet": wallet, "limit": limit]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "CortexView", code: code, userInfo: [
                NSLocalizedDescriptionKey: "Server error \(code): \(msg)"
            ])
        }

        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["ok"] as? Bool) == true
        else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "CortexView", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected response: \(txt)"
            ])
        }

        return (obj["insight"] as? String) ?? "(no insight returned)"
    }
}
