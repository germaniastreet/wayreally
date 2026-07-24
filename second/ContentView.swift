import SwiftUI

struct ContentView: View {
    @StateObject private var sessionStore = ReflectionSessionStore()

    /// Shared with AudioCaptureScreen so both screens control and reflect the
    /// same live recording instead of each owning a separate speech engine.
    @StateObject private var speechManager = SpeechRecognitionManager()

    var body: some View {
        TabView {
            ObservatoryScreen()
                .tabItem {
                    Label("Observatory", systemImage: "house")
                }

            ReflectionTimelineScreen()
                .tabItem {
                    Label("Timeline", systemImage: "clock")
                }

            CorrelationScreen()
                .tabItem {
                    Label("Correlation", systemImage: "waveform.path.ecg")
                }

            ConversationDynamicsScreen()
                .tabItem {
                    Label("Dynamics", systemImage: "arrow.left.arrow.right")
                }

            AudioCaptureScreen()
                .tabItem {
                    Label("Capture", systemImage: "mic")
                }

            NavigationStack {
                SignalLibraryScreen()
            }
            .tabItem {
                Label("Libraries", systemImage: "books.vertical")
            }

            SettingsScreen()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(SecondTheme.heartRate)
        .environmentObject(sessionStore)
        .environmentObject(speechManager)
    }
}

