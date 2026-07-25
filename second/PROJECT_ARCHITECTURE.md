# WayReally — Project Architecture

## Source of Truth • v1.0 • 2026-07-25

This file is the practical companion to PROJECT_CONSTRAINTS.md. Where
PROJECT_CONSTRAINTS.md defines *what the product is allowed to do*, this file
defines *how the code is actually organized* — folder structure, naming,
data flow, what each engine is responsible for, how data is stored, and
where the boundaries are. It reflects the real code as of v115 (Capture
Reliability update), not an aspirational future design. When the code and
this document disagree, treat that as a bug in this document and fix the
document to match the code — this file should always describe reality.

This document is meant to be usable by anyone or anything working on this
project — Claude, ChatGPT, or a future contributor — so that changes are
measured against the same shared picture of how the app is built, instead
of each contributor re-deriving the architecture from scratch.

## 1. Folder structure

The project currently uses a single flat source folder — there are no
subfolders inside `second/` yet:

```text
WayReally/                          (outer container folder — not tracked by Xcode)
  second.xcodeproj/                 (the Xcode project file)
  second/                           (all Swift source + docs — this is what Xcode calls "the second target")
    *.swift                         (all source files, flat, no subfolders)
    Info.plist                      (only exists because of Background Modes; otherwise auto-generated)
    Assets.xcassets/                (app icon, accent color)
    PROJECT_CONSTRAINTS.md
    PROJECT_GLOSSARY.md
    PROJECT_ARCHITECTURE.md         (this file)
    PRE_BUILD_CHECKLIST.md
    PROJECT_STRUCTURE_CLEANUP_v115.md
    README.txt
    VERSION_HISTORY.txt
```

As the project grows past roughly 40 files, grouping into subfolders (e.g.
`Screens/`, `Engines/`, `Models/`, `Stores/`) is worth considering — but
that is itself a rename/move-type change and should be its own controlled
version, the same way the app-name rename was, since Xcode's file
references need to move together with the files.

## 2. Naming conventions actually in use

These aren't proposed conventions — this is what the existing ~28 Swift
files already do consistently, and new files should follow the same
pattern:

- **Screens** (SwiftUI views the user navigates to) are structs named
  `___Screen.swift` — e.g. `ObservatoryScreen`, `AudioCaptureScreen`,
  `SignalLibraryScreen`. Each owns its own `NavigationStack` and reads
  state through `@EnvironmentObject`, never by constructing a store
  itself.
- **Engines** (pure analysis logic) are `enum`s with only `static` members
  — never instantiated, never hold state. Every engine exposes a
  `static let engineVersion = "x.y"` constant, and the version string is
  stored on the result it produces and shown in the UI (e.g. "Summary
  engine: 1.8"). This is a deliberate transparency convention — see
  PROJECT_CONSTRAINTS.md #5/#9 — so a user can always see which version of
  which logic produced a given observation.
- **Stores** (shared mutable state) are `final class ... : ObservableObject`
  — there are exactly two: `ReflectionSessionStore` and
  `SignalLibraryRegistry`/`PersistentSignalLibraryStore`. Both are created
  once in `ContentView` and shared via `.environmentObject(...)` to every
  tab, so all screens see the same live state.
- **Models** (plain data types) live in `Models.swift` (session, transcript,
  observation, dynamics, biometrics, correlation) and
  `SignalLibraryModels.swift` (signal library domain only, kept separate
  because it's a distinct subsystem — user/moderator-authored detection
  rules, not reflection data).
- `Components.swift` holds shared, reusable SwiftUI pieces (`AppCard`,
  `MetricRow`, `ScreenHeader`, `SignalBadge`, etc.) used across multiple
  screens — new shared UI pieces belong here, not duplicated per-screen.

## 3. Data flow

`ContentView` is the single root that creates the app's two long-lived
stores and hands them down:

```text
ContentView
  @StateObject sessionStore: ReflectionSessionStore
  @StateObject speechManager: SpeechRecognitionManager
    → .environmentObject() to all 7 tabs
```

The `SignalLibraryRegistry` (backed by `PersistentSignalLibraryStore`) is
created independently and owns the signal-library subsystem — it is a
separate concern from reflection sessions.

The flow for a single reflection, start to finish:

1. `AudioCaptureScreen` (or `ObservatoryScreen`, which shares the same
   store) calls `speechManager.start(onTranscript:)`.
2. `SpeechRecognitionManager` (AVFoundation + Speech framework) turns live
   audio into text and calls back into `store.updateLiveTranscript(_:)`.
3. `ReflectionSessionStore` holds the single `activeSession` as
   `@Published`, so every screen watching it updates automatically.
4. On stop, `store.stopAndObserve()` runs the analysis engines
   (`ObservationEventEngine`, `DynamicsEngine`, `CorrelationEngine`, etc.)
   against the finished session and attaches their results to it.
5. The finished session moves into `store.completedSessions`, where
   `ReflectionTimelineScreen`, `ReflectionDetailScreen`,
   `ConversationDynamicsScreen`, and `CorrelationScreen` all read from it.

**Engines never mutate state themselves.** Every engine is a pure
function: it takes a `ReflectionSession` (or similar) in, and returns a
result type out (e.g. `ConversationDynamicsEngine.analyze(session:) ->
ConversationDynamics?`). Only the store applies the result back onto the
session. This separation is what keeps the "engine" layer testable and
swappable without touching UI or storage code.

## 4. Responsibilities of every engine

| Engine | File | Computes |
|---|---|---|
| `ObservationEventEngine` | ObservationEventEngine.swift | Turns a transcript into individual `ObservationEvent`s (moments worth flagging) |
| `CognitiveObservationDetector` | CognitiveObservationDetector.swift | Keyword/pattern-based detection feeding into observation events |
| `DynamicsEngine` | DynamicsEngine.swift | General session dynamics/patterns (`DynamicsPattern`) |
| `ConversationDynamicsEngine` | ConversationDynamicsEngine.swift | Turn-taking and speaking-share, estimated from transcript word counts (not timed audio — see its doc comment) |
| `CorrelationEngine` | CorrelationEngine.swift | Correlations between observations (`ObservationCorrelation`) |
| `ReflectionAnalyzer` | ReflectionAnalyzer.swift | Overall per-reflection analysis summary |
| `ReflectionArcEngine` | ReflectionArcEngine.swift | The emotional/topical "arc" shape of a single reflection |
| `EmotionalTrajectoryEngine` | EmotionalTrajectoryEngine.swift | Emotional trajectory across a reflection (or across sessions) |
| `ReflectionSummaryEngine` | ReflectionSummaryEngine.swift | Human-readable summary text for a completed reflection |
| `SignalLibraryDetectionEngine` | SignalLibraryDetectionEngine.swift | Matches transcript content against active `SignalLibrary` rules |

All ten are stateless enums with a version constant, per the naming
convention above. None of them make network calls — see section 7.

## 5. How observations and evidence are produced and stored

"Observations" (in the PROJECT_CONSTRAINTS.md #5 sense — every claim must
retain its evidence) are produced entirely by the engine layer running
against a session's transcript and biometric window at `stopAndObserve()`
time, and are attached directly onto the `ReflectionSession` value as
typed arrays (`observations`, `observationEvents`, `dynamicsPatterns`,
`observationCorrelations`) plus the `engineVersion` string that produced
each layer. There is currently no separate "evidence store" — the
evidence *is* the session's own transcript and biometric window, which
travel with it, so any observation can always be traced back to the raw
transcript text it came from.

**Current gap worth knowing about:** `ReflectionSessionStore` holds
`completedSessions` only in memory (`@Published var completedSessions:
[ReflectionSession] = SampleData.sessions`) — there is no `FileManager` or
`UserDefaults` persistence call anywhere in that file. In practice, this
means finished reflections do not currently survive an app relaunch; only
the sample/demo data reappears. This is a real limitation, not a design
choice, and is a natural candidate for a future version (following the
same JSON-file-in-Application-Support pattern `PersistentSignalLibraryStore`
already uses successfully for signal libraries).

## 6. "Database" / storage schema

There is no database (no CoreData, no SwiftData, no SQLite). Two storage
mechanisms exist today:

- **In-memory only:** `ReflectionSessionStore.completedSessions` and
  `.activeSession` — Swift `Codable` structs held in RAM, lost on
  relaunch (see gap above).
- **JSON files on disk:** `PersistentSignalLibraryStore` encodes
  `[SignalLibrary]` via `JSONEncoder`/`JSONDecoder` to a file under the
  app's Application Support directory (`FileManager.default.urls(for:
  .applicationSupportDirectory, ...)`). This is the only durable storage
  in the app today.

The core `Codable` model types (defined in Models.swift /
SignalLibraryModels.swift) are effectively the schema:
`ReflectionSession`, `TranscriptEvent`, `ObservationEvent`,
`DynamicsPattern`, `ObservationCorrelation`, `BiometricWindow` /
`BiometricSample`, `VoiceSignals` on the reflection side; `SignalLibrary`,
`SignalDetectionRule`, `SignalLibraryMatch` on the signal-library side.
Any future real persistence layer (for reflections) should serialize
these same types rather than inventing a parallel representation.

## 7. API boundaries / network access / "AI reasoning"

As of this version, WayReally makes **no network calls anywhere in the
codebase** — there is no `URLSession`, no `URLRequest`, and no
integration with any external AI/LLM service. Every analysis engine listed
in section 4 is on-device, rule-based Swift logic (keyword matching, word
counts, simple heuristics) — not a large-language-model prompt. This
matches PROJECT_CONSTRAINTS.md's "local-first" posture (see
SettingsScreen: Cloud sync = Off, Storage = Local-first) and is worth
treating as intentional, not incidental: it means reflections never leave
the device today.

If a future version adds real "AI reasoning" (an LLM call, a prompt-based
engine, a cloud service) that would be a meaningful architecture change,
not a routine one — it should get its own controlled version, its own
entry in this document (a "Prompt Contracts" section, defining exactly
what data leaves the device and why), and should not be added quietly
inside an existing engine.

## 8. What this document is not

This file describes the current, real structure of the code. It is not a
roadmap and not a constraints document — see VERSION_HISTORY.txt for what
changed when, and PROJECT_CONSTRAINTS.md for binding product/safety rules.
When either Claude or ChatGPT makes an architecture-level decision (a new
store, a new persistence layer, a new cross-cutting naming convention),
update this document in the same commit as the code change, so it never
drifts out of sync with what's actually true.
