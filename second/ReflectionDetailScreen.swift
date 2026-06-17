import SwiftUI

struct ReflectionDetailScreen: View {
    let session: ReflectionSession

    var body: some View {
        ZStack {
            SecondTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(
                        title: session.title,
                        subtitle: "\(session.timeRangeText) • \(session.durationText)"
                    )

                    AppCard(title: "Transcript") {
                        transcriptView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Reflection Summary") {
                        reflectionSummaryView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Emotional Trajectory") {
                        emotionalTrajectoryView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Observed Pattern") {
                        Text(observationDetail("Observed Pattern"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    AppCard(title: "Reflection Dynamics") {
                        reflectionDynamicsView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Observation Correlations") {
                        observationCorrelationsView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Observation Events", startsExpanded: true) {
                        observationEventsView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Cognition Signals") {
                        cognitionSignalsView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Session State") {
                        sessionStateView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Voice Signals") {
                        voiceSignalsView
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Reflection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.transcript.isEmpty {
                Text("No transcript captured.")
                    .font(.caption)
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
        }
    }

    private var reflectionSummaryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(observationDetail("Reflection Summary"))
                .font(.subheadline)

            if observationDetail("Key Signals") != "Pending" {
                Text("Key signals: \(observationDetail("Key Signals"))")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            }

            Text("Suggested direction: \(observationDetail("Suggested Direction"))")
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emotionalTrajectoryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(observationDetail("Trajectory Title"))
                .font(.subheadline)
                .bold()

            Text(observationDetail("Emotional Trajectory"))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            MetricRow(label: "Movement", value: observationDetail("Trajectory Movement"))
            MetricRow(label: "Start", value: observationDetail("Trajectory Start"))
            MetricRow(label: "End", value: observationDetail("Trajectory End"))

            if observationDetail("Trajectory Phrases") != "Pending" {
                Text("Key phrases: \(observationDetail("Trajectory Phrases"))")
                    .font(.caption2)
                    .foregroundStyle(SecondTheme.secondaryText)
            }

            Text("Engine version: \(EmotionalTrajectoryEngine.engineVersion)")
                .font(.caption2)
                .foregroundStyle(SecondTheme.secondaryText)
        }
    }

    private var reflectionDynamicsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DynamicsEngine.summary(session.dynamicsPatterns))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            Text("Engine version: \(session.dynamicsEngineVersion)")
                .font(.caption2)
                .foregroundStyle(SecondTheme.secondaryText)

            if session.dynamicsPatterns.isEmpty {
                Text("No dynamics patterns detected.")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            } else {
                ForEach(session.dynamicsPatterns) { pattern in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pattern.title)
                            .font(.subheadline)
                            .bold()

                        Text(pattern.detail)
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        if !pattern.tags.isEmpty {
                            Text("Tags: \(pattern.tags.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(SecondTheme.secondaryText)
                        }

                        Text("Confidence: \(pattern.confidence.rawValue.capitalized) • Engine \(pattern.engineVersion)")
                            .font(.caption2)
                            .foregroundStyle(SecondTheme.secondaryText)
                    }

                    Divider()
                }
            }
        }
    }

    private var observationCorrelationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CorrelationEngine.summary(session.observationCorrelations))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            Text("Engine version: \(session.correlationEngineVersion)")
                .font(.caption2)
                .foregroundStyle(SecondTheme.secondaryText)

            if session.observationCorrelations.isEmpty {
                Text("No correlations detected.")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            } else {
                ForEach(session.observationCorrelations) { correlation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(correlation.timestamp.displayTime) • \(correlation.title)")
                            .font(.subheadline)
                            .bold()

                        Text(correlation.summary)
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        if !correlation.sourceEventTitles.isEmpty {
                            Text("Based on: \(correlation.sourceEventTitles.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(SecondTheme.secondaryText)
                        }

                        Text("Confidence: \(correlation.confidence.rawValue.capitalized) • Engine \(correlation.engineVersion)")
                            .font(.caption2)
                            .foregroundStyle(SecondTheme.secondaryText)
                    }

                    Divider()
                }
            }
        }
    }

    private var observationEventsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ObservationEventEngine.eventSummary(session.observationEvents))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            Text("Engine version: \(session.observationEngineVersion)")
                .font(.caption2)
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

                        Text(ObservationEventEngine.categorySummary(group.category, events: group.events))
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        ForEach(group.events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(event.timestamp.shortTimeWithSeconds) • \(event.title)")
                                    .font(.subheadline)
                                    .bold()

                                Text(event.detail)
                                    .font(.caption)
                                    .foregroundStyle(SecondTheme.secondaryText)

                                if let related = event.relatedText {
                                    Text("Related: \(related)")
                                        .font(.caption2)
                                        .foregroundStyle(SecondTheme.secondaryText)
                                }

                                if !event.tags.isEmpty {
                                    Text("Tags: \(event.tags.joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(SecondTheme.secondaryText)
                                }

                                Text("Confidence: \(event.confidence.rawValue.capitalized) • Engine \(event.engineVersion)")
                                    .font(.caption2)
                                    .foregroundStyle(SecondTheme.secondaryText)
                            }
                            .padding(.top, 4)
                        }
                    }

                    Divider()
                }
            }
        }
    }

    private var cognitionSignalsView: some View {
        VStack(spacing: 8) {
            MetricRow(label: "Emotional tone", value: observationDetail("Emotional Tone"))
            MetricRow(label: "Cognitive load", value: observationDetail("Cognitive Load"))
            MetricRow(label: "Focus signal", value: observationDetail("Focus Signal"))
            MetricRow(label: "Confidence", value: session.observations.first(where: { $0.title == "Observed Pattern" })?.confidence.rawValue.capitalized ?? "Unavailable")
        }
    }

    private var sessionStateView: some View {
        VStack(spacing: 8) {
            MetricRow(label: "State", value: session.state.rawValue.capitalized)
            MetricRow(label: "Boundary", value: session.endedAt == nil ? "Open" : "Closed")
            MetricRow(label: "Duration", value: session.durationText)
            MetricRow(label: "Observation engine", value: session.observationEngineVersion)
            MetricRow(label: "Dynamics engine", value: session.dynamicsEngineVersion)
            MetricRow(label: "Correlation engine", value: session.correlationEngineVersion)
            MetricRow(label: "Summary engine", value: ReflectionSummaryEngine.engineVersion)
            MetricRow(label: "Trajectory engine", value: EmotionalTrajectoryEngine.engineVersion)
        }
    }

    private var voiceSignalsView: some View {
        VStack(spacing: 8) {
            MetricRow(label: "Speech rate", value: session.voice.wordsPerMinute == 0 ? "Pending" : "\(session.voice.wordsPerMinute) WPM")
            MetricRow(label: "Pause gaps", value: session.voice.pauseCount == 0 ? "None detected" : "\(session.voice.pauseCount)")
            MetricRow(label: "Hesitation markers", value: session.voice.hesitationMarkers == 0 ? "None detected" : "\(session.voice.hesitationMarkers)")
            MetricRow(label: "Duration", value: session.durationText)
        }
    }

    private func observationDetail(_ title: String) -> String {
        session.observations.first(where: { $0.title == title })?.detail ?? "Pending"
    }
}

