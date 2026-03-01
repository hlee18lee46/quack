import SwiftUI
import Foundation
import SmartSpectraSwiftSDK

struct UploadView: View {
    @ObservedObject var sdk = SmartSpectraSwiftSDK.shared
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""

    @State private var status: String = ""
    @State private var isUploading: Bool = false
    @State private var lastUploadedAt: Date = .distantPast

    private let uploadTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    init() {
        SmartSpectraSwiftSDK.shared.setApiKey("CRoukQVggzGXA4xvOtue7F9jiNzel6i1y3P1PQra")
        SmartSpectraSwiftSDK.shared.setSmartSpectraMode(.continuous)
        SmartSpectraSwiftSDK.shared.setCameraPosition(.front)
        SmartSpectraSwiftSDK.shared.showControlsInScreeningView(true)
    }

    var body: some View {
        VStack(spacing: 16) {
            SmartSpectraView()
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if let m = sdk.metricsBuffer {
                let hr = Int(m.pulse.rate.last?.value ?? 0)
                let br = Int(m.breathing.rate.last?.value ?? 0)
                Text("❤️ \(hr) BPM · 🌬️ \(br) RPM")
                    .font(.headline)
            } else {
                Text("Align face + upper chest • even lighting • ~18–24\"")
                    .foregroundStyle(.secondary)
            }

            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding()
        .navigationTitle("Capture")
        .onReceive(uploadTimer) { _ in
            uploadLatestVitalsIfAvailable()
        }
    }

    private func uploadLatestVitalsIfAvailable() {
        guard !isUploading else { return }
        guard let m = sdk.metricsBuffer else { return }

        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wallet.isEmpty else {
            status = "Please link/paste your wallet address first."
            return
        }

        guard let hrLast = m.pulse.rate.last?.value,
              let brLast = m.breathing.rate.last?.value else { return }

        if hrLast <= 0 || brLast <= 0 { return }
        if Date().timeIntervalSince(lastUploadedAt) < 1.5 { return }

        let payload: [String: Any] = [
            "wallet": wallet,
            "ts_ms": Int(Date().timeIntervalSince1970 * 1000),
            "hr_bpm": Double(hrLast),
            "br_rpm": Double(brLast),
            "mode": "continuous"
        ]

        guard let url = URL(string: "/api/vitals", relativeTo: backendBaseURL) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            status = "Encode error: \(error.localizedDescription)"
            return
        }

        isUploading = true
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                self.isUploading = false
                self.lastUploadedAt = Date()

                if let error = error {
                    self.status = "Upload failed: \(error.localizedDescription)"
                    return
                }

                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code >= 200 && code < 300 {
                    self.status = "✅ Uploaded HR/BR to backend"
                } else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    self.status = "Server error \(code): \(body)"
                }
            }
        }.resume()
    }
}
