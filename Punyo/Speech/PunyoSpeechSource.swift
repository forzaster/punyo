import Foundation

// Where a line comes from. The whole point of this seam is phase 5: swapping in
// an on-device model (or a rare Claude API "渾身の一言") should be assigning one
// property on PunyoSpeaker, and a source that returns nil — offline, too slow,
// nothing good to say — falls straight back to the templates with no other
// change anywhere.
//
// Class-bound so an implementation can keep state (recent lines, a warm model)
// without every call site dealing with mutating methods.
protocol PunyoSpeechSource: AnyObject {
    // nil means "I have nothing" and hands off to the fallback.
    func line(for event: PunyoCaptureEvent) -> String?
}
