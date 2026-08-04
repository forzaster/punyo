import Foundation

// Fixed lines picked by descriptor. Kept honest: this is the fallback when no
// model is available or a model call takes too long, so it must always be
// able to answer. Priority order runs from "most telling about the moment" to
// "generic catch" — a slam matters more than the chase length.
//
// @MainActor for two reasons: the mutable `lastLine` is only ever touched
// from the speaker (main-actor), and it makes the class implicitly Sendable
// so PunyoSpeechSource can require Sendable.
@MainActor
final class TemplateSpeechSource: PunyoSpeechSource {
    private var lastLine: String?

    func line(for context: PunyoUtteranceContext) async -> String? {
        pick(from: bucket(for: context))
    }

    // Synchronous entry kept so PunyoSpeaker's fallback path doesn't need to
    // await when it's already resolved everything else.
    func lineSync(for context: PunyoUtteranceContext) -> String? {
        pick(from: bucket(for: context))
    }

    // MARK: - Bucket selection

    private func bucket(for context: PunyoUtteranceContext) -> [String] {
        let tags = Set(context.descriptor.tags)
        let event = context.event

        // Descriptor-driven branches. Order matters: the first hit wins, so
        // put "reads most about the moment" at the top.
        if tags.contains(.slammed) { return Self.slammed }
        if tags.contains(.gentle) { return Self.gentle }
        if tags.contains(.trembling) { return Self.trembling }
        if tags.contains(.fumbled) && context.descriptor.missCount >= 3 {
            return Self.fumbledLots
        }
        if tags.contains(.fumbled) { return Self.fumbledSome }
        if tags.contains(.circles) { return Self.circles }
        if tags.contains(.zigzag) { return Self.zigzag }
        if tags.contains(.rough) { return Self.rough }
        if tags.contains(.sluggish) { return Self.sluggish }
        if tags.contains(.tinyPath) { return Self.tinyPath }
        if tags.contains(.repeatedHabit) { return Self.repeated }

        // Fall back to the phase-3 buckets on the base capture event.
        if event.captureCount == 1 { return Self.firstMeeting }
        if event.stamina < 0.25 { return Self.exhausted }
        if let gap = event.timeSinceLastCapture, gap < 4.0 { return Self.tooSoon }
        if tags.contains(.briefTouch) || event.chaseDuration < 0.6 { return Self.instant }
        if tags.contains(.longChase) || event.chaseDuration > 8.0 { return Self.longChase }
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
        "はじめまして", "わ、つかまった", "だれ",
    ]

    private static let exhausted = [
        "もうむり", "はぁ…はぁ…", "こうさん", "うごけない", "ぎぶ",
    ]

    private static let tooSoon = [
        "またぁ？", "さっきもやった", "なんでよ", "もぉ",
    ]

    private static let instant = [
        "え", "はやっ", "みつかった", "うそ",
    ]

    private static let longChase = [
        "しつこい", "つかれた…", "そんなに？", "ねばるね",
    ]

    private static let casual = [
        "つかまった", "わっ", "にげてたのに", "ちょ", "ふにゃ",
    ]

    // --- Descriptor-driven buckets ---

    private static let slammed = [
        "いた", "らんぼう", "つよ", "叩かないで", "ひどい",
    ]

    private static let gentle = [
        "やさしいね", "ほっ", "ふわ", "そっとしてくれた", "ありがと",
    ]

    private static let trembling = [
        "ふるえてる？", "だいじょうぶ？", "きんちょう？", "て、ぷるぷる",
    ]

    private static let fumbledSome = [
        "おしい", "もうすこし", "ぬるっ", "つるっ",
    ]

    private static let fumbledLots = [
        "へたっぴ", "なんかいめ？", "しつこいなぁ", "そんなに掴みたい？",
    ]

    private static let circles = [
        "めがまわる", "ぐるぐるすんな", "うずまき…", "よってきた",
    ]

    private static let zigzag = [
        "いらいらしてる？", "ぎざぎざ", "落ち着いて", "なにその動き",
    ]

    private static let rough = [
        "せっかち", "殺気だってる", "はやすぎ", "こわ",
    ]

    private static let sluggish = [
        "ねむい？", "げんきないね", "だる…", "のんびりだね",
    ]

    private static let tinyPath = [
        "うごかないの？", "そこ？", "じっとしてる",
    ]

    private static let repeated = [
        "またそれ", "くせだね", "みたことある動き", "さっきもした",
    ]
}
