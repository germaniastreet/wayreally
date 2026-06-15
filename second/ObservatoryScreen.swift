import SwiftUI
import Combine

struct ObservatoryScreen: View {
    @EnvironmentObject private var store: ReflectionSessionStore
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var timerTick = Date()

    private var displaySession: ReflectionSession? {
        store.activeSession
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SecondTheme.background
                    .ignoresSafeArea()

                if let session = displaySession {
                    activeSessionView(session)
                } else {
                    emptyStateView
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                timerTick = date
            }
        }
    }

    @ViewBuilder
    private func activeSessionView(_ session: ReflectionSession) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(
                    title: "second",
                    subtitle: store.isRecording ? "Recording Reflection" : "Live Reflection"
                )

                Text("\(session.timeRangeText) • \(durationText)")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                lifecycleControls

                AppCard(title: "Live Reflection Transcript") {
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
                                        .frame(width: 38, alignment: .leading)

                                    Text(event.text)
                                        .font(.subheadline)
                                }
                            }
                        }

                        Text(speechManager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)
                    }
                }
                .padding(.horizontal)

                AppCard(title: "Observed Pattern") {
                    Text(session.observations.first?.detail ?? "No observed pattern yet. Stop the reflection to generate the first observation.")
                        .font(.subheadline)
                        .foregroundStyle(SecondTheme.primaryText)
                }
                .padding(.horizontal)

                AppCard(title: "Cognition Signals") {
                    VStack(spacing: 8) {
                        MetricRow(label: "Session state", value: session.state.rawValue.capitalized)
                        MetricRow(label: "Session boundary", value: session.endedAt == nil ? "Open" : "Closed")
                        MetricRow(label: "Emotional tone", value: observationDetail(session, title: "Emotional Tone"))
                        MetricRow(label: "Cognitive load", value: observationDetail(session, title: "Cognitive Load"))
                        MetricRow(label: "Focus signal", value: observationDetail(session, title: "Focus Signal"))
                        MetricRow(label: "Confidence", value: session.observations.first?.confidence.rawValue.capitalized ?? "Unavailable")
                    }
                }
                .padding(.horizontal)

                AppCard(title: "Voice Signals") {
                    VStack(spacing: 8) {
                        MetricRow(label: "Speech rate", value: session.voice.wordsPerMinute == 0 ? "Pending" : "\(session.voice.wordsPerMinute) WPM")
                        MetricRow(label: "Pause gaps", value: session.voice.pauseCount == 0 ? "None detected" : "\(session.voice.pauseCount)")
                        MetricRow(label: "Hesitation markers", value: session.voice.hesitationMarkers == 0 ? "None detected" : "\(session.voice.hesitationMarkers)")
                        MetricRow(label: "Duration", value: durationText)
                    }
                }
                .padding(.horizontal)

                AppCard(title: "Observation Events", startsExpanded: false) {
                    observationEventsView(session)
                }
                .padding(.horizontal)

                AppCard(title: "Body Signals") {
                    VStack(spacing: 12) {
                        Text("Body signals from \(session.biometrics.queryStart.shortTimeWithSeconds)–\(session.biometrics.queryEnd.shortTimeWithSeconds)")
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        Text("No biometric samples attached to this session yet. Watch and HealthKit will be connected in a later build.")
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        MetricRow(label: "Data quality", value: session.biometrics.quality.rawValue.capitalized)
                    }
                }
                .padding(.horizontal)

                AppCard(title: "Observatory Note") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.observations.first(where: { $0.title == "Observatory Note" })?.detail ?? "No observatory note yet.")
                            .font(.subheadline)

                        Text("Observations are associations, not diagnoses.")
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
    }

    private func observationEventsView(_ session: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ObservationEventEngine.eventSummary(session.observationEvents))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            Text("Engine version: \(session.observationEngineVersion)")
                .font(.caption2)
                .foregroundStyle(SecondTheme.secondaryText)

            if session.observationEvents.isEmpty {
                Text("No micro-observation events recorded yet.")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            } else {
                ForEach(ObservationEventEngine.groupedEvents(session.observationEvents), id: \.category) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(group.category.rawValue) (\(group.events.count))")
                            .font(.subheadline)
                            .bold()

                        Text(ObservationEventEngine.categorySummary(group.category, events: group.events))
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        ForEach(group.events.prefix(4)) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.caption)
                                    .bold()

                                Text(event.detail)
                                    .font(.caption2)
                                    .foregroundStyle(SecondTheme.secondaryText)

                                if let related = event.relatedText {
                                    Text("Related: \(related)")
                                        .font(.caption2)
                                        .foregroundStyle(SecondTheme.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.top, 3)
                        }
                    }

                    Divider()
                }
            }
        }
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

    private var durationText: String {
        if store.isRecording, let start = store.activeSession?.startedAt {
            let seconds = Int(timerTick.timeIntervalSince(start))
            return "\(seconds / 60)m \(seconds % 60)s"
        }

        return displaySession?.durationText ?? "0m 0s"
    }
}
