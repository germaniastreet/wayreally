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

    /// Treat a gap this long or longer between two recognized utterances as
    /// a real pause worth recording as evidence. Utterance timing comes from
    /// SFSpeechRecognizer's own segment timestamps (real positions within
    /// its audio stream), not from when SpeechRecognitionManager's callback
    /// happened to run -- so unlike the previous implementation, this isn't
    /// measuring callback/scheduling jitter. It's still not true acoustic
    /// silence detection (no energy/VAD analysis of the raw waveform), so
    /// these are recorded at `.low`/`.medium` confidence rather than
    /// `.high` -- see PROJECT_CONSTRAINTS.md and the review this responds
    /// to (finding 2, "Pause gap observations do not measure acoustic
    /// pauses").
    private let minimumObservablePause: TimeInterval = 1.5

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

    /// Starts a new reflection. `consentAcknowledgedAt` is the moment the
    /// person confirmed (via the confirmation prompt) that anyone else being
    /// recorded knows about it and agreed -- stored on the session as part
    /// of its evidence trail. Returns the filename SpeechRecognitionManager
    /// should record this reflection's raw audio to, so both sides agree on
    /// where it lives without any extra round trip after stopping.
    @discardableResult
    func startReflection(consentAcknowledgedAt: Date) -> String {
        let start = Date()

        let emptyWindow = BiometricWindow(queryStart: start, queryEnd: start, samples: [], quality: .unavailable)

        var session = ReflectionSession(
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
            voice: VoiceSignals(wordsPerMinute: 0, pauseCount: 0, hesitationMarkers: 0, durationSeconds: 0),
            consentAcknowledgedAt: consentAcknowledgedAt
        )

        let audioFileName = "\(session.id.uuidString).caf"
        session.audioFileName = audioFileName
        activeSession = session
        return audioFileName
    }

    /// Reconciles the live utterance list (delivered in full, from
    /// SpeechRecognitionManager, on every speech callback) against this
    /// session's transcript. Earlier utterances are done growing --
    /// SFSpeechRecognizer only ever revises the most recent one -- so only
    /// the final entry's text/timestamp actually needs to keep updating in
    /// place; anything new past the current count is appended. Each
    /// utterance keeps its own real, stable start time (see
    /// SpeechRecognitionManager.Utterance), which is what makes per-speaker
    /// diarization mapping meaningful afterwards -- previously this method
    /// collapsed an entire reflection into one transcript event whose
    /// timestamp kept sliding forward to "now," so diarization could only
    /// ever assign one speaker label to the whole conversation (review
    /// finding 1).
    func updateLiveTranscript(_ utterances: [SpeechRecognitionManager.Utterance]) {
        guard var session = activeSession, session.state == .recording else { return }
        guard !utterances.isEmpty else { return }

        var transcriptIndices = session.transcript.indices.filter { session.transcript[$0].source == .transcript }

        // Emit a pause-gap observation for any newly-visible gap between
        // consecutive utterances that's long enough to be meaningful. Only
        // gaps at or past `transcriptIndices.count` are new -- earlier ones
        // were already recorded on a previous call, since this whole
        // utterance list is re-delivered every time.
        if utterances.count > 1 {
            for index in max(1, transcriptIndices.count)..<utterances.count {
                let gap = utterances[index].start.timeIntervalSince(utterances[index - 1].end)
                guard gap >= minimumObservablePause else { continue }

                session.observationEvents.append(
                    ObservationEvent(
                        timestamp: utterances[index - 1].end,
                        kind: .pauseGap,
                        category: .voice,
                        title: "Pause gap",
                        detail: String(format: "Possible pause or silence gap of %.1f seconds before speech resumed.", gap),
                        source: .acoustic,
                        confidence: gap >= 2.5 ? .medium : .low,
                        relatedText: utterances[index - 1].text,
                        tags: ["pause", "silence", "speech-timing"],
                        engineVersion: ObservationEventEngine.engineVersion
                    )
                )
            }
        }

        for (i, utterance) in utterances.enumerated() {
            if i < transcriptIndices.count {
                let idx = transcriptIndices[i]
                session.transcript[idx].text = utterance.text
                session.transcript[idx].timestamp = utterance.start
            } else {
                session.transcript.append(
                    TranscriptEvent(timestamp: utterance.start, speaker: .user, text: utterance.text, source: .transcript)
                )
                transcriptIndices.append(session.transcript.count - 1)
            }
        }

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
            session.transcript.append(
                TranscriptEvent(timestamp: session.startedAt, speaker: .user, text: "No speech was captured for this reflection.", source: .userMarker)
            )
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

        // Speaker identification runs after the fact, on the audio file
        // SpeechRecognitionManager saved alongside the transcript -- it can
        // take a moment (on-device ML inference), so it happens here as a
        // background step rather than blocking Stop & Observe. Every
        // transcript entry starts as `.user`; this only changes that if
        // diarization actually finds more than one voice.
        let sessionForDiarization = session
        Task {
            let labeled = await SpeakerDiarizationEngine.label(session: sessionForDiarization)
            self.applyDiarizedTranscript(labeled)
        }
    }

    /// Patches in speaker labels found by SpeakerDiarizationEngine after the
    /// fact. Only ever touches transcript speaker tags and the diarization
    /// engine version -- never re-runs the analysis engines, which already
    /// ran against the transcript at Stop time.
    private func applyDiarizedTranscript(_ labeled: ReflectionSession) {
        if let index = completedSessions.firstIndex(where: { $0.id == labeled.id }) {
            completedSessions[index].transcript = labeled.transcript
            completedSessions[index].diarizationEngineVersion = labeled.diarizationEngineVersion
        }

        if activeSession?.id == labeled.id {
            activeSession?.transcript = labeled.transcript
            activeSession?.diarizationEngineVersion = labeled.diarizationEngineVersion
        }
    }

    func resetActiveSession() {
        activeSession = nil
    }

    // MARK: - Deletion & export (PROJECT_CONSTRAINTS.md #12: users must be
    // able to understand, control, export, and remove their data)

    /// Deletes one completed reflection and its associated raw audio file,
    /// if it has one. Safe to call even if the audio file is already
    /// missing.
    func deleteReflection(_ session: ReflectionSession) {
        completedSessions.removeAll { $0.id == session.id }
        if let audioFileName = session.audioFileName {
            Self.deleteAudioFile(named: audioFileName)
        }
    }

    /// Wipes every completed reflection this app knows about, plus every
    /// file in the reflection Audio directory -- including any orphaned
    /// `.caf` left behind by a past crash or bug, which per-reflection
    /// deletion above can't reach since it only knows about files a
    /// still-referenced session points to. This is an explicit, confirmed,
    /// all-or-nothing action; there is no soft/partial version.
    func deleteAllData() {
        completedSessions = []
        Self.deleteAllAudioFiles()
    }

    /// Builds one JSON export covering every completed reflection's
    /// transcript, observations, evidence, and consent/provenance metadata.
    /// Raw audio is intentionally not included -- it would make the export
    /// file large and is also the most sensitive part of a reflection;
    /// exporting the record of what was said and observed doesn't require
    /// exporting the recording itself.
    func exportAllReflectionsJSON() -> URL? {
        do {
            let data = try JSONEncoder.reflectionSessionEncoder.encode(completedSessions)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("WayReally-Export-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            print("Reflection export failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func deleteAudioFile(named fileName: String) {
        let url = SpeechRecognitionManager.audioFileURL(named: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private static func deleteAllAudioFiles() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let audioDirectory = baseURL
            .appendingPathComponent("WayReally", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.removeItem(at: audioDirectory)
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
