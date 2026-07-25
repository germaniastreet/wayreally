import Foundation

enum SignalSource: String, Codable {
    case mock
    case liveWatch
    case healthKitBackfill
    case transcript
    case userMarker
    case acoustic
    case observationEngine
    case dynamicsEngine
    case correlationEngine
    case derived
}

enum SignalQuality: String, Codable, Hashable {
    case high
    case medium
    case low
    case unavailable
}

enum ReflectionState: String, Codable {
    case idle
    case recording
    case completed
}

enum ObservationCategory: String, Codable, CaseIterable, Hashable {
    case language = "Language"
    case voice = "Voice"
    case cognitive = "Cognitive"
    case behavior = "Behavior"
    case body = "Body"
    case environment = "Environment"
}

enum ObservationEventKind: String, Codable, Hashable {
    case pauseGap
    case breathCue
    case stressLanguage
    case conflictLanguage
    case uncertaintyLanguage
    case reflectiveQuestion
    case regulationAttempt
    case repetition
    case falseStart
    case selfCorrection
    case qualificationLanguage
    case certaintyLanguage
    case emotionSearch

    case outcomeConcern
    case verificationAttempt
    case selfMonitoring
    case relief
    case reorientation
    case planning
    case decisionPoint
}

struct ObservationEvent: Identifiable, Codable {
    var id = UUID()

    /// Internal source of truth. Keep this as Date. Do not convert to String for storage.
    var timestamp: Date

    var kind: ObservationEventKind
    var category: ObservationCategory
    var title: String
    var detail: String
    var source: SignalSource
    var confidence: SignalQuality
    var relatedText: String?
    var tags: [String]

    /// Other plausible readings of the same evidence, so a reflection never
    /// presents a single interpretation as the only possible one. Populated
    /// by whichever engine creates the event; empty means none were authored
    /// for this observation kind yet, not that none exist. See
    /// PROJECT_CONSTRAINTS.md #6 and PROJECT_ARCHITECTURE.md section 7.
    var alternativeExplanations: [String] = []

    var engineVersion: String
}

enum DynamicsPatternKind: String, Codable, Hashable {
    case emotionalClarification
    case emotionalAmbivalence
    case regulationEffort
    case uncertaintyLoop
    case speechConstructionFriction
    case stressRegulationCluster
    case breathRegulationMarker
    case reflectiveSenseMaking

    case resolutionSeeking
    case activeChecking
    case unresolvedConcern
}

struct DynamicsPattern: Identifiable, Codable {
    var id = UUID()
    var title: String
    var kind: DynamicsPatternKind
    var detail: String
    var confidence: SignalQuality
    var supportingEventIDs: [UUID]
    var tags: [String]
    var engineVersion: String
}

enum ObservationCorrelationKind: String, Codable, Hashable {
    case emotionalClarification
    case reflectiveProcessing
    case possibleSelfRegulation
    case conflictRegulation
    case stressActivation
    case speechFriction
    case uncertaintyWithQualification
    case breathAfterConcern

    case concernVerification
    case verificationRelief
    case selfMonitoringReassurance
}

struct ObservationCorrelation: Identifiable, Codable {
    var id = UUID()
    var timestamp: Date
    var title: String
    var kind: ObservationCorrelationKind
    var summary: String
    var confidence: SignalQuality
    var sourceEventIDs: [UUID]
    var sourceEventTitles: [String]
    var tags: [String]
    var engineVersion: String
}

struct ReflectionSession: Identifiable, Codable {
    var id = UUID()
    var title: String

    /// Internal source of truth. Keep these as Date. Display format belongs in Date extension/UI only.
    var startedAt: Date
    var endedAt: Date?

    var state: ReflectionState
    var transcript: [TranscriptEvent]
    var observations: [Observation]
    var observationEvents: [ObservationEvent]
    var dynamicsPatterns: [DynamicsPattern]
    var observationCorrelations: [ObservationCorrelation]
    var observationEngineVersion: String
    var dynamicsEngineVersion: String
    var correlationEngineVersion: String
    var biometrics: BiometricWindow
    var voice: VoiceSignals

    var durationSeconds: Int {
        let end = endedAt ?? Date()
        return max(0, Int(end.timeIntervalSince(startedAt)))
    }

    var durationText: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return "\(minutes)m \(seconds)s"
    }

    var timeRangeText: String {
        if let endedAt {
            return "\(startedAt.displayTime) – \(endedAt.displayTime)"
        } else {
            return "\(startedAt.displayTime) – now"
        }
    }
}

struct TranscriptEvent: Identifiable, Codable {
    var id = UUID()

    /// Internal source of truth. Keep this as Date. Do not convert to String for storage.
    var timestamp: Date

    var speaker: Speaker
    var text: String
    var source: SignalSource
}

enum Speaker: String, Codable, Hashable {
    case user = "You"
    case other = "They"
}

struct BiometricSample: Identifiable, Codable {
    var id = UUID()

    /// Internal source of truth. Keep this as Date. Do not convert to String for storage.
    var timestamp: Date

    var heartRate: Double?
    var respiration: Double?
    var hrv: Double?
    var source: SignalSource
    var quality: SignalQuality
}

struct BiometricWindow: Codable {
    var queryStart: Date
    var queryEnd: Date
    var samples: [BiometricSample]
    var quality: SignalQuality

    var latestHeartRate: Double {
        samples.compactMap { $0.heartRate }.last ?? 0
    }

    var averageHeartRate: Double {
        let values = samples.compactMap { $0.heartRate }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageRespiration: Double {
        let values = samples.compactMap { $0.respiration }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageHRV: Double {
        let values = samples.compactMap { $0.hrv }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct Observation: Identifiable, Codable {
    var id = UUID()
    var title: String
    var detail: String
    var confidence: SignalQuality
}

struct VoiceSignals: Codable {
    var wordsPerMinute: Int
    var pauseCount: Int
    var hesitationMarkers: Int
    var durationSeconds: Int
}

struct CorrelationScore: Identifiable {
    var id = UUID()
    var label: String
    var value: Double
    var signalColorName: String
}

struct ConversationDynamics {
    var userSpeakingPercent: Double
    var otherSpeakingPercent: Double
    var turnsTaken: Int
    var averageTurnLength: Double
    var interruptions: Int
    var dominanceIndex: Double
}


