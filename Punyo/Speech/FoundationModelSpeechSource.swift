import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import Observation

// On-device speech source. Uses Apple's FoundationModels framework on iOS 26+.
// Everything about it is designed to fail closed: if the framework isn't
// present, if the model is unavailable, if a call throws, or if it takes too
// long, `line(for:)` returns nil and the caller falls back to templates.
//
// The whole session is reset when the persona changes — we lean on the
// session's instructions rather than repeating the persona in every prompt,
// so a fresh persona means a fresh session.
//
// @MainActor: the debug panel binds directly to `temperature`, `persona`,
// and `isAvailable`; pinning the class to the main actor keeps observation
// coherent and gives us implicit Sendable so the speaker can hold it.
@MainActor
@Observable
final class FoundationModelSpeechSource: PunyoSpeechSource {
    // Live tuning knobs exposed to the debug panel. Kept inside the source
    // (not the speaker) because they only mean something to a model.
    var temperature: Double = 0.9
    var maxResponseTokens: Int = 24
    // Persona currently baked into the session's instructions. Private
    // setter because @Observable rewrites stored properties into computed
    // ones, which drops didSet — the rebuild has to be triggered explicitly
    // via setPersona(_:).
    private(set) var persona: PunyoPersona

    func setPersona(_ new: PunyoPersona) {
        guard new != persona else { return }
        persona = new
        rebuildSession()
    }

    // Availability that the debug panel can display. Stays false when
    // FoundationModels can't be imported or the OS reports the model as
    // unavailable.
    private(set) var isAvailable: Bool = false
    private(set) var lastErrorSummary: String?

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var session: LanguageModelSession?
    #endif

    init(persona: PunyoPersona = .mischievous) {
        self.persona = persona
        rebuildSession()
    }

    func line(for context: PunyoUtteranceContext) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await respond(context: context)
        } else {
            return nil
        }
        #else
        _ = context
        return nil
        #endif
    }

    // MARK: - Session

    private func rebuildSession() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                session = LanguageModelSession(instructions: persona.instructions)
                isAvailable = true
                lastErrorSummary = nil
            default:
                session = nil
                isAvailable = false
                lastErrorSummary = "モデル使用不可"
            }
        } else {
            isAvailable = false
            lastErrorSummary = "iOS 26未満"
        }
        #else
        isAvailable = false
        lastErrorSummary = "FoundationModels未リンク"
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func respond(context: PunyoUtteranceContext) async -> String? {
        guard let session else { return nil }
        let prompt = Self.buildPrompt(context: context)
        do {
            let options = GenerationOptions(
                temperature: temperature,
                maximumResponseTokens: maxResponseTokens
            )
            let response = try await session.respond(to: prompt, options: options)
            let trimmed = Self.tidy(response.content)
            lastErrorSummary = nil
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            lastErrorSummary = String(describing: error).prefix(80).description
            return nil
        }
    }
    #endif

    // MARK: - Prompt

    // Only the descriptor summary + the coarse hints get sent to the model.
    // The raw numeric features stay upstream: what the model actually needs
    // is "what kind of catch was this", not decimals.
    private static func buildPrompt(context: PunyoUtteranceContext) -> String {
        let d = context.descriptor
        let e = context.event
        var lines: [String] = []
        lines.append("状況: \(d.summary)")
        if let f = d.flourish { lines.append("補足: \(f)") }
        if e.captureCount == 1 { lines.append("これが最初の遭遇") }
        if e.stamina < 0.25 { lines.append("ぷにょは息切れしている") }
        if let gap = e.timeSinceLastCapture, gap < 4.0 {
            lines.append("さっき捕まったばかり")
        }
        // Volume/pace hints as words, not numbers — the model handles
        // adjectives more reliably than sliders.
        if d.volumeHint > 0.75 { lines.append("声は大きめ") }
        else if d.volumeHint < 0.25 { lines.append("声は小さめ") }
        if d.paceHint > 0.75 { lines.append("早口") }
        else if d.paceHint < 0.3 { lines.append("ゆっくり") }
        lines.append("上の状況に対して、ぷにょが一言だけ発する台詞を出力せよ。台詞のみ。前置き禁止。")
        return lines.joined(separator: "\n")
    }

    // Strip quotes/whitespace and clamp length: LLM completions like to wrap
    // in 「」 or add trailing punctuation that fights the speech bubble.
    private static func tidy(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let f = s.first, "「」\"'『』 ".contains(f) { s.removeFirst() }
        while let l = s.last, "「」\"'『』 ".contains(l) { s.removeLast() }
        if let nl = s.firstIndex(where: { $0.isNewline }) {
            s = String(s[..<nl])
        }
        if s.count > 20 { s = String(s.prefix(20)) }
        return s
    }
}
