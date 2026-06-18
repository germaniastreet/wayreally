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

                    AppCard(title: "Summary") {
                        summaryView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Reflection Arc") {
                        arcView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Transcript") {
                        transcriptView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Evidence", startsExpanded: false) {
                        evidenceView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Diagnostics", startsExpanded: false) {
                        diagnosticsView
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Reflection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(primaryInsight)
                .font(.headline)

            Text(observationDetail("Reflection Summary"))
                .font(.subheadline)

            if observationDetail("Suggested Direction") != "Pending" {
                Text("Suggested direction: \(observationDetail("Suggested Direction"))")
                    .font(.caption)
                    .foregroundStyle(SecondTheme.secondaryText)
            }

            if observationDetail("Key Signals") != "Pending" {
                Text("Key signals: \(observationDetail("Key Signals"))")
                    .font(.caption2)
                    .foregroundStyle(SecondTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var arcView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(observationDetail("Arc Title"))
                .font(.title3)
                .bold()

            MetricRow(label: "Start", value: observationDetail("Arc Start"))
            MetricRow(label: "Middle", value: observationDetail("Arc Middle"))
            MetricRow(label: "End", value: observationDetail("Arc End"))

            Text(observationDetail("Reflection Arc"))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            if observationDetail("Arc Key Events") != "Pending" && !observationDetail("Arc Key Events").isEmpty {
                Text("Evidence: \(observationDetail("Arc Key Events"))")
                    .font(.caption2)
                    .foregroundStyle(SecondTheme.secondaryText)
            }
        }
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

    private var evidenceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Emotional Trajectory")
            Text(observationDetail("Trajectory Title"))
                .font(.subheadline)
                .bold()

            Text(observationDetail("Emotional Trajectory"))
                .font(.caption)
                .foregroundStyle(SecondTheme.secondaryText)

            MetricRow(label: "Movement", value: observationDetail("Trajectory Movement"))
            MetricRow(label: "Start", value: observationDetail("Trajectory Start"))
            MetricRow(label: "End", value: observationDetail("Trajectory End"))

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

                        Text(ObservationEventEngine.categorySummary(group.category, events: group.events))
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)

                        ForEach(group.events.prefix(5)) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(event.timestamp.shortTimeWithSeconds) • \(event.title)")
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

                    Text(correlation.summary)
                        .font(.caption2)
                        .foregroundStyle(SecondTheme.secondaryText)
                }
            }
        }
    }

    private var diagnosticsView: some View {
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

    private var primaryInsight: String {
        let arcTitle = observationDetail("Arc Title")
        if arcTitle != "Pending" && arcTitle != "No clear arc" {
            return arcTitle
        }

        let trajectoryTitle = observationDetail("Trajectory Title")
        if trajectoryTitle != "Pending" && trajectoryTitle != "No clear trajectory" {
            return trajectoryTitle
        }

        let observedPattern = observationDetail("Observed Pattern")
        if observedPattern != "Pending" {
            return observedPattern
        }

        return "No clear pattern detected yet."
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func observationDetail(_ title: String) -> String {
        session.observations.first(where: { $0.title == title })?.detail ?? "Pending"
    }
}

