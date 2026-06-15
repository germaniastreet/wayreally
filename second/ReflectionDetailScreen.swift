import SwiftUI

struct ReflectionDetailScreen: View {
    let session: ReflectionSession

    var body: some View {
        ZStack {
            SecondTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(
                        title: session.title,
                        subtitle: "\(session.timeRangeText) • \(session.durationText)"
                    )

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
                        observationEventsView
                    }
                    .padding(.horizontal)

                    AppCard(title: "Session State") {
                        VStack(spacing: 8) {
                            MetricRow(label: "State", value: session.state.rawValue.capitalized)
                            MetricRow(label: "Boundary", value: session.endedAt == nil ? "Open" : "Closed")
                            MetricRow(label: "Duration", value: session.durationText)
                            MetricRow(label: "Observation engine", value: session.observationEngineVersion)
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

                    AppCard(title: "Body Signals") {
                        VStack(spacing: 12) {
                            Text("Body signals from \(session.biometrics.queryStart.shortTimeWithSeconds)–\(session.biometrics.queryEnd.shortTimeWithSeconds)")
                                .font(.caption)
                                .foregroundStyle(SecondTheme.secondaryText)

                            if session.biometrics.samples.isEmpty {
                                Text("No biometric samples attached to this session.")
                                    .font(.caption)
                                    .foregroundStyle(SecondTheme.secondaryText)
                            } else {
                                MetricRow(label: "Heart Rate", value: "\(Int(session.biometrics.latestHeartRate)) bpm", color: SecondTheme.heartRate)
                                MiniLineChart(values: session.biometrics.samples.compactMap { $0.heartRate }, color: SecondTheme.heartRate)

                                MetricRow(label: "Respiration", value: String(format: "%.1f brpm", session.biometrics.averageRespiration), color: SecondTheme.respiration)
                                MiniLineChart(values: session.biometrics.samples.compactMap { $0.respiration }, color: SecondTheme.respiration)

                                MetricRow(label: "HRV", value: "\(Int(session.biometrics.averageHRV)) ms", color: SecondTheme.hrv)
                                MiniLineChart(values: session.biometrics.samples.compactMap { $0.hrv }, color: SecondTheme.hrv)
                            }
                        }
                    }
                    .padding(.horizontal)

                    AppCard(title: "Observatory Note") {
                        Text(session.observations.first(where: { $0.title == "Observatory Note" })?.detail ?? "No observatory note.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Reflection")
        .navigationBarTitleDisplayMode(.inline)
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

    private func observationDetail(_ title: String) -> String {
        session.observations.first(where: { $0.title == title })?.detail ?? "Pending"
    }
}

