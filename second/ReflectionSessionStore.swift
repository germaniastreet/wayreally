import Foundation
import SwiftUI
import Combine

@MainActor
final class ReflectionSessionStore: ObservableObject {
    @Published var activeSession: ReflectionSession?

    /// Persisted to disk on every change (see saveCompletedSessions()) so a
    /// finished reflection survives an app relaunch, phone restart, or the
    /// app being terminated in the background. Previously this was in-memory
    /// only, which meant completed reflections were silently lost the moment
    /// the app process ended -- see PROJECT_ARCHITECTURE.md section 5.
    @Published var completedSessions: [ReflectionSession] {
        didSet {
            saveCompletedSessions()
        }
    }

    private var lastTranscriptUpdateDate: Date?
    private var lastTranscriptText: String = ""

    init() {
        // Start honestly empty when there's no saved history yet, rather
        // than showing fabricated demo content that looks indistinguishable
        // from real personal reflections (see PROJECT_CONSTRAINTS.md honesty
        // principle -- this was confusing/concerning to a real user in
        // practice once real data was lost and demo data resurfaced).
        completedSessions = Self.loadPersistedSessions() ?? []
    }

    var isRecording: Bool {
        activeSession?.state == .recording
    }

    func startReflection() {
        let start = Date()
        lastTranscriptUpdateDate = nil
        lastTranscriptText = ""

        let emptyWindow = BiometricWindow(queryStart: start, queryEnd: start, samples: [], quality: .unavailable)

        activeSession = ReflectionSession(
            title: "Live Reflection",
            startedAt: start,
            endedAt: nil,
            state: .recording,
            transcript: [],
            observations: [],
            observationEvents: [],
            dynamicsPatterns: [],
            observationCorrelations: [],
            observationEngineVersion: ObservationEventEngine.engineVersion,
            dynamicsEngineVersion: DynamicsEngine.engineVersion,
            correlationEngineVersion: CorrelationEngine.engineVersion,
            biometrics: emptyWindow,
            voice: VoiceSignals(wordsPerMinute: 0, pauseCount: 0, hesitationMarkers: 0, durationSeconds: 0)
        )
    }

    func updateLiveTranscript(_ text: String) {
        guard var session = activeSession, session.state == .recording else { return }

        let now = Date()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }

        if trimmed == lastTranscriptText {
            activeSession = session
            return
        }

        if let lastDate = lastTranscriptUpdateDate {
            let gap = now.timeIntervalSince(lastDate)

            if gap >= 1.5 {
                session.observationEvents.append(
                    ObservationEvent(
                        timestamp: now,
                        kind: .pauseGap,
                        category: .voice,
                        title: "Pause gap",
                        detail: String(format: "Possible pause or silence gap of %.1f seconds before speech resumed.", gap),
                        source: .acoustic,
                        confidence: gap >= 2.5 ? .medium : .low,
                        relatedText: lastTranscriptText.isEmpty ? nil : lastTranscriptText,
                        tags: ["pause", "silence", "speech-timing"],
                        engineVersion: ObservationEventEngine.engineVersion
                    )
                )
            }
        }

        if let lastIndex = session.transcript.indices.last,
           session.transcript[lastIndex].source == .transcript {
            session.transcript[lastIndex].text = trimmed
            session.transcript[lastIndex].timestamp = now
        } else {
            session.transcript.append(
                TranscriptEvent(timestamp: now, speaker: .user, text: trimmed, source: .transcript)
            )
        }

        lastTranscriptUpdateDate = now
        lastTranscriptText = trimmed
        activeSession = session
    }

    func stopAndObserve() {
        guard var session = activeSession else { return }

        let end = Date()
        session.endedAt = end
        session.state = .completed
        session.title = "Reflection at \(session.startedAt.displayTime)"
        session.observationEngineVersion = ObservationEventEngine.engineVersion
        session.dynamicsEngineVersion = DynamicsEngine.engineVersion
        session.correlationEngineVersion = CorrelationEngine.engineVersion

        session.transcript = session.transcript.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if session.transcript.isEmpty {
            if !lastTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.transcript.append(
                    TranscriptEvent(timestamp: end, speaker: .user, text: lastTranscriptText, source: .transcript)
                )
            } else {
                session.transcript.append(
                    TranscriptEvent(timestamp: session.startedAt, speaker: .user, text: "No speech was captured for this reflection.", source: .userMarker)
                )
            }
        }

        session.biometrics = BiometricWindow(queryStart: session.startedAt, queryEnd: end, samples: [], quality: .unavailable)

        session.observationEvents = ObservationEventEngine.enrich(session: session)
        session.dynamicsPatterns = DynamicsEngine.analyze(session: session)
        session.observationCorrelations = CorrelationEngine.analyze(session: session)

        let analysis = ReflectionAnalyzer.analyze(session: session)
        let summary = ReflectionSummaryEngine.analyze(session: session)
        let trajectory = EmotionalTrajectoryEngine.analyze(session: session)
        let arc = ReflectionArcEngine.analyze(session: session)

        let enhancedSummary: String
        if arc.title != "No clear arc" {
            enhancedSummary = "\(summary.summary) Reflection arc: \(arc.detail)"
        } else if trajectory.title != "No clear trajectory" {
            enhancedSummary = "\(summary.summary) Emotional trajectory: \(trajectory.detail)"
        } else {
            enhancedSummary = summary.summary
        }

        session.observations = [
            Observation(title: "Reflection Summary", detail: enhancedSummary, confidence: summary.confidence),
            Observation(title: "Reflection Arc", detail: arc.detail, confidence: arc.confidence),
            Observation(title: "Arc Title", detail: arc.title, confidence: arc.confidence),
            Observation(title: "Arc Sequence", detail: arc.sequence, confidence: arc.confidence),
            Observation(title: "Arc Start", detail: arc.startPhase, confidence: arc.confidence),
            Observation(title: "Arc Middle", detail: arc.middlePhase, confidence: arc.confidence),
            Observation(title: "Arc End", detail: arc.endPhase, confidence: arc.confidence),
            Observation(title: "Arc Key Events", detail: arc.keyEvents.joined(separator: ", "), confidence: arc.confidence),
            Observation(title: "Emotional Trajectory", detail: trajectory.detail, confidence: trajectory.confidence),
            Observation(title: "Trajectory Title", detail: trajectory.title, confidence: trajectory.confidence),
            Observation(title: "Trajectory Movement", detail: trajectory.movement, confidence: trajectory.confidence),
            Observation(title: "Trajectory Start", detail: trajectory.startState, confidence: trajectory.confidence),
            Observation(title: "Trajectory End", detail: trajectory.endState, confidence: trajectory.confidence),
            Observation(title: "Trajectory Phrases", detail: trajectory.keyPhrases.joined(separator: ", "), confidence: trajectory.confidence),
            Observation(title: "Observed Pattern", detail: summary.observedPattern, confidence: summary.confidence),
            Observation(title: "Suggested Direction", detail: summary.suggestedDirection, confidence: summary.confidence),
            Observation(title: "Key Signals", detail: summary.keySignals.joined(separator: ", "), confidence: summary.confidence),
            Observation(title: "Observatory Note", detail: analysis.observatoryNote, confidence: analysis.confidence),
            Observation(title: "Emotional Tone", detail: analysis.emotionalTone, confidence: analysis.confidence),
            Observation(title: "Cognitive Load", detail: analysis.cognitiveLoad, confidence: analysis.confidence),
            Observation(title: "Focus Signal", detail: analysis.focusSignal, confidence: analysis.confidence)
        ]

        let pauseCount = session.observationEvents.filter { $0.kind == .pauseGap }.count

        session.voice = VoiceSignals(
            wordsPerMinute: analysis.wordsPerMinute,
            pauseCount: pauseCount,
            hesitationMarkers: analysis.hesitationMarkers,
            durationSeconds: session.durationSeconds
        )

        completedSessions.insert(session, at: 0)
        activeSession = session
    }

    func resetActiveSession() {
        activeSession = nil
        lastTranscriptUpdateDate = nil
        lastTranscriptText = ""
    }

    // MARK: - Persistence

    private func saveCompletedSessions() {
        do {
            let url = Self.storeURL()
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let data = try JSONEncoder.reflectionSessionEncoder.encode(completedSessions)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Reflection session store save failed: \(error.localizedDescription)")
        }
    }

    private static func loadPersistedSessions() -> [ReflectionSession]? {
        let url = storeURL()

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder.reflectionSessionDecoder.decode([ReflectionSession].self, from: data)
            return decoded.isEmpty ? nil : decoded
        } catch {
            print("Reflection session store load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func storeURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("WayReally", isDirectory: true)
            .appendingPathComponent("completed_reflections_v1.json")
    }
}

private extension JSONEncoder {
    static var reflectionSessionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var reflectionSessionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
