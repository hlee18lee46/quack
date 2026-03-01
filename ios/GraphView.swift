import SwiftUI
import Charts
import Foundation
import UIKit

// MARK: - Models
struct SFVitalsSample: Identifiable, Decodable {
    let id = UUID()
    let wallet: String
    let ts_ms: Int
    let hr_bpm: Double
    let br_rpm: Double
    let mode: String?
    let created_at: String?

    var date: Date {
        Date(timeIntervalSince1970: Double(ts_ms) / 1000.0)
    }
}

struct SFVitalsResponse: Decodable {
    let ok: Bool
    let vitals: [SFVitalsSample]
}

// MARK: - View
struct GraphView: View {
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""
    @State private var emailAddress: String = "" // Captured for the mint/email flow
    
    @State private var samples: [SFVitalsSample] = []
    @State private var status: String = ""
    @State private var isLoading = false
    @State private var isMinting = false

    // ✅ LAN backend (ngrok)
    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    var body: some View {
        VStack(spacing: 16) {
            header
            
            // Email Input Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Results")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                TextField("skagen146@gmail.com", text: $emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 4)

            if samples.isEmpty {
                ContentUnavailableView("No Data", systemImage: "chart.line.uptrend.xyaxis", description: Text(isLoading ? "Fetching from Snowflake..." : "Upload vitals first."))
            } else {
                chartBlock
            }

            statusFooter

            Spacer()
        }
        .padding()
        .navigationTitle("Vitals Analysis")
        .task { await fetchVitals() }
    }

    private var header: some View {
        HStack {
            Text("Snowflake Data")
                .font(.title2.bold())
            Spacer()
            
            Button {
                Task { await fetchVitals() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
            .buttonStyle(.bordered)

            Button {
                Task { await mintAndEmailGraph() }
            } label: {
                HStack {
                    if isMinting { ProgressView().tint(.white).padding(.trailing, 4) }
                    Text(isMinting ? "Minting..." : "Mint & Email")
                }
            }
            .disabled(isMinting || emailAddress.isEmpty || solanaPublicKey.isEmpty)
            .buttonStyle(.borderedProminent)
        }
    }

    private var chartBlock: some View {
        let ordered = samples.sorted { $0.ts_ms < $1.ts_ms }
        return VStack(alignment: .leading, spacing: 8) {
            Chart(ordered) { s in
                LineMark(
                    x: .value("Time", s.date),
                    y: .value("HR", s.hr_bpm)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", s.date),
                    y: .value("BR", s.br_rpm)
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 300)

            HStack {
                Label("HR (BPM)", systemImage: "heart.fill").foregroundStyle(.blue)
                Spacer()
                Label("BR (RPM)", systemImage: "wind").foregroundStyle(.purple)
            }
            .font(.caption2)
        }
    }

    private var statusFooter: some View {
        Text(status)
            .font(.caption2)
            .foregroundStyle(status.contains("✅") ? .green : .secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Networking

    private func fetchVitals() async {
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespaces)
        guard !wallet.isEmpty else {
            status = "⚠️ Set wallet address in settings."
            return
        }

        isLoading = true
        status = "Querying Snowflake..."
        
        var components = URLComponents(url: backendBaseURL.appendingPathComponent("api/vitals"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "wallet", value: wallet),
            URLQueryItem(name: "limit", value: "50")
        ]

        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.addValue("69420", forHTTPHeaderField: "ngrok-skip-browser-warning")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(SFVitalsResponse.self, from: data)
            samples = decoded.vitals
            status = "Loaded \(samples.count) records from Snowflake."
        } catch {
            status = "Fetch failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func mintAndEmailGraph() async {
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespaces)
        
        isMinting = true
        status = "Backend is generating & emailing graph..."

        // Build URL for the /mint-and-email endpoint
        var components = URLComponents(url: backendBaseURL.appendingPathComponent("mint-and-email"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "wallet", value: wallet),
            URLQueryItem(name: "email", value: emailAddress)
        ]

        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("69420", forHTTPHeaderField: "ngrok-skip-browser-warning")

            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 200 {
                status = "✅ Success! Graph sent to \(emailAddress)"
            } else {
                let errorDetails = String(data: data, encoding: .utf8) ?? "Unknown Error"
                status = "❌ Failed: \(errorDetails)"
            }
        } catch {
            status = "❌ Connection Error: \(error.localizedDescription)"
        }
        isMinting = false
    }
}
