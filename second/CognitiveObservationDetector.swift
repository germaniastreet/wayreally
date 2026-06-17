import Foundation

enum CognitiveObservationDetector {
    static let engineVersion = "1.9"

    static func detect(session: ReflectionSession) -> [ObservationEvent] {
        guard let latest = session.transcript.last else { return [] }

        let timestamp = latest.timestamp
        let transcript = session.transcript.map { $0.text }.joined(separator: " ")
        let lower = transcript.lowercased()

        var events: [ObservationEvent] = []

        if containsAny(lower, [
            "hope i didn't",
            "hope i did not",
            "i hope i didn't",
            "i hope i did not",
            "mess this up",
            "miss this up",
            "worried",
            "i'm worried",
            "im worried",
            "what if",
            "concerned"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .outcomeConcern,
                    title: "Outcome concern",
                    detail: "Language suggested concern about a possible mistake, outcome, or consequence.",
                    confidence: .medium,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "hope i didn't",
                        "hope i did not",
                        "mess this up",
                        "miss this up",
                        "worried",
                        "what if"
                    ]),
                    tags: ["concern", "outcome", "uncertainty", "risk"]
                )
            )
        }

        if containsAny(lower, [
            "let me go back",
            "go back and take a look",
            "take a look",
            "let me check",
            "double check",
            "check this",
            "checking",
            "verify",
            "confirm"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .verificationAttempt,
                    title: "Verification attempt",
                    detail: "Language suggested checking, confirming, or verifying whether something is correct.",
                    confidence: .medium,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "let me go back",
                        "take a look",
                        "checking",
                        "double check",
                        "verify",
                        "confirm"
                    ]),
                    tags: ["verification", "checking", "confirmation"]
                )
            )
        }

        if containsAny(lower, [
            "checking checking",
            "monitoring",
            "watching",
            "looking at",
            "i think it's ok",
            "i think it's okay",
            "i think its ok",
            "i think its okay"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .selfMonitoring,
                    title: "Self-monitoring",
                    detail: "Language suggested active monitoring of the situation, output, or internal state.",
                    confidence: .low,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "checking checking",
                        "i think it's ok",
                        "i think it's okay",
                        "monitoring",
                        "watching"
                    ]),
                    tags: ["self-monitoring", "attention", "checking"]
                )
            )
        }

        if containsAny(lower, [
            "ok looks good",
            "okay looks good",
            "looks good",
            "it's ok",
            "it's okay",
            "its ok",
            "its okay",
            "all good",
            "working",
            "yes",
            "relief"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .relief,
                    title: "Relief / reassurance",
                    detail: "Language suggested reassurance, relief, or a positive resolution after checking.",
                    confidence: .medium,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "ok looks good",
                        "looks good",
                        "it's ok",
                        "it's okay",
                        "working",
                        "yes"
                    ]),
                    tags: ["relief", "reassurance", "resolution"]
                )
            )
        }

        if containsAny(lower, [
            "moving on",
            "let's go",
            "lets go",
            "now we are cooking",
            "now we're talking",
            "continue",
            "progress",
            "next"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .reorientation,
                    title: "Reorientation toward progress",
                    detail: "Language suggested movement away from the current concern and toward continuation or progress.",
                    confidence: .medium,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "moving on",
                        "let's go",
                        "lets go",
                        "progress",
                        "next"
                    ]),
                    tags: ["reorientation", "progress", "forward-motion"]
                )
            )
        }

        if containsAny(lower, [
            "i'll",
            "i will",
            "i should",
            "i need to",
            "i'm going to",
            "im going to",
            "next i",
            "plan"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .planning,
                    title: "Planning",
                    detail: "Language suggested intention, next action, or planning.",
                    confidence: .low,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "i'll",
                        "i will",
                        "i should",
                        "i need to",
                        "i'm going to",
                        "next"
                    ]),
                    tags: ["planning", "intention", "next-action"]
                )
            )
        }

        if containsAny(lower, [
            "i decide",
            "i decided",
            "decision",
            "i'll do",
            "i will do",
            "that means",
            "so i"
        ]) {
            events.append(
                cognitiveEvent(
                    timestamp: timestamp,
                    kind: .decisionPoint,
                    title: "Decision point",
                    detail: "Language suggested a choice, conclusion, or decision point.",
                    confidence: .low,
                    relatedText: matchingPhrase(in: lower, phrases: [
                        "i decide",
                        "i decided",
                        "decision",
                        "i'll do",
                        "i will do",
                        "so i"
                    ]),
                    tags: ["decision", "choice", "conclusion"]
                )
            )
        }

        return deduplicated(events)
    }

    private static func cognitiveEvent(
        timestamp: Date,
        kind: ObservationEventKind,
        title: String,
        detail: String,
        confidence: SignalQuality,
        relatedText: String?,
        tags: [String]
    ) -> ObservationEvent {
        ObservationEvent(
            timestamp: timestamp,
            kind: kind,
            category: .cognitive,
            title: title,
            detail: detail,
            source: .derived,
            confidence: confidence,
            relatedText: relatedText,
            tags: tags,
            engineVersion: engineVersion
        )
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func matchingPhrase(in text: String, phrases: [String]) -> String? {
        phrases.first(where: { text.contains($0) })
    }

    private static func deduplicated(_ events: [ObservationEvent]) -> [ObservationEvent] {
        var seen = Set<String>()
        var result: [ObservationEvent] = []

        for event in events {
            let key = "\(event.category.rawValue)-\(event.title)-\(event.relatedText ?? "")"
            if !seen.contains(key) {
                seen.insert(key)
                result.append(event)
            }
        }

        return result
    }
}

