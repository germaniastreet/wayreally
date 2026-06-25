import Foundation

enum CognitiveObservationDetector {
    static let engineVersion = "2.0"

    static func detect(session: ReflectionSession) -> [ObservationEvent] {
        SignalLibraryDetectionEngine.detect(
            session: session,
            libraries: SignalLibraryDefaults.defaultLibraries,
            domain: .cognitive
        )
    }
}
