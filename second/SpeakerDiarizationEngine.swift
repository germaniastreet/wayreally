import Foundation
import SpeakerKit
import WhisperKit // AudioProcessor.loadAudioAsFloatArray lives here, not in SpeakerKit itself

/// Runs after a reflection is stopped, using the raw audio file saved by
/// SpeechRecognitionManager to figure out which parts of the transcript came
/// from different speakers. Uses Argmax's open-source SpeakerKit (Pyannote
/// v4 community-1, on-device, MIT license -- see the multi-speaker capture
/// research this was built from) -- entirely separate from live
/// transcription, which SFSpeechRecognizer already finished producing by the
/// time this runs.
///
/// Honesty note (PROJECT_CONSTRAINTS.md #5, #9): this only ever tells voices
/// apart -- it has no way to know which voice is the phone's owner, so a
/// transcript stays entirely `.user` unless diarization actually finds more
/// than one *distinct* voice. When it does, every entry (including the
/// owner's) gets re-labeled as "Speaker 1", "Speaker 2", etc., since
/// asserting one of them is specifically "You" would be presenting a guess
/// as a fact.
///
/// IMPORTANT: this is the one file in WayReally built against a third-party
/// package's exact API without a compiler available here to verify it. If
/// Xcode reports a "has no member" or "cannot find type" error anywhere in
/// this file, that's expected -- the fix is almost certainly a one- or
/// two-line rename once the real member name is visible in the error.
enum SpeakerDiarizationEngine {
    static let engineVersion = "0.2"

    /// Re-labels `session.transcript` by speaker, using the session's saved
    /// audio file. Returns the session unchanged (still nil
    /// diarizationEngineVersion) if there's no audio file, diarization finds
    /// only one distinct voice, or anything fails -- speaker labeling is a
    /// layer on top of a transcript that already works fine without it.
    static func label(session: ReflectionSession) async -> ReflectionSession {
        var session = session

        guard let audioFileName = session.audioFileName else { return session }
        let audioURL = Self.audioFileURL(named: audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return session }

        do {
            let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
            let speakerKit = try await SpeakerKit()
            let result = try await speakerKit.diarize(audioArray: audioArray)

            let segments = Self.parseSegments(from: result, fileName: audioFileName)
            guard !segments.isEmpty else { return session }

            // A recording with exactly one voice can still produce more than
            // one RTTM segment (the same speaker turning on and off) -- so
            // checking segment *count* alone (the previous behavior) could
            // relabel a single-speaker session away from `.user` just
            // because diarization emitted multiple same-speaker segments.
            // What actually matters is whether more than one *distinct*
            // speaker identifier was found.
            let distinctSpeakers = Set(segments.map(\.label))
            guard distinctSpeakers.count >= 2 else { return session }

            session.transcript = session.transcript.map { event in
                var event = event
                let offset = event.timestamp.timeIntervalSince(session.startedAt)
                if let match = segments.first(where: { offset >= $0.start && offset <= $0.end }) {
                    event.speaker = .other(match.label)
                }
                return event
            }
            session.diarizationEngineVersion = engineVersion
        } catch {
            print("Speaker diarization failed: \(error.localizedDescription)")
        }

        return session
    }

    private struct ParsedSegment {
        let start: Double
        let end: Double
        let label: String
    }

    /// SpeakerKit.generateRTTM produces the standard, industry-wide RTTM
    /// text format (`SPEAKER <file> <channel> <start> <duration> <NA> <NA>
    /// <speaker-id> <NA> <NA>`) -- parsed here directly rather than reading
    /// DiarizationResult's own Swift properties, since RTTM's field layout
    /// is a stable, documented format independent of this package's exact
    /// internal API (which this codebase can't fully verify without a
    /// compiler available).
    private static func parseSegments(from result: DiarizationResult, fileName: String) -> [ParsedSegment] {
        let rttmLines = SpeakerKit.generateRTTM(from: result, fileName: fileName)

        return rttmLines.compactMap { line -> ParsedSegment? in
            let fields = line.description.split(separator: " ").map(String.init)
            guard fields.count >= 8, fields[0] == "SPEAKER",
                  let start = Double(fields[3]), let duration = Double(fields[4]) else {
                return nil
            }

            let token = fields[7]
            let normalized = token
                .replacingOccurrences(of: "speaker_", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "speaker", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_ "))
            let label = normalized.isEmpty ? "Speaker (\(token))" : "Speaker \(normalized)"

            return ParsedSegment(start: start, end: start + duration, label: label)
        }
    }

    private static func audioFileURL(named fileName: String) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("WayReally", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
