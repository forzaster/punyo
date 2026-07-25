import Foundation
import Observation

// Holds the one line currently being said and how far through its life it is.
// Everything is time-driven rather than animated with SwiftUI transitions,
// because the view lives inside a TimelineView that redraws every frame — the
// display math wants to be a function of elapsed time, not a state change.
@Observable
final class PunyoSpeaker {
    private(set) var line: String?
    private(set) var elapsed: TimeInterval = 0

    let duration: TimeInterval = 2.4

    // Phase 5 hook: set this to an on-device model source and the templates
    // become the fallback for whenever it declines. Leave it nil for phase 3.
    var source: (any PunyoSpeechSource)?

    private let fallback = TemplateSpeechSource()
    private var spokenAt: TimeInterval?

    func speak(for event: PunyoCaptureEvent, at time: TimeInterval) {
        // flatMap, not optional chaining: `source?.line(for:)` is a double
        // optional, so a source that declines would read as silence instead of
        // falling through to the templates.
        let offered = source.flatMap { $0.line(for: event) }
        guard let text = offered ?? fallback.line(for: event),
              !text.isEmpty else { return }
        line = text
        spokenAt = time
        elapsed = 0
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
}
