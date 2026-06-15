import Foundation
import SwiftUI
import Combine

@MainActor
final class ReflectionSessionStore: ObservableObject {
    @Published var activeSession: ReflectionSession?
    @Published var completedSessions: [ReflectionSession] = SampleData.sessions

    private var lastTranscriptUpdateDate: Date?
    private var lastTranscriptText: String = ""

    var isRecording: Bool {
        activeSession?.state == .recording
    }

    func startReflection() {
        let start = Date()
        lastTranscriptUpdateDate = nil
        lastTranscriptText = ""

        let emptyWindow = BiometricWindow(
            queryStart: start,
            queryEnd: start,
            samples: [],
            quality: .unavailable
        )

        activeSession = ReflectionSession(
            title: "Live Reflection",
            startedAt: start,
            endedAt: nil,
            state: .recording,
            transcript: [],
            observations: [],
            observationEvents: [],
            observationEngineVersion: ObservationEventEngine.engineVersion,
            biometrics: emptyWindow,
            voice: VoiceSignals(
                wordsPerMinute: 0,
                pauseCount: 0,
                hesitationMarkers: 0,
                durationSeconds: 0
            )
        )
    }

    func updateLiveTranscript(_ text: String) {
        print("TRANSCRIPT RECEIVED BY STORE:")
        print(text)

        guard var session = activeSession, session.state == .recording else { return }

        let now = Date()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            print("STORE IGNORED EMPTY TRANSCRIPT")
            return
        }

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
                TranscriptEvent(
                    timestamp: now,
                    speaker: .user,
                    text: trimmed,
                    source: .transcript
                )
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
        session.title = "Reflection at \(session.startedAt.shortTime)"
        session.observationEngineVersion = ObservationEventEngine.engineVersion

        session.transcript = session.transcript.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if session.transcript.isEmpty {
            if !lastTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.transcript.append(
                    TranscriptEvent(
                        timestamp: end,
                        speaker: .user,
                        text: lastTranscriptText,
                        source: .transcript
                    )
                )
            } else {
                session.transcript.append(
                    TranscriptEvent(
                        timestamp: session.startedAt,
                        speaker: .user,
                        text: "No speech was captured for this reflection.",
                        source: .userMarker
                    )
                )
            }
        }

        session.biometrics = BiometricWindow(
            queryStart: session.startedAt,
            queryEnd: end,
            samples: [],
            quality: .unavailable
        )

        session.observationEvents = ObservationEventEngine.enrich(session: session)

        let analysis = ReflectionAnalyzer.analyze(session: session)

        session.observations = [
            Observation(title: "Observed Pattern", detail: analysis.observedPattern, confidence: analysis.confidence),
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
}

