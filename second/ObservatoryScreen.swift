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
                    whatsGoingOnCard(session)
                    reflectionArcCard(session)
                    suggestedDirectionCard(session)
                    validationEvidenceCard(session)
                    diagnosticsCard(session)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func whatsGoingOnCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "What's Going On") {
            VStack(alignment: .leading, spacing: 12) {
                Text(primaryInsight(session))
                    .font(.headline)
                    .foregroundStyle(SecondTheme.primaryText)

                Text(observationDetail(session, title: "Reflection Summary"))
                    .font(.subheadline)
                    .foregroundStyle(SecondTheme.primaryText)

                if observationDetail(session, title: "Key Signals") != "Pending" {
                    Text("Key signals: \(observationDetail(session, title: "Key Signals"))")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private func reflectionArcCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "Reflection Arc") {
            VStack(alignment: .leading, spacing: 10) {
                Text(observationDetail(session, title: "Arc Title"))
                    .font(.title3)
                    .bold()

                MetricRow(label: "Start", value: observationDetail(session, title: "Arc Start"))
                MetricRow(label: "Middle", value: observationDetail(session, title: "Arc Middle"))
                MetricRow(label: "End", value: observationDetail(session, title: "Arc End"))

                Text(observationDetail(session, title: "Reflection Arc"))
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)

                let keyEvents = observationDetail(session, title: "Arc Key Events")
                if keyEvents != "Pending" && !keyEvents.isEmpty {
                    Text("Evidence: \(keyEvents)")
                        .font(.caption2)
                        .foregroundStyle(SecondTheme.secondaryText)
                }
            }
        }
        .padding(.horizontal)
    }

    private func suggestedDirectionCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "Suggested Direction") {
            VStack(alignment: .leading, spacing: 8) {
                Text(observationDetail(session, title: "Suggested Direction"))
                    .font(.subheadline)

                Text("Observations are associations, not diagnoses.")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private func validationEvidenceCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "Validation Evidence", startsExpanded: false) {
            VStack(alignment: .leading, spacing: 18) {
                evidenceSectionTitle("Transcript")
                transcriptView(session)

                Divider()

                evidenceSectionTitle("Observation Events")
                Text(ObservationEventEngine.eventSummary(session.observationEvents))
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)

                if session.observationEvents.isEmpty {
                    Text("No micro-observation events recorded.")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)
                } else {
                    ForEach(ObservationEventEngine.groupedEvents(session.observationEvents), id: \.category) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(group.category.rawValue) (\(group.events.count))")
                                .font(.subheadline)
                                .bold()

                            Text(ObservationEventEngine.categorySummary(group.category, events: group.events))
                                .font(.caption)
                                .foregroundStyle(SecondTheme.secondaryText)

                            ForEach(group.events) { event in
                                observationEventDetail(event)
                            }
                        }
                    }
                }

                Divider()

                evidenceSectionTitle("Dynamics")
                Text(DynamicsEngine.summary(session.dynamicsPatterns))
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)

                if session.dynamicsPatterns.isEmpty {
                    Text("No dynamics patterns detected yet.")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)
                } else {
                    ForEach(Array(session.dynamicsPatterns.enumerated()), id: \.offset) { _, pattern in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pattern.title)
                                .font(.caption)
                                .bold()

                            Text(pattern.detail)
                                .font(.caption)
                                .foregroundStyle(SecondTheme.secondaryText)
                        }
                    }
                }

                Divider()

                evidenceSectionTitle("Correlations")
                Text(CorrelationEngine.summary(session.observationCorrelations))
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)

                if session.observationCorrelations.isEmpty {
                    Text("No correlations detected yet.")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)
                } else {
                    ForEach(Array(session.observationCorrelations.enumerated()), id: \.offset) { _, correlation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(correlation.title)
                                .font(.caption)
                                .bold()
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func observationEventDetail(_ event: ObservationEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(event.timestamp.shortTimeWithSeconds) • \(event.title)")
                .font(.caption)
                .bold()
                .foregroundStyle(SecondTheme.primaryText)

            Text(event.detail)
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            if let relatedText = event.relatedText, !relatedText.isEmpty {
                Text("Related: \(relatedText)")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            }

            if !event.alternativeExplanations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Other possible readings:")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(SecondTheme.secondaryText)

                    ForEach(event.alternativeExplanations, id: \.self) { explanation in
                        Text("• \(explanation)")
                            .font(.caption2)
                            .foregroundStyle(SecondTheme.secondaryText)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }

    private func diagnosticsCard(_ session: ReflectionSession) -> some View {
        AppCard(title: "Session State", startsExpanded: false) {
            VStack(spacing: 8) {
                MetricRow(label: "State", value: session.state.rawValue.capitalized)
                MetricRow(label: "Boundary", value: session.endedAt == nil ? "Open" : "Closed")
                MetricRow(label: "Duration", value: session.durationText)
                MetricRow(label: "Speech rate", value: session.voice.wordsPerMinute == 0 ? "Pending" : "\(session.voice.wordsPerMinute) WPM")
                MetricRow(label: "Pause gaps", value: session.voice.pauseCount == 0 ? "None detected" : "\(session.voice.pauseCount)")
                MetricRow(label: "Hesitation markers", value: session.voice.hesitationMarkers == 0 ? "None detected" : "\(session.voice.hesitationMarkers)")
                MetricRow(label: "Observation engine", value: session.observationEngineVersion)
                MetricRow(label: "Dynamics engine", value: session.dynamicsEngineVersion)
                MetricRow(label: "Correlation engine", value: session.correlationEngineVersion)
                MetricRow(label: "Summary engine", value: ReflectionSummaryEngine.engineVersion)
                MetricRow(label: "Trajectory engine", value: EmotionalTrajectoryEngine.engineVersion)
                MetricRow(label: "Arc engine", value: ReflectionArcEngine.engineVersion)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Body Signals")
                        .font(.subheadline)
                        .bold()

                    Text("Body signals from \(session.biometrics.queryStart.shortTimeWithSeconds)–\(session.biometrics.queryEnd.shortTimeWithSeconds)")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)

                    Text("No biometric samples attached to this session yet. Watch and HealthKit will be connected in a later build.")
                        .font(.caption)
                        .foregroundStyle(SecondTheme.secondaryText)

                    MetricRow(label: "Data quality", value: session.biometrics.quality.rawValue.capitalized)
                }
            }
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

    private func evidenceSectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
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

