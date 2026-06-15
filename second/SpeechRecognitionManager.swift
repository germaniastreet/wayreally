import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var statusMessage = "Speech not started."

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStoppingIntentionally = false
    private var lastNonEmptyTranscript = ""

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            statusMessage = "Speech recognition permission not granted."
            return false
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard microphoneGranted else {
            statusMessage = "Microphone permission not granted."
            return false
        }

        statusMessage = "Speech permissions ready."
        return true
    }

    func start(onTranscript: @escaping @MainActor (String) -> Void) {
        stop()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusMessage = "Speech recognizer unavailable."
            return
        }

        isStoppingIntentionally = false
        lastNonEmptyTranscript = ""

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            liveTranscript = ""
            statusMessage = "Listening."

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        let text = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        print("SPEECH ENGINE RESULT:")
                        print(text)

                        if !text.isEmpty {
                            self.lastNonEmptyTranscript = text
                            self.liveTranscript = text
                            self.statusMessage = result.isFinal ? "Final transcript received." : "Listening."
                            onTranscript(text)
                        } else if result.isFinal, !self.lastNonEmptyTranscript.isEmpty {
                            self.statusMessage = "Final transcript received."
                            onTranscript(self.lastNonEmptyTranscript)
                        }
                    }

                    if let error {
                        if self.isStoppingIntentionally {
                            self.statusMessage = "Speech capture stopped."
                            if !self.lastNonEmptyTranscript.isEmpty {
                                onTranscript(self.lastNonEmptyTranscript)
                            }
                        } else {
                            self.statusMessage = "Speech error: \(error.localizedDescription)"
                            self.stop()
                        }
                    }
                }
            }
        } catch {
            statusMessage = "Speech start failed: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        isStoppingIntentionally = true

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Safe to ignore for prototype.
        }
    }
}

