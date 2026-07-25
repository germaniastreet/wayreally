import SwiftUI
import Combine

struct ObservatoryScreen: View {
    @EnvironmentObject private var store: ReflectionSessionStore

    /// Shared with AudioCaptureScreen (injected from ContentView) so starting
    /// or stopping a reflection from either tab controls the same recording.
    @EnvironmentObject private var speechManager: SpeechRecognitionManager

    private var displaySession: ReflectionSession? {
        store.activeSession
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SecondTheme.background.ignoresSafeArea()

                if let session = displaySession {
                    activeSessionView(session)
                } else {
                    emptyStateView
                }
            }
        }
    }

    private func activeSessionView(_ session: ReflectionSession) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(
                    title: "WayReally",
                    subtitle: store.isRecording ? "Recording Reflection" : "Reflection Complete"
                )

                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Text("\(session.timeRangeText) • \(durationText(for: session, now: context.date))")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                lifecycleControls

                if store.isRecording {
                    liveTranscriptCard(session)
                } else {
                    // The full breakdown (Reflection Arc, Suggested Direction,
                    // Evidence, Diagnostics) lives in ReflectionDetailScreen,
                    // which is also what the Timeline tab opens for this same
                    // session. Showing it a second time here duplicated that
                    // content; this card is a compact preview that links to
                    // the single, shared detail view instead.
                    completionSummaryCard(session)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func completionSummaryCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "Reflection Complete") {
            VStack(alignment: .leading, spacing: 12) {
                Text(primaryInsight(session))
                    .font(.headline)
                    .foregroundStyle(SecondTheme.primaryText)

                Text(observationDetail(session, title: "Reflection Summary"))
                    .font(.subheadline)
                    .foregroundStyle(SecondTheme.primaryText)

                NavigationLink {
                    ReflectionDetailScreen(session: session)
                } label: {
                    HStack {
                        Text("View Full Reflection Details")
                            .font(.subheadline)
                            .bold()

                        Spacer()

                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(SecondTheme.primaryText)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private func liveTranscriptCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "Live Reflection") {
            VStack(alignment: .leading, spacing: 14) {
                transcriptView(session)

                Text(speechManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            }
        }
        .padding(.horizontal)
    }

    private func transcriptView(_ session: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.transcript.isEmpty {
                Text(store.isRecording ? "Listening..." : "No transcript captured.")
                    .font(.subheadline)
                    .foregroundStyle(SecondTheme.secondaryText)
            } else {
                ForEach(session.transcript) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.timestamp.shortTimeWithSeconds)
                            .font(.caption2)
                            .foregroundStyle(SecondTheme.secondaryText)
                            .frame(width: 78, alignment: .leading)

                        Text(event.speaker.rawValue)
                            .font(.caption)
                            .bold()
                            .foregroundStyle(SecondTheme.primaryText)
                            .frame(width: 38, alignment: .leading)

                        Text(event.text)
                            .font(.subheadline)
                            .foregroundStyle(SecondTheme.primaryText)
                    }
                }
            }
        }
    }

    private func primaryInsight(_ session: ReflectionSession) -> String {
        let arcTitle = observationDetail(session, title: "Arc Title")
        if arcTitle != "Pending" && arcTitle != "No clear arc" {
            return arcTitle
        }

        let trajectoryTitle = observationDetail(session, title: "Trajectory Title")
        if trajectoryTitle != "Pending" && trajectoryTitle != "No clear trajectory" {
            return trajectoryTitle
        }

        let observedPattern = observationDetail(session, title: "Observed Pattern")
        if observedPattern != "Pending" {
            return observedPattern
        }

        return "No clear pattern detected yet."
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "circle.dashed")
                .font(.system(size: 64))
                .foregroundStyle(SecondTheme.secondaryText)

            Text("No Active Reflection")
                .font(.title2)
                .bold()

            Text("Tap Start Reflection to begin.")
                .foregroundStyle(SecondTheme.secondaryText)

            Button {
                startReflectionAndSpeech()
            } label: {
                Label("Start Reflection", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SecondTheme.heartRate)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private var lifecycleControls: some View {
        HStack(spacing: 12) {
            if store.isRecording {
                Button {
                    speechManager.stop()
                    store.stopAndObserve()
                } label: {
                    Label("Stop & Observe", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    speechManager.stop()
                    store.resetActiveSession()
                } label: {
                    Text("Reset")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    startReflectionAndSpeech()
                } label: {
                    Label("Start Reflection", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SecondTheme.heartRate)

                Button {
                    store.resetActiveSession()
                } label: {
                    Text("Clear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    private func startReflectionAndSpeech() {
        Task {
            let allowed = await speechManager.requestPermissions()
            guard allowed else { return }

            store.startReflection()

            speechManager.start { text in
                store.updateLiveTranscript(text)
            }
        }
    }

    private func observationDetail(_ session: ReflectionSession, title: String) -> String {
        session.observations.first(where: { $0.title == title })?.detail ?? "Pending"
    }

    private func durationText(for session: ReflectionSession, now: Date) -> String {
        if store.isRecording, let start = store.activeSession?.startedAt {
            let seconds = max(0, Int(now.timeIntervalSince(start)))
            return "\(seconds / 60)m \(seconds % 60)s"
        }

        return session.durationText
    }
}
