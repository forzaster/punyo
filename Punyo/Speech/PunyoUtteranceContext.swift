import Foundation

// Everything a speech source (template, on-device model, cloud) needs to pick
// or generate a line. Structured deliberately: capture event = physics
// truth (won't ever contain sensitive data), descriptor = the human-readable
// reading of *how* it was caught. An LLM prompt is built from the descriptor
// and the persona — the numbers never go to the model.
struct PunyoUtteranceContext {
    let event: PunyoCaptureEvent
    let descriptor: PunyoGestureDescriptor
    let persona: PunyoPersona
}

// Character preset. The name is what shows in the debug panel; the prompt
// lines are what an on-device model is instructed with. Keeping it tiny —
// three or four presets — is enough to feel that the same catch reads
// differently under a different personality.
struct PunyoPersona: Identifiable, Equatable {
    let id: String
    let name: String
    // Two-line instruction handed to the LLM. Deliberately terse so the
    // model spends its response budget on the line, not on echoing rules.
    let instructions: String

    static let mischievous = PunyoPersona(
        id: "mischievous",
        name: "軽口",
        instructions: """
        あなたは「ぷにょ」という小さな生き物。捕まえられた瞬間に一言だけ、\
        ひらがな中心の日本語で、軽口で少し生意気に返す。1〜12文字。句読点なし。
        """
    )

    static let quiet = PunyoPersona(
        id: "quiet",
        name: "寡黙",
        instructions: """
        あなたは「ぷにょ」。捕まえられた瞬間に短く一言。ぼそっと、\
        ひらがな中心で、1〜6文字。感情を出しすぎない。句読点なし。
        """
    )

    static let dramatic = PunyoPersona(
        id: "dramatic",
        name: "大袈裟",
        instructions: """
        あなたは「ぷにょ」。捕まえられた瞬間に一言、少し大袈裟に。\
        ひらがな中心の日本語で1〜14文字。句読点なし。
        """
    )

    static let all: [PunyoPersona] = [.mischievous, .quiet, .dramatic]
}
