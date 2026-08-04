import Foundation

// Where a line comes from. The whole point of this seam is phase 5: swapping
// in an on-device model (or a rare Claude API "渾身の一言") is assigning one
// property on PunyoSpeaker, and a source that returns nil — offline, too
// slow, nothing good to say — falls straight back to the templates with no
// other change anywhere.
//
// Async because the on-device path (Apple FoundationModels) is inherently
// async. The template source resolves immediately and remains a viable
// implementation. Sendable so the speaker can hand this ref to an internal
// Task without a Sendable warning; implementations get Sendable for free by
// being main-actor isolated.
protocol PunyoSpeechSource: AnyObject, Sendable {
    // nil means "I have nothing" and hands off to the fallback.
    func line(for context: PunyoUtteranceContext) async -> String?
}
