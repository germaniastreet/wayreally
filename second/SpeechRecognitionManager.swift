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

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStoppingIntentionally = false
    private var lastNonEmptyTranscript = ""

    /// This reflection's raw audio, written alongside the live speech-to-text
    /// so a later step (speaker diarization) has real audio to work from --
    /// SFSpeechRecognizer only ever gives us text back, never the audio.
    private var audioFile: AVAudioFile?
    private var pendingAudioFileURL: URL?

    /// Everything finalized from earlier listening segments in this recording.
    /// Apple's speech engine ends a "segment" (an SFSpeechRecognitionTask) on
    /// its own after roughly a minute of continuous speech, and an
    /// interruption (call, Siri, another app) also forcibly ends a segment.
    /// Rather than treating either as the end of the reflection, we fold the
    /// finished segment's text in here and quietly start a new segment, so
    /// the transcript reads as one continuous recording to the user.
    private var accumulatedTranscript = ""

    private var currentOnTranscript: (@MainActor (String) -> Void)?
    private var wasRecordingBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
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
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
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

    func start(audioFileName: String, onTranscript: @escaping @MainActor (String) -> Void) {
        currentOnTranscript = onTranscript
        accumulatedTranscript = ""
        lastNonEmptyTranscript = ""
        liveTranscript = ""
        isStoppingIntentionally = false
        wasRecordingBeforeInterruption = false
        audioFile = nil
        pendingAudioFileURL = Self.audioFileURL(named: audioFileName)

        beginListeningSegment()
    }

    private static func audioFileURL(named fileName: String) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("WayReally", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Starts (or restarts) one listening segment. Safe to call whether or
    /// not a previous segment is still technically running — it tears down
    /// any existing engine/tap/request first, so this is the single entry
    /// point used for the initial start, resuming after an interruption, and
    /// quietly continuing past Apple's ~1 minute segment limit.
    private func beginListeningSegment() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusMessage = "Speech recognizer unavailable."
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

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

            // Captured as a local constant rather than reached for via `self`
            // inside the closure below -- this tap callback fires on a
            // real-time audio thread, not the main actor this class is
            // otherwise isolated to, so it must not touch `self` directly.
            let fileForThisSegment = audioFile

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
                if let fileForThisSegment {
                    try? fileForThisSegment.write(from: buffer)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            statusMessage = "Listening."
            lastNonEmptyTranscript = ""

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleRecognition(result: result, error: error)
                }
            }
        } catch {
            statusMessage = "Speech start failed: \(error.localizedDescription)"
            stop()
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                lastNonEmptyTranscript = text
                let combined = combinedTranscript(with: text)
                liveTranscript = combined
                statusMessage = result.isFinal ? "Final transcript received." : "Listening."
                currentOnTranscript?(combined)
            } else if result.isFinal, !lastNonEmptyTranscript.isEmpty {
                let combined = combinedTranscript(with: lastNonEmptyTranscript)
                statusMessage = "Final transcript received."
                currentOnTranscript?(combined)
            }
        }

        guard let error else { return }

        if isStoppingIntentionally {
            statusMessage = "Speech capture stopped."
            if !lastNonEmptyTranscript.isEmpty {
                currentOnTranscript?(combinedTranscript(with: lastNonEmptyTranscript))
            }
            return
        }

        if wasRecordingBeforeInterruption {
            // The system is mid-interruption (a call, Siri, or another app
            // just took the microphone). This segment ending is expected —
            // handleInterruption(_:) will restart listening once the
            // interruption ends, so don't treat this as a failure.
            return
        }

        if isRecording {
            // Not an interruption — most likely Apple's speech engine ending
            // this segment on its own after continuous speech. Fold what we
            // have and quietly keep going instead of stopping the reflection.
            foldSegmentIntoAccumulatedTranscript()
            statusMessage = "Listening (continuing)."
            beginListeningSegment()
        } else {
            statusMessage = "Speech error: \(error.localizedDescription)"
            stop()
        }
    }

    private func combinedTranscript(with segmentText: String) -> String {
        accumulatedTranscript.isEmpty ? segmentText : accumulatedTranscript + " " + segmentText
    }

    private func foldSegmentIntoAccumulatedTranscript() {
        guard !lastNonEmptyTranscript.isEmpty else { return }
        accumulatedTranscript = combinedTranscript(with: lastNonEmptyTranscript)
        lastNonEmptyTranscript = ""
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            guard isRecording else { return }
            wasRecordingBeforeInterruption = true
            foldSegmentIntoAccumulatedTranscript()

            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            recognitionTask = nil
            isRecording = false
            statusMessage = "Paused — interrupted (call, Siri, or another app)."

        case .ended:
            guard wasRecordingBeforeInterruption else { return }
            wasRecordingBeforeInterruption = false

            var shouldResume = false
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
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
