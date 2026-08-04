import Foundation

// Descriptor: features passed through fixed thresholds into short natural-
// language tags. This is the layer a speech source (template or LLM) actually
// reads — the raw numbers stay upstream so that changing the threshold table
// doesn't ripple into the model prompts.
//
// Kept explicit and inspectable: the debug panel shows the last descriptor,
// which is how you tell whether an odd line came from a wrong reading or a
// wrong template.
struct PunyoGestureDescriptor {
    enum Tag: String, CaseIterable {
        case gentle       // そっと触れた
        case rough        // 荒く速い
        case slammed      // 叩くように掴んだ
        case trembling    // 手が震えている
        case hurried      // 急いでる
        case sluggish     // のろい
        case fumbled      // 何度も掴み損ねた
        case longChase    // 長く追い回した
        case briefTouch   // すぐ捕まえた
        case circles      // ぐるぐる円を描いた
        case zigzag       // ジグザグ
        case straight     // 直線的
        case tinyPath     // ほとんど動かず
        case repeatedHabit // 同じ手癖
    }

    let tags: [Tag]
    let missCount: Int
    // 0…1. Amount to nudge speech loudness/emphasis in the utterance. Comes
    // from deformation peak — a slam speaks loud, a graze whispers.
    let volumeHint: Double
    // 0…1. Nudge for speech tempo. Comes from mean finger speed.
    let paceHint: Double
    // Japanese one-line summary handed to the LLM as the "situation" line.
    // Also displayed in the debug panel so template misfires are obvious.
    let summary: String
    // Free-form modifier the LLM can weave in: a made-up shape name for
    // loopy paths, an invented constellation for angular ones. Sometimes nil.
    // Purely flavour; the template ignores it.
    let flourish: String?
}

// Threshold table. All in one place so the debug panel is the ground truth
// for what a reading means and small tweaks stay auditable.
enum PunyoDescriptorFactory {
    static func make(
        from features: PunyoGestureFeatures,
        recentHabit: PunyoGestureFeatures? = nil
    ) -> PunyoGestureDescriptor {
        var tags: [PunyoGestureDescriptor.Tag] = []
        var summaryParts: [String] = []

        // --- Force / touch character ---
        if features.deformationRatio >= 0.55 && features.peakSpeed >= 900 {
            tags.append(.slammed); summaryParts.append("叩くように掴んだ")
        } else if features.deformationRatio <= 0.15 && features.peakSpeed < 400 {
            tags.append(.gentle); summaryParts.append("そっと触れた")
        }

        // --- Speed profile ---
        if features.meanSpeed >= 700 {
            tags.append(.rough); summaryParts.append("荒く速い動き")
        } else if features.meanSpeed < 90 && features.elapsed > 0.6 {
            tags.append(.sluggish); summaryParts.append("のろい動き")
        } else if features.meanSpeed >= 350 {
            tags.append(.hurried)
        }

        // --- Jitter ---
        if features.jitter >= 0.55 {
            tags.append(.trembling); summaryParts.append("手が震えている")
        }

        // --- Grab attempts ---
        if features.grabMissCount >= 3 {
            tags.append(.fumbled)
            summaryParts.append("\(features.grabMissCount)回掴み損ねた")
        } else if features.grabMissCount >= 1 {
            tags.append(.fumbled)
        }

        // --- Chase length ---
        if features.elapsed >= 8.0 {
            tags.append(.longChase); summaryParts.append("長く追い回した")
        } else if features.elapsed < 0.6 && features.totalDistance < 40 {
            tags.append(.briefTouch)
        }

        // --- Shape ---
        var flourish: String? = nil
        let absWinds = abs(features.windings)
        if absWinds >= 0.75 && features.straightness < 0.35 {
            tags.append(.circles); summaryParts.append("ぐるぐる円を描いた")
            flourish = "目が回るような \(String(format: "%.1f", absWinds))周の渦"
        } else if features.jitter >= 0.4 && features.straightness < 0.5
                    && features.curvature > 0.05 {
            tags.append(.zigzag); summaryParts.append("ジグザグ")
            // 稀にでたらめな星座名/文字っぽいものを付ける — 大体外すのが仕様。
            flourish = Self.madeUpName()
        } else if features.straightness >= 0.85 && features.totalDistance > 60 {
            tags.append(.straight); summaryParts.append("直線的")
        }

        if features.totalDistance < 30 && features.elapsed > 0.4 {
            tags.append(.tinyPath); summaryParts.append("ほとんど動いていない")
        }

        // --- Habit (across catches) ---
        if let prev = recentHabit, sameHabit(features, prev) {
            tags.append(.repeatedHabit); summaryParts.append("さっきと同じ手つき")
        }

        // Volume + pace hints for the speaker/UI layer.
        let volume = min(1.0, 0.15 + features.deformationRatio * 1.1)
        let pace = min(1.0, 0.25 + Double(features.meanSpeed) / 1200.0)

        let summary = summaryParts.isEmpty
            ? "ふつうに捕まえた"
            : summaryParts.joined(separator: "、")

        return PunyoGestureDescriptor(
            tags: tags,
            missCount: features.grabMissCount,
            volumeHint: volume,
            paceHint: pace,
            summary: summary,
            flourish: flourish
        )
    }

    // Two catches count as "same habit" when the coarse feel is close. Kept
    // loose on purpose — repeatedHabit is a hint, not an assertion.
    private static func sameHabit(
        _ a: PunyoGestureFeatures,
        _ b: PunyoGestureFeatures
    ) -> Bool {
        let speedClose = abs(a.meanSpeed - b.meanSpeed) < 120
        let defClose = abs(a.deformationRatio - b.deformationRatio) < 0.2
        let jitterClose = abs(a.jitter - b.jitter) < 0.25
        return speedClose && defClose && jitterClose
    }

    // Purposely nonsense: the character is guessing at what the finger drew
    // and gets it wrong. Kept short so an LLM can quote it verbatim.
    private static let madeUpConstellations = [
        "アイロン座", "だし巻き座", "しゃもじ座", "うずまき座", "ジグザグ座"
    ]
    private static let madeUpLetters = [
        "『ぬ』みたいな字", "『Z』っぽい字", "『え』かなにか", "知らない字"
    ]
    private static func madeUpName() -> String {
        let pool = Bool.random()
            ? madeUpConstellations
            : madeUpLetters
        return pool.randomElement() ?? "なにかの形"
    }
}
