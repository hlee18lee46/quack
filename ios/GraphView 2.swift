import SwiftUI
import Charts
import Foundation

// MARK: - Models (renamed to avoid collisions)

struct SFVitalsSample2: Identifiable, Decodable {
    let id = UUID()

    let wallet: String
    let ts_ms: Int
    let hr_bpm: Double
    let br_rpm: Double
    let mode: String?
    let created_at: String?

    private enum CodingKeys: String, CodingKey {
        case wallet, ts_ms, hr_bpm, br_rpm, mode, created_at
    }

    var date: Date {
        Date(timeIntervalSince1970: Double(ts_ms) / 1000.0)
    }
}

struct SFVitalsResponse2: Decodable {
    let ok: Bool
    let vitals: [SFVitalsSample]
}

// MARK: - View

struct GraphView2: View {
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""

    @State private var samples: [SFVitalsSample] = []
    @State private var status: String = ""
    @State private var isLoading = false

    // ✅ LAN backend (your Mac)
    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Vitals (Snowflake)")
                    .font(.title2.bold())
                Spacer()
                Button(isLoading ? "Loading..." : "Refresh") {
                    Task { await fetchVitals() }
                }
                .disabled(isLoading)
                .buttonStyle(.bordered)
            }

            if samples.isEmpty {
                Text(isLoading ? "Loading…" : "No data yet. Upload first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let ordered = samples.sorted { $0.ts_ms < $1.ts_ms }

                Chart(ordered) { s in
                    LineMark(
                        x: .value("Time", s.date),
                        y: .value("HR", s.hr_bpm)
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", s.date),
                        y: .value("BR", s.br_rpm)
                    )
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 260)
            }

            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding()
        .navigationTitle("Graph")
        .task { await fetchVitals() }
    }

    // MARK: - Networking

    private func fetchVitals() async {
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wallet.isEmpty else {
            status = "Please link/paste your wallet address first."
            samples = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        // GET /api/vitals?wallet=...&limit=300
        let endpoint = backendBaseURL.appendingPathComponent("api/vitals")
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "wallet", value: wallet),
            URLQueryItem(name: "limit", value: "300")
        ]

        guard let url = comps.url else {
            status = "Bad URL."
            return
        }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

            guard (200..<300).contains(code) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                status = "Server error \(code): \(body)"
                return
            }

            let decoded = try JSONDecoder().decode(SFVitalsResponse.self, from: data)
            samples = decoded.vitals
            status = "Loaded \(samples.count) points from Snowflake."
        } catch {
            status = "Fetch failed: \(error.localizedDescription)"
        }
    }
}
