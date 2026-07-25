import Foundation

// What the physics knows about a catch at the moment it happens. This is the
// whole context a speech source gets to work with — keeping it small and
// concrete means a template can branch on it today and a model can be handed
// it verbatim later.
struct PunyoCaptureEvent {
    // Stamina at the instant of capture: near 0 means it was run into the
    // ground first, near 1 means it was caught while still fresh.
    let stamina: Double
    // How long this touch lasted before the catch landed.
    let chaseDuration: TimeInterval
    // Times caught since launch, including this one.
    let captureCount: Int
    // Gap since the previous catch, nil for the first one.
    let timeSinceLastCapture: TimeInterval?
}
