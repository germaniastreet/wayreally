import SwiftUI

struct ReflectionDetailScreen: View {
    let session: ReflectionSession

    var body: some View {
        ZStack {
            SecondTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(title: session.title, subtitle: "\(session.timeRangeText) • \(session.durationText)")

                    AppCard(title: "Transcript") {
                        VStack(alignment: .leading, spacing: 14) {
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
                    .padding(.horizontal)

                    AppCard(title: "Observed Pattern") {
                        Text(session.observations.first?.detail ?? "No observed pattern.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    AppCard(title: "Reflection Dynamics") {
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
                    .padding(.horizontal)

                    AppCard(title: "Cognition Signals") {
                        VStack(spacing: 8) {
                            MetricRow(label: "Emotional tone", value: observationDetail("Emotional Tone"))
                            MetricRow(label: "Cognitive load", value: observationDetail("Cognitive Load"))
                            MetricRow(label: "Focus signal", value: observationDetail("Focus Signal"))
                            MetricRow(label: "Confidence", value: session.observations.first?.confidence.rawValue.capitalized ?? "Unavailable")
                        }
                    }
                    .padding(.horizontal)

                    AppCard(title: "Observation Events", startsExpanded: true) {
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
                    .padding(.horizontal)

                    AppCard(title: "Session State") {
                        VStack(spacing: 8) {
                            MetricRow(label: "State", value: session.state.rawValue.capitalized)
                            MetricRow(label: "Boundary", value: session.endedAt == nil ? "Open" : "Closed")
                            MetricRow(label: "Duration", value: session.durationText)
                            MetricRow(label: "Observation engine", value: session.observationEngineVersion)
                            MetricRow(label: "Dynamics engine", value: session.dynamicsEngineVersion)
                        }
                    }
                    .padding(.horizontal)

                    AppCard(title: "Voice Signals") {
                        VStack(spacing: 8) {
                            MetricRow(label: "Speech rate", value: session.voice.wordsPerMinute == 0 ? "Pending" : "\(session.voice.wordsPerMinute) WPM")
                            MetricRow(label: "Pause gaps", value: session.voice.pauseCount == 0 ? "None detected" : "\(session.voice.pauseCount)")
                            MetricRow(label: "Hesitation markers", value: session.voice.hesitationMarkers == 0 ? "None detected" : "\(session.voice.hesitationMarkers)")
                            MetricRow(label: "Duration", value: session.durationText)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Reflection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func observationDetail(_ title: String) -> String {
        session.observations.first(where: { $0.title == title })?.detail ?? "Pending"
    }
}
