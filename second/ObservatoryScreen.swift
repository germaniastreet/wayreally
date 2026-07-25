import SwiftUI
import Combine

/// Observatory is now the single home for both recording a reflection and
/// browsing reflection history. It used to be split with ReflectionTimelineScreen
/// (separate tab, separate detail page reached by navigation) -- that produced
/// duplicated Summary/Arc/Evidence/Diagnostics content across two screens. Now
/// the full history lives here as an expandable list (tap a card to open it in
/// place), and the Timeline tab is a placeholder for something else later.
struct ObservatoryScreen: View {
    @EnvironmentObject private var store: ReflectionSessionStore

    /// Shared with AudioCaptureScreen (injected from ContentView) so starting
    /// or stopping a reflection from either tab controls the same recording.
    @EnvironmentObject private var speechManager: SpeechRecognitionManager

    var body: some View {
        NavigationStack {
            ZStack {
                SecondTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ScreenHeader(
                            title: "WayReally",
                            subtitle: store.isRecording ? "Recording Reflection" : nil
                        )

                        if store.isRecording, let session = store.activeSession {
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                Text("\(session.timeRangeText) • \(durationText(for: session, now: context.date))")
                                    .font(.caption)
                                    .foregroundStyle(SecondTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }

                        lifecycleControls

                        if store.isRecording, let session = store.activeSession {
                            liveTranscriptCard(session)
                        }

                        if store.completedSessions.isEmpty {
                            emptyHistoryCard
                        } else {
                            reflectionListSection
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Controls

    private var lifecycleControls: some View {
        RecordingControlButton(
            isRecording: store.isRecording,
            onStart: { startReflectionAndSpeech() },
            onStop: {
                speechManager.stop()
                store.stopAndObserve()
            }
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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

    // MARK: - Live recording

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

    // MARK: - History list

    private var emptyHistoryCard: some View {
        AppCard(title: "No Reflections Yet") {
            Text("Hold Start Reflection above to record your first one. Finished reflections are saved to your device and will appear here.")
                .font(.subheadline)
                .foregroundStyle(SecondTheme.secondaryText)
        }
        .padding(.horizontal)
    }

    private var reflectionListSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(store.completedSessions.enumerated()), id: \.element.id) { index, session in
                reflectionCard(session, startsExpanded: index == 0)
            }
        }
        .padding(.horizontal)
    }

    private func reflectionCard(_ session: ReflectionSession, startsExpanded: Bool) -> some View {
        AppCard(title: session.title, startsExpanded: startsExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(session.timeRangeText) • \(session.durationText)")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)

                summaryView(session)

                Divider()

                sectionTitle("Reflection Arc")
                arcView(session)

                Divider()

                sectionTitle("Transcript")
                transcriptView(session)

                Divider()

                sectionTitle("Evidence")
                evidenceView(session)

                Divider()

                sectionTitle("Diagnostics")
                diagnosticsView(session)
            }
        }
    }

    private func summaryView(_ session: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(primaryInsight(session))
                .font(.headline)
                .foregroundStyle(SecondTheme.primaryText)

            Text(observationDetail(session, title: "Reflection Summary"))
                .font(.subheadline)
                .foregroundStyle(SecondTheme.primaryText)

            if observationDetail(session, title: "Suggested Direction") != "Pending" {
                Text("Suggested direction: \(observationDetail(session, title: "Suggested Direction"))")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            }

            if observationDetail(session, title: "Key Signals") != "Pending" {
                Text("Key signals: \(observationDetail(session, title: "Key Signals"))")
                    .font(.caption2)
                    .foregroundStyle(SecondTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func arcView(_ session: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(observationDetail(session, title: "Arc Title"))
                .font(.title3)
                .bold()
                .foregroundStyle(SecondTheme.primaryText)

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

    private func evidenceView(_ session: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Emotional Trajectory")
            Text(observationDetail(session, title: "Trajectory Title"))
                .font(.subheadline)
                .bold()
                .foregroundStyle(SecondTheme.primaryText)

            Text(observationDetail(session, title: "Emotional Trajectory"))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            MetricRow(label: "Movement", value: observationDetail(session, title: "Trajectory Movement"))
            MetricRow(label: "Start", value: observationDetail(session, title: "Trajectory Start"))
            MetricRow(label: "End", value: observationDetail(session, title: "Trajectory End"))

            Divider()

            sectionTitle("Observation Events")
            Text(ObservationEventEngine.eventSummary(session.observationEvents))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            if session.observationEvents.isEmpty {
                Text("No micro-observation events recorded.")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            } else {
                ForEach(ObservationEventEngine.groupedEvents(session.observationEvents), id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.category.rawValue) (\(group.events.count))")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(SecondTheme.primaryText)

                        Text(ObservationEventEngine.categorySummary(group.category, events: group.events))
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        ForEach(group.events.prefix(5)) { event in
                            observationEventDetail(event)
                        }
                    }

                    Divider()
                }
            }

            sectionTitle("Dynamics")
            Text(DynamicsEngine.summary(session.dynamicsPatterns))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            ForEach(session.dynamicsPatterns) { pattern in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.title)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(SecondTheme.primaryText)

                    Text(pattern.detail)
                        .font(.caption2)
                        .foregroundStyle(SecondTheme.secondaryText)
                }
            }

            Divider()

            sectionTitle("Correlations")
            Text(CorrelationEngine.summary(session.observationCorrelations))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            ForEach(session.observationCorrelations) { correlation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(correlation.title)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(SecondTheme.primaryText)

                    Text(correlation.summary)
                        .font(.caption2)
                        .foregroundStyle(SecondTheme.secondaryText)
                }
            }
        }
    }

    private func observationEventDetail(_ event: ObservationEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(event.timestamp.shortTimeWithSeconds) • \(event.title)")
                .font(.caption)
                .bold()
                .foregroundStyle(SecondTheme.primaryText)

            Text(event.detail)
                .font(.caption2)
                .foregroundStyle(SecondTheme.secondaryText)

            if let related = event.relatedText, !related.isEmpty {
                Text("Related: \(related)")
                    .font(.caption2)
                    .foregroundStyle(SecondTheme.secondaryText)
                    .lineLimit(2)
            }

            if !event.alternativeExplanations.isEmpty {
                Text("Other readings: " + event.alternativeExplanations.joined(separator: " · "))
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(SecondTheme.secondaryText)
                    .lineLimit(3)
            }
        }
    }

    private func diagnosticsView(_ session: ReflectionSession) -> some View {
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
                sectionTitle("Body Signals")

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

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .bold()
            .foregroundStyle(SecondTheme.primaryText)
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

/// One circular control that covers both ends of a reflection. Idle, it only
/// fires after being held for a couple of seconds (so it can't be triggered
/// by an accidental tap) and shows on-button text feedback while held
/// ("Hold...", "Starting...", "Now!"). Once recording, the same circle turns
/// into a plain single-tap Stop button -- stopping shouldn't have the same
/// friction as starting. Sized at half of its original size in every state,
/// including the in-between hold states, per request.
struct RecordingControlButton: View {
    let isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isPressing = false
    @State private var holdElapsed: Double = 0

    private let holdDuration: Double = 2.0
    private let tickInterval: Double = 0.05
    private let diameter: CGFloat = 70

    var body: some View {
        Group {
            if isRecording {
                Button(action: onStop) {
                    face(icon: "stop.fill", label: "Stop", fill: Color.red.opacity(0.9), progress: 0)
                }
                .buttonStyle(.plain)
            } else {
                face(icon: "record.circle", label: startLabel, fill: SecondTheme.heartRate, progress: min(holdElapsed / holdDuration, 1.0))
                    .contentShape(Circle())
                    .onLongPressGesture(
                        minimumDuration: holdDuration,
                        maximumDistance: 60,
                        pressing: { pressing in
                            isPressing = pressing
                            if !pressing && holdElapsed < holdDuration {
                                holdElapsed = 0
                            }
                        },
                        perform: {
                            holdElapsed = holdDuration
                            onStart()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                holdElapsed = 0
                                isPressing = false
                            }
                        }
                    )
                    .onReceive(Timer.publish(every: tickInterval, on: .main, in: .common).autoconnect()) { _ in
                        guard isPressing, holdElapsed < holdDuration else { return }
                        holdElapsed = min(holdElapsed + tickInterval, holdDuration)
                    }
            }
        }
        .accessibilityLabel(isRecording ? "Stop reflection" : "Hold for two seconds to start a reflection")
    }

    private var startLabel: String {
        if holdElapsed >= holdDuration {
            return "Now!"
        } else if isPressing {
            return "Starting..."
        } else {
            return "Hold to\nStart"
        }
    }

    private func face(icon: String, label: String, fill: Color, progress: Double) -> some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: diameter, height: diameter)

            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
            }

            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17))

                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
            }
            .foregroundStyle(.white)
        }
    }
}
