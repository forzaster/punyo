import Foundation

// Fixed lines picked by situation. No cleverness on purpose — phase 3 is only
// asking whether the catch → speak loop is fun at all, and a template that
// reacts to *how* it was caught is enough to answer that.
final class TemplateSpeechSource: PunyoSpeechSource {
    private var lastLine: String?

    func line(for event: PunyoCaptureEvent) -> String? {
        pick(from: bucket(for: event))
    }

    // Priority order, most telling situation first: being run into the ground
    // says more about the moment than how long the chase took.
    private func bucket(for event: PunyoCaptureEvent) -> [String] {
        if event.captureCount == 1 {
            return Self.firstMeeting
        }
        if event.stamina < 0.25 {
            return Self.exhausted
        }
        if let gap = event.timeSinceLastCapture, gap < 4.0 {
            return Self.tooSoon
        }
        if event.chaseDuration < 0.6 {
            return Self.instant
        }
        if event.chaseDuration > 8.0 {
            return Self.longChase
        }
        return Self.casual
    }

    private func pick(from lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        // Never the same line twice running. With four or more per bucket a
        // single re-roll is enough to keep it from sounding canned.
        var choice = lines.randomElement()
        if choice == lastLine, lines.count > 1 {
            choice = lines.filter { $0 != lastLine }.randomElement()
        }
        lastLine = choice
        return choice
    }

    // MARK: - Lines

    private static let firstMeeting = [
        "はじめまして",
        "わ、つかまった",
        "だれ",
    ]

    private static let exhausted = [
        "もうむり",
        "はぁ…はぁ…",
        "こうさん",
        "うごけない",
        "ぎぶ",
    ]

    private static let tooSoon = [
        "またぁ？",
        "さっきもやった",
        "なんでよ",
        "もぉ",
    ]

    private static let instant = [
        "え",
        "はやっ",
        "みつかった",
        "うそ",
    ]

    private static let longChase = [
        "しつこい",
        "つかれた…",
        "そんなに？",
        "ねばるね",
    ]

    private static let casual = [
        "つかまった",
        "わっ",
        "にげてたのに",
        "ちょ",
        "ふにゃ",
    ]
}
