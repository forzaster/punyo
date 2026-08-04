import Foundation
import Observation

// Holds the one line currently being said and how far through its life it is.
// Everything is time-driven rather than animated with SwiftUI transitions,
// because the view lives inside a TimelineView that redraws every frame — the
// display math wants to be a function of elapsed time, not a state change.
//
// @MainActor: the speaker orchestrates async work (a model call may take
// hundreds of ms) and hands the result back to SwiftUI state. Pinning the
// whole class to the main actor keeps captures inside the internal Task
// isolated-inherited, so no Sendable dance is needed for the source ref.
@MainActor
@Observable
final class PunyoSpeaker {
    private(set) var line: String?
    private(set) var elapsed: TimeInterval = 0

    // Last descriptor + which source produced the line. Exposed so the debug
    // panel can show *why* the puni said what it said — the whole point of
    // the three-stage pipeline is that a wrong line is diagnosable from the
    // reading, not just from the utterance.
    enum Origin: String { case model, template, none }
    private(set) var lastDescriptor: PunyoGestureDescriptor?
    private(set) var lastOrigin: Origin = .none

    let duration: TimeInterval = 2.4

    // Persona flows into the utterance context and, for a model source, into
    // its instructions. Debug panel picker binds to this.
    var persona: PunyoPersona = .mischievous

    // Phase 5 hook: set this to an on-device model source and the templates
    // become the fallback for whenever it declines. Leave it nil for phase 3
    // parity.
    var source: (any PunyoSpeechSource)?

    // Deadline the model has to beat before the fallback wins. Kept just
    // under half the utterance duration so a late answer doesn't collide
    // with the next catch under normal play.
    var modelDeadline: TimeInterval = 0.9

    private let fallback = TemplateSpeechSource()
    private var spokenAt: TimeInterval?
    // Monotonic token: only the most recent speak() invocation is allowed to
    // write `line`. Guards against a slow model response landing after a
    // newer catch has already produced its own line.
    private var pendingToken: Int = 0

    func speak(
        for event: PunyoCaptureEvent,
        descriptor: PunyoGestureDescriptor,
        at time: TimeInterval
    ) {
        lastDescriptor = descriptor
        let ctx = PunyoUtteranceContext(
            event: event, descriptor: descriptor, persona: persona
        )
        // Snapshot the fallback synchronously so a model that returns nil
        // still leaves us with something to say.
        let fallbackText = fallback.lineSync(for: ctx)
        pendingToken &+= 1
        let token = pendingToken

        guard let source else {
            present(text: fallbackText, at: time, origin: .template)
            return
        }

        let deadlineNs = UInt64(max(0.05, modelDeadline) * 1_000_000_000)
        Task { [weak self] in
            let modelText = await Self.race(
                model: { await source.line(for: ctx) },
                deadlineNs: deadlineNs
            )
            guard let self, token == self.pendingToken else { return }
            if let t = modelText, !t.isEmpty {
                self.present(
                    text: t,
                    at: Date().timeIntervalSinceReferenceDate,
                    origin: .model
                )
            } else {
                self.present(text: fallbackText, at: time, origin: .template)
            }
        }
    }

    func step(time: TimeInterval) {
        guard let spokenAt else { return }
        elapsed = time - spokenAt
        if elapsed >= duration {
            line = nil
            self.spokenAt = nil
            elapsed = 0
        }
    }

    // MARK: - Private

    private func present(text: String?, at time: TimeInterval, origin: Origin) {
        guard let text, !text.isEmpty else { return }
        line = text
        spokenAt = time
        elapsed = 0
        lastOrigin = origin
    }

    // Race model call against a sleep. Whichever produces a value first wins;
    // if the sleep wins, the model call is cancelled and we return nil so
    // the caller can fall back. Kept as a static so the closures don't
    // capture `self` — Sendable checks stay quiet.
    private static func race(
        model: @escaping @Sendable () async -> String?,
        deadlineNs: UInt64
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await model() }
            group.addTask {
                try? await Task.sleep(nanoseconds: deadlineNs)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
