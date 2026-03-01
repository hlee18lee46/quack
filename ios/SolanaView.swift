


import SwiftUI

struct SolanaView: View {
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""
    @State private var samples: [SFVitalsSample] = []
    @State private var status: String = "Ready to anchor data."
    @State private var isAnchoring = false
    @State private var lastSignature: String?

    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                // 1. "On-Chain Certificate" Preview
                VStack(spacing: 15) {
                    Image(systemName: "link.icloud.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.purple)
                    
                    Text("Vital Sign Certificate")
                        .font(.title2.bold())
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Avg Heart Rate").font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(calculateAvgHR())) BPM").font(.title3.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Avg Breathing").font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(calculateAvgBR())) RPM").font(.title3.bold())
                        }
                    }
                    .padding(.horizontal)
                    
                    Text("Wallet: \(shortKey(solanaPublicKey))")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).stroke(Color.purple.opacity(0.5), lineWidth: 2))
                .padding()

                // 2. Action Button
                Button {
                    Task { await anchorVitals() }
                } label: {
                    HStack {
                        if isAnchoring { ProgressView().padding(.trailing, 8) }
                        Text(isAnchoring ? "Committing to Memo..." : "Anchor to Solana Devnet")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(solanaPublicKey.isEmpty ? Color.gray : Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isAnchoring || solanaPublicKey.isEmpty)
                .padding(.horizontal)

                // 3. Signature Result
                if let sig = lastSignature {
                    Link(destination: URL(string: "https://explorer.solana.com/tx/\(sig)?network=devnet")!) {
                        HStack {
                            Text("View on Solscan")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }

                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()

                Spacer()
            }
            .navigationTitle("Solana Proof")
            .onAppear { fetchVitals() } // Load the data to anchor when view appears
        }
    }

    // MARK: - Logic Helpers

    func calculateAvgHR() -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map { $0.hr_bpm }.reduce(0, +) / Double(samples.count)
    }

    func calculateAvgBR() -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map { $0.br_rpm }.reduce(0, +) / Double(samples.count)
    }

    private func shortKey(_ s: String) -> String {
        guard s.count > 10 else { return "No Wallet" }
        return "\(s.prefix(6))...\(s.suffix(6))"
    }

    // MARK: - Networking

    func fetchVitals() {
        // We reuse your existing fetch logic or pass data from the other view
        // For simplicity, this view calls the same Snowflake API
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespaces)
        guard !wallet.isEmpty else { return }

        var comps = URLComponents(url: backendBaseURL.appendingPathComponent("api/vitals"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "wallet", value: wallet), URLQueryItem(name: "limit", value: "50")]
        
        URLSession.shared.dataTask(with: comps.url!) { data, _, _ in
            if let data = data, let decoded = try? JSONDecoder().decode(SFVitalsResponse.self, from: data) {
                DispatchQueue.main.async { self.samples = decoded.vitals }
            }
        }.resume()
    }

    func anchorVitals() async {
        isAnchoring = true
        status = "Broadcasting to Solana..."
        
        let avgHR = calculateAvgHR()
        let avgBR = calculateAvgBR()
        
        let payload: [String: Any] = [
            "name": "Quack Vitals Proof",
            "artist": solanaPublicKey,
            "bpm": Int(avgHR),
            "key": "BR: \(Int(avgBR))",
            "audio_url": "https://quack-demo.com/proof/\(solanaPublicKey)"
        ]

        var request = URLRequest(url: backendBaseURL.appendingPathComponent("solana/devnet/publish-metadata"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("69420", forHTTPHeaderField: "ngrok-skip-browser-warning")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sig = json["signature"] as? String {
                    lastSignature = sig
                    status = "✅ Transaction Confirmed!"
                }
            } else {
                status = "❌ Failed to anchor."
            }
        } catch {
            status = "❌ Error: \(error.localizedDescription)"
        }
        isAnchoring = false
    }
}
