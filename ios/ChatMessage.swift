
import SwiftUI
import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "bot"
    let text: String
}

struct ChatResponse: Decodable {
    let ok: Bool
    let engine: String
    let reply: String
    let vitals_ctx: String?
}

struct ChatView: View {
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""

    @State private var engine: String = "cortex" // "cortex" or "gradient"
    @State private var input: String = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: "bot", text: "Hi! I’m Quack 🦆 Ask me about your vitals or for a breathing tip.")
    ]
    @State private var isSending: Bool = false
    @State private var status: String = ""

    private let backendBaseURL = URL(string: "https://d4f9-155-246-151-34.ngrok-free.app")!

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Quack Chat")
                    .font(.title2.bold())
                Spacer()

                Picker("Engine", selection: $engine) {
                    Text("Cortex").tag("cortex")
                    Text("Gradient").tag("gradient")
                }
                .pickerStyle(.menu)
            }

            if solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Please paste your Solana wallet address first (Login tab).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                returnView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { m in
                                bubble(for: m)
                                    .id(m.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    TextField("Message Quack…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(isSending)

                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding()
        .navigationTitle("Chat")
    }

    @ViewBuilder
    private var returnView: some View {
        EmptyView()
    }

    @ViewBuilder
    private func bubble(for m: ChatMessage) -> some View {
        HStack {
            if m.role == "bot" { }
            else { Spacer() }

            Text(m.text)
                .padding(12)
                .background(m.role == "bot" ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.accentColor.opacity(0.25)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 320, alignment: m.role == "bot" ? .leading : .trailing)

            if m.role == "bot" { Spacer() }
        }
    }

    private func send() async {
        let wallet = solanaPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wallet.isEmpty, !text.isEmpty else { return }

        input = ""
        status = ""
        isSending = true

        messages.append(ChatMessage(role: "user", text: text))

        do {
            let reply = try await callChat(wallet: wallet, message: text, engine: engine, limit: 120)
            messages.append(ChatMessage(role: "bot", text: reply))
            status = "✅ \(engine.capitalized) replied"
        } catch {
            messages.append(ChatMessage(role: "bot", text: "Sorry — I couldn’t reach the server."))
            status = "❌ \(error.localizedDescription)"
        }

        isSending = false
    }

    private func callChat(wallet: String, message: String, engine: String, limit: Int) async throws -> String {
        let url = backendBaseURL.appendingPathComponent("chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "wallet": wallet,
            "message": message,
            "engine": engine,
            "limit": limit
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw NSError(domain: "Chat", code: code, userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Server error"
            ])
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.reply
    }
}
