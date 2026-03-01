//
//  MeditationView.swift
//  p2
//
//  Created by Han Lee on 3/1/26.
//


import SwiftUI
import AVFoundation

struct MeditationView: View {
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var status = "Let Gradient AI tune your focus."
    @AppStorage("solana_public_key") private var solanaPublicKey: String = ""
    
    private let backendBaseURL = "https://d4f9-155-246-151-34.ngrok-free.app"

    var body: some View {
        VStack(spacing: 40) {
            // Icon that pulses with the "heartbeat"
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 20)
                    .frame(width: 200, height: 200)
                    .scaleEffect(isPlaying ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: isPlaying)
                
                Image(systemName: "leaf.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
            }

            Text(status)
                .font(.subheadline)
                .italic()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task { await toggleSession() }
            } label: {
                HStack {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    Text(isPlaying ? "End Session" : "Start Gradient AI Session")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isPlaying ? Color.red : Color.green)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .navigationTitle("AI Meditation")
    }

    func toggleSession() async {
        if isPlaying {
            player?.pause()
            isPlaying = false
            status = "Session ended."
            return
        }

        status = "Gradient AI is analyzing your Snowflake vitals..."
        
        let urlString = "\(backendBaseURL)/ai/gradient-meditation?wallet=\(solanaPublicKey)"
        guard let url = URL(string: urlString) else { return }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("69420", forHTTPHeaderField: "ngrok-skip-browser-warning")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let trackUrlStr = json["track_url"] as? String,
               let insight = json["insight"] as? String,
               let trackUrl = URL(string: trackUrlStr) {
                
                let playerItem = AVPlayerItem(url: trackUrl)
                player = AVPlayer(playerItem: playerItem)
                player?.play()
                
                isPlaying = true
                status = insight
            }
        } catch {
            status = "Error: Check your backend/ngrok connection."
        }
    }
}