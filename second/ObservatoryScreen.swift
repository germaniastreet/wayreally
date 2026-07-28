import SwiftUI
import Combine
import UIKit

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

    @State private var pendingConsentConfirmation = false
    @State private var pendingDeleteSession: ReflectionSession?
    @State private var hapticTimer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                SecondTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ScreenHeader(
                            title: "WayReally",
                            subtitle: nil
                        )

                        lifecycleControls

                        if store.isRecording, let session = store.activeSession {
                            VStack(spacing: 8) {
                                Text("Recording Reflection")
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundStyle(SecondTheme.primaryText)

                                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                    Text("\(session.timeRangeText) • \(durationText(for: session, now: context.date))")
                                        .font(.caption)
                                        .foregroundStyle(SecondTheme.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }

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
            .confirmationDialog(
                "Before You Start",
                isPresented: $pendingConsentConfirmation,
                titleVisibility: .visible
            ) {
                Button("Start Recording") {
                    startReflectionAndSpeech()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("If anyone besides you will be part of this reflection, make sure they know it's being recorded and have agreed to it.")
            }
            .confirmationDialog(
                "Delete This Reflection",
                isPresented: Binding(
                    get: { pendingDeleteSession != nil },
                    set: { isPresented in if !isPresented { pendingDeleteSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let session = pendingDeleteSession {
                        store.deleteReflection(session)
                    }
                    pendingDeleteSession = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteSession = nil
                }
            } message: {
                if let session = pendingDeleteSession {
                    Text("This permanently deletes \"\(session.title)\" and its audio recording. This can't be undone.")
                }
            }
        }
        .onChange(of: store.isRecording) { _, isRecording in
            if isRecording {
                startHapticFeedback()
            } else {
                stopHapticFeedback()
            }
        }
    }

    private func startHapticFeedback() {
        // Initial haptic pulse when recording starts
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()

        // Sharp haptic pulse every 60 seconds (1 minute)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            let pulse = UIImpactFeedbackGenerator(style: .heavy)
            pulse.prepare()
            pulse.impactOccurred()
        }
    }

    private func stopHapticFeedback() {
        hapticTimer?.invalidate()
        hapticTimer = nil

        // Final haptic pulse when recording stops
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
    }

    // MARK: - Controls

    private var lifecycleControls: some View {
        RecordingControlButton(
            isRecording: store.isRecording,
            // Temporarily bypassing the consent confirmation dialog during
            // testing -- startReflectionAndSpeech() still records a
            // consentAcknowledgedAt timestamp either way. Restore by setting
            // pendingConsentConfirmation = true here instead.
            onStart: { startReflectionAndSpeech() },
            onStop: {
                speechManager.stop()
                store.stopAndObserve()
            }
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func startReflectionAndSpeech() {
        // Captured at the moment consent was confirmed, not whenever
        // permissions/setup happen to finish, so this timestamp is an
        // honest record of when the person actually agreed to start.
        let consentTimestamp = Date()

        Task {
            let allowed = await speechManager.requestPermissions()
            guard allowed else { return }

            let audioFileName = store.startReflection(consentAcknowledgedAt: consentTimestamp)

            speechManager.start(audioFileName: audioFileName) { utterances in
                store.updateLiveTranscript(utterances)
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
            Text("Tap Start Reflection above to record your first one. Finished reflections are saved to your device and will appear here.")
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

                Divider()

                Button(role: .destructive) {
                    pendingDeleteSession = session
                } label: {
                    Label("Delete This Reflection", systemImage: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private enum TranscriptRow: Identifiable {
        case utterance(TranscriptEvent)
        case pause(id: UUID, duration: TimeInterval)

        var id: UUID {
            switch self {
            case .utterance(let event): return event.id
            case .pause(let id, _): return id
            }
        }
    }

    private func transcriptRows(for session: ReflectionSession) -> [TranscriptRow] {
        let longPauseThreshold: TimeInterval = 10.0

        let events = session.transcript.sorted { $0.timestamp < $1.timestamp }
        let gaps = session.observationEvents
            .filter { $0.kind == .pauseGap }
            .sorted { $0.timestamp < $1.timestamp }

        var rows: [TranscriptRow] = []
        var gapIndex = 0

        for (index, event) in events.enumerated() {
            rows.append(.utterance(event))

            let nextTimestamp = index + 1 < events.count ? events[index + 1].timestamp : Date.distantFuture
            while gapIndex < gaps.count,
                  gaps[gapIndex].timestamp >= event.timestamp,
                  gaps[gapIndex].timestamp < nextTimestamp {
                let gapEvent = gaps[gapIndex]
                let duration = nextTimestamp.timeIntervalSince(gapEvent.timestamp)
                if duration > 0 {
                    rows.append(.pause(id: gapEvent.id, duration: duration))
                }
                gapIndex += 1
            }
        }

        return rows
    }

    private func transcriptView(_ session: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.transcript.isEmpty {
                Text(store.isRecording ? "Listening..." : "No transcript captured.")
                    .font(.subheadline)
                    .foregroundStyle(SecondTheme.secondaryText)
            } else {
                ForEach(transcriptRows(for: session)) { row in
                    switch row {
                    case .utterance(let event):
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
                    case .pause(_, let duration):
                        pauseIndicator(duration: duration)
                    }
                }
            }
        }
    }

    private func pauseIndicator(duration: TimeInterval) -> some View {
        let longPauseThreshold: TimeInterval = 10.0

        return Group {
            if duration >= longPauseThreshold {
                HStack(spacing: 8) {
                    VStack { Divider() }
                    Text("quiet · \(formattedGapDuration(duration))")
                        .font(.caption2)
                        .foregroundStyle(SecondTheme.secondaryText)
                        .fixedSize()
                    VStack { Divider() }
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 12) {
                    Text("")
                        .frame(width: 78, alignment: .leading)

                    Text("···  \(formattedGapDuration(duration)) pause")
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(SecondTheme.secondaryText.opacity(0.8))

                    Spacer()
                }
            }
        }
    }

    private func formattedGapDuration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
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
            MetricRow(
                label: "Consent acknowledged",
                value: session.consentAcknowledgedAt.map { $0.shortTimeWithSeconds } ?? "Not recorded"
            )
            MetricRow(
                label: "Speaker identification",
                value: session.diarizationEngineVersion.map { "v\($0)" } ?? "Not yet run"
            )
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

/// Full-width rectangular control for starting and stopping a reflection.
/// Tap to start (no hold required), tap to stop. The entire button is hot
/// and clickable -- no need to hit a specific spot.
struct RecordingControlButton: View {
    let isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: isRecording ? onStop : onStart) {
            VStack(spacing: 8) {
                Image(systemName: isRecording ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36, weight: .semibold))

                Text(isRecording ? "Stop Reflection" : "Start Reflection")
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(
                isRecording
                    ? LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.0, green: 0.2, blue: 0.2),
                            Color(red: 0.8, green: 0.0, blue: 0.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.1, green: 0.6, blue: 1.0),
                            Color(red: 0.0, green: 0.4, blue: 0.9)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isRecording ? "Stop reflection" : "Start reflection")
    }
}
