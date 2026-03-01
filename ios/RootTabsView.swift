import SwiftUI

struct RootTabsView: View {
    var body: some View {
        TabView {
            LoginView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            UploadView()
                .tabItem {
                    Label("Upload", systemImage: "camera.viewfinder")
                }

            GraphView()
                .tabItem {
                    Label("Graph", systemImage: "waveform.path.ecg")
                }
            SolanaView()
                .tabItem {
                    Label("Solana", systemImage: "checkmark.seal.fill")
                }

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "chart.line.uptrend.xyaxis")
                }
            AIView()
                .tabItem {
                    Label("GradientAI", systemImage: "brain.head.profile")
                }
            
            CortexView()
                .tabItem {
                    Label("Cortex", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
    }
}
