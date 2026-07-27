import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var statusMessage = "Speech not started."
    @Published var permissionDenied = false

    /// One chunk of recognized speech with real audio-relative timing.
    /// `start`/`end` are derived from SFSpeechRecognizer's own
    /// `SFTranscriptionSegment.timestamp`/`.duration` (positions within the
    /// recognizer's own audio stream), not from when this app's callback
    /// happened to be scheduled -- so unlike timing based on callback
    /// arrival, these hold up as real time boundaries even under CPU or
    /// dispatch-queue jitter. This is what makes it possible for
    /// SpeakerDiarizationEngine to map a diarization time segment onto more
    /// than one utterance, and for pause-gap detection to reflect actual
    /// gaps between recognized speech instead of gaps between callbacks.
    ///
    /// A growing (not-yet-finished) utterance keeps the same `start` across
    /// callbacks -- SFSpeechRecognizer's already-reported word timestamps
    /// don't get revised, only later words get appended -- so `start` is
    /// stable the moment an utterance first appears, not just once it ends.
    struct Utterance {
        var text: String
        var start: Date
        var end: Date
    }

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStoppingIntentionally = false

    /// This reflection's raw audio, written alongside the live speech-to-text
    /// so a later step (speaker diarization) has real audio to work from --
    /// SFSpeechRecognizer only ever gives us text back, never the audio.
    private var audioFile: AVAudioFile?
    private var pendingAudioFileURL: URL?

    /// Thread-safe target for the audio tap's buffer callback, which fires on
    /// a real-time audio thread outside this class's `@MainActor` isolation.
    /// The tap itself is installed exactly once (in the first call to
    /// `beginListeningSegment()`) and is never torn down at a routine segment
    /// boundary -- only this box's contents change, atomically under a lock,
    /// when a new segment's request replaces the previous one. That's what
    /// keeps the mic capturing continuously across Apple's ~1 minute segment
    /// limit instead of stopping and restarting the engine, which previously
    /// left a real gap (stop → remove tap → reconfigure session → reinstall
    /// tap → start) during which speech at the seam was silently dropped --
    /// the leading suspect for transcript quality degrading right around the
    /// one-minute mark.
    private final class CurrentRequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        private var audioFile: AVAudioFile?

        /// Swaps in the new request/file and returns whatever was previously
        /// set, still under the same lock the tap callback uses -- so by the
        /// time this returns, no in-flight tap callback can still be holding
        /// a reference to the old request. That guarantees it's safe for the
        /// caller to call `endAudio()` on the returned previous request right
        /// after this returns, without racing a concurrent `append(_:)` on
        /// the audio thread (which would throw).
        @discardableResult
        func set(request: SFSpeechAudioBufferRecognitionRequest?, audioFile: AVAudioFile?) -> SFSpeechAudioBufferRecognitionRequest? {
            lock.lock()
            defer { lock.unlock() }
            let previous = self.request
            self.request = request
            self.audioFile = audioFile
            return previous
        }

        /// Called from the audio tap on a real-time thread for every buffer.
        /// Appending and the raw-audio file write both happen under the same
        /// lock `set(request:audioFile:)` uses, so a segment swap can never
        /// interleave with an in-progress append.
        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock()
            defer { lock.unlock() }
            request?.append(buffer)
            if let audioFile {
                try? audioFile.write(from: buffer)
            }
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            request = nil
            audioFile = nil
        }
    }

    private let currentRequestBox = CurrentRequestBox()

    /// Utterances finalized from earlier listening segments in this
    /// recording. Apple's speech engine ends a "segment" (an
    /// SFSpeechRecognitionTask) on its own after roughly a minute of
    /// continuous speech, and an interruption (call, Siri, another app) also
    /// forcibly ends a segment. Rather than treating either as the end of
    /// the reflection, we seal whatever utterances that segment produced in
    /// here and quietly start a new segment, so the transcript reads as one
    /// continuous recording to the user.
    ///
    /// Known limitation: while a segment is paused for an interruption, the
    /// raw .caf audio file also isn't being written to (the mic tap is torn
    /// down), so the file itself has no gap for that pause -- but these
    /// utterance timestamps are wall-clock and DO include it. For a
    /// recording with no interruptions (the common case) this doesn't
    /// matter; for one that was interrupted, diarization's audio-relative
    /// segment offsets and these wall-clock utterance offsets can drift
    /// apart by roughly the interruption's length. Not fixed here -- it's a
    /// separate, second-order issue from the one this rewrite addresses.
    private var sealedUtterances: [Utterance] = []

    /// Utterances recognized so far in the *current* segment, recomputed in
    /// full from `SFSpeechRecognitionResult.bestTranscription.segments`
    /// every time a new result arrives (that array only ever grows within a
    /// segment, so this is cheap and always consistent).
    private var currentSegmentUtterances: [Utterance] = []

    /// Wall-clock instant the current segment's audio actually started
    /// (right after `audioEngine.start()` succeeds, or immediately after a
    /// mid-stream segment swap that doesn't restart the engine) -- lets us
    /// convert a segment-relative `SFTranscriptionSegment.timestamp` into an
    /// absolute `Date`.
    private var segmentAudioStartDate: Date?

    /// Treat a gap this long or longer between two recognized utterances as
    /// a separate utterance rather than a continuation of the same one.
    private static let utteranceGapThreshold: TimeInterval = 0.7

    private var currentOnTranscript: (@MainActor ([Utterance]) -> Void)?
    private var wasRecordingBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            // Pulled out here, before crossing into the Task below, since
            // Notification itself isn't Sendable -- only these two plain
            // values (an enum and a UInt) need to cross that boundary.
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt

            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type, optionsValue: optionsValue)
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            statusMessage = "Speech recognition permission not granted."
            permissionDenied = true
            return false
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard microphoneGranted else {
            statusMessage = "Microphone permission not granted."
            permissionDenied = true
            return false
        }

        permissionDenied = false
        statusMessage = "Speech permissions ready."
        return true
    }

    func start(audioFileName: String, onTranscript: @escaping @MainActor ([Utterance]) -> Void) {
        currentOnTranscript = onTranscript
        sealedUtterances = []
        currentSegmentUtterances = []
        segmentAudioStartDate = nil
        liveTranscript = ""
        isStoppingIntentionally = false
        wasRecordingBeforeInterruption = false
        audioFile = nil
        pendingAudioFileURL = Self.audioFileURL(named: audioFileName)

        beginListeningSegment()
    }

    static func audioFileURL(named fileName: String) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("WayReally", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Starts (or continues into) one listening segment. Used for the
    /// initial start, for resuming after an interruption, and for quietly
    /// continuing past Apple's ~1 minute segment limit.
    ///
    /// Whenever the audio engine is already running -- the routine case of
    /// continuing past the ~1 minute limit -- this does NOT stop it or touch
    /// its tap. It only swaps in a fresh `SFSpeechAudioBufferRecognitionRequest`
    /// (via `currentRequestBox`) and starts a new recognition task against
    /// it, so the mic never stops capturing and no audio at the segment seam
    /// is lost. The engine and tap are only started fresh here when they
    /// aren't already running -- the very first segment, or resuming after an
    /// interruption tore them down.
    private func beginListeningSegment() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusMessage = "Speech recognizer unavailable."
            return
        }

        currentSegmentUtterances = []
        segmentAudioStartDate = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            if audioFile == nil, let pendingAudioFileURL {
                do {
                    try FileManager.default.createDirectory(
                        at: pendingAudioFileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    audioFile = try AVAudioFile(forWriting: pendingAudioFileURL, settings: recordingFormat.settings)
                } catch {
                    // Live transcription still works without this -- diarization
                    // just won't have audio to work from for this reflection.
                    print("Reflection audio recording failed to open: \(error.localizedDescription)")
                    audioFile = nil
                }
            }

            // Atomically swap this segment's request (and the unchanging
            // audio file reference) into the box, then end the *previous*
            // request only after the swap completes. Because `set` and
            // `append` share one lock, this guarantees no tap callback can
            // still be appending to the old request by the time we call
            // `endAudio()` on it below -- avoiding the "append after
            // endAudio" exception that a naive swap could hit.
            let previousRequest = currentRequestBox.set(request: request, audioFile: audioFile)
            recognitionRequest = request

            if audioEngine.isRunning {
                // Routine continuation past the ~1 minute segment limit --
                // the engine and tap stay exactly as they are; only the
                // request/task underneath changes. No stop/start gap.
                previousRequest?.endAudio()
            } else {
                // First segment, or resuming after an interruption tore the
                // engine down -- (re)install the tap and start fresh.
                previousRequest?.endAudio()
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [currentRequestBox] buffer, _ in
                    currentRequestBox.append(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()
            }

            segmentAudioStartDate = Date()

            isRecording = true
            statusMessage = "Listening."

            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                Task { @MainActor [weak self] in
                    self?.handleRecognition(result: result, error: error)
                }
            }
        } catch {
            statusMessage = "Speech start failed: \(error.localizedDescription)"
            stop()
        }
    }

    /// Groups a result's word/phrase-level segments into utterances, using
    /// each segment's own audio-relative timestamp -- splitting wherever the
    /// gap since the previous segment ended is at least
    /// `utteranceGapThreshold`. Because this reads real recognizer segment
    /// timing rather than wall-clock callback arrival, it's the same
    /// grouping every time it's recomputed for a given result, growing only
    /// as new segments are recognized.
    ///
    /// Text for each segment comes from `formattedString` (via
    /// `segment.substringRange`), not `segment.substring` -- the latter is
    /// SFSpeechRecognizer's raw per-word text with none of the
    /// capitalization, punctuation, and smart-formatting Apple normally
    /// applies to `bestTranscription.formattedString`. Reconstructing the
    /// transcript from raw substrings (the original version of this
    /// timestamp rewrite did this) reads as noticeably lower quality even
    /// when every word was recognized correctly. `substringRange` is the
    /// documented way to map a segment back onto its formatted text, so this
    /// keeps the real per-segment timing this rewrite needs while restoring
    /// the same text quality the app had before it.
    private func utterances(from segments: [SFTranscriptionSegment], formattedString: String, segmentStart: Date) -> [Utterance] {
        var result: [Utterance] = []
        let formatted = formattedString as NSString

        for segment in segments {
            let range = segment.substringRange
            let rawText: String
            if range.location != NSNotFound, range.location + range.length <= formatted.length {
                rawText = formatted.substring(with: range)
            } else {
                // Fallback for the rare case a range doesn't line up with
                // the current formattedString -- still correct, just not
                // formatted.
                rawText = segment.substring
            }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let start = segmentStart.addingTimeInterval(segment.timestamp)
            let end = start.addingTimeInterval(segment.duration)

            if let lastIndex = result.indices.last,
               start.timeIntervalSince(result[lastIndex].end) < Self.utteranceGapThreshold {
                result[lastIndex].text += " " + text
                result[lastIndex].end = end
            } else {
                result.append(Utterance(text: text, start: start, end: end))
            }
        }

        return result
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result, let segmentStart = segmentAudioStartDate {
            let segments = result.bestTranscription.segments
            if !segments.isEmpty {
                currentSegmentUtterances = utterances(
                    from: segments,
                    formattedString: result.bestTranscription.formattedString,
                    segmentStart: segmentStart
                )
            }

            let combined = sealedUtterances + currentSegmentUtterances
            if !combined.isEmpty {
                liveTranscript = combined.map(\.text).joined(separator: " ")
                statusMessage = result.isFinal ? "Final transcript received." : "Listening."
                currentOnTranscript?(combined)
            }
        }

        guard let error else { return }

        if isStoppingIntentionally {
            statusMessage = "Speech capture stopped."
            let combined = sealedUtterances + currentSegmentUtterances
            if !combined.isEmpty {
                currentOnTranscript?(combined)
            }
            return
        }

        if wasRecordingBeforeInterruption {
            // The system is mid-interruption (a call, Siri, or another app
            // just took the microphone). This segment ending is expected —
            // handleInterruption(type:optionsValue:) will restart listening once the
            // interruption ends, so don't treat this as a failure.
            return
        }

        if isRecording {
            // Not an interruption — most likely Apple's speech engine ending
            // this segment on its own after continuous speech. Seal what we
            // have and quietly keep going instead of stopping the reflection.
            sealCurrentSegment()
            statusMessage = "Listening (continuing)."
            beginListeningSegment()
        } else {
            statusMessage = "Speech error: \(error.localizedDescription)"
            stop()
        }
    }

    private func sealCurrentSegment() {
        sealedUtterances.append(contentsOf: currentSegmentUtterances)
        currentSegmentUtterances = []
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType, optionsValue: UInt?) {
        switch type {
        case .began:
            guard isRecording else { return }
            wasRecordingBeforeInterruption = true
            sealCurrentSegment()

            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            recognitionRequest?.endAudio()
            currentRequestBox.clear()
            recognitionRequest = nil
            recognitionTask = nil
            isRecording = false
            statusMessage = "Paused — interrupted (call, Siri, or another app)."

        case .ended:
            guard wasRecordingBeforeInterruption else { return }
            wasRecordingBeforeInterruption = false

            var shouldResume = false
            if let optionsValue {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }

            if shouldResume {
                statusMessage = "Resuming after interruption..."
                beginListeningSegment()
            } else {
                statusMessage = "Paused by an interruption. Tap Start to resume."
            }

        @unknown default:
            break
        }
    }

    func stop() {
        isStoppingIntentionally = true
        wasRecordingBeforeInterruption = false

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        currentRequestBox.clear()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        // AVAudioFile has no explicit close() -- releasing it finalizes the
        // file on disk.
        audioFile = nil
        pendingAudioFileURL = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Safe to ignore for prototype.
        }
    }
}
