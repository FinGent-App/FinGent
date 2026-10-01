// Core/Domain/Services/ConversationContextManager.swift

import Foundation

/// Thread-safe conversation context memory and query enrichment engine.
/// Retains active stock context (anaphora resolution) across conversational turns
/// so that follow-up questions like "will it go up or down" or "bagaimana prospeknya"
/// accurately reference the previously discussed stock (e.g. BBCA).
final class ConversationContextManager: @unchecked Sendable {

    static let shared = ConversationContextManager()

    private let lock = NSLock()
    private var _activeTickerContext: String? = nil
    private var _lastEnrichedPrompt: String? = nil

    private init() {}

    // MARK: - State Accessors

    var activeTickerContext: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _activeTickerContext
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _activeTickerContext = newValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    var lastEnrichedPrompt: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastEnrichedPrompt
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _activeTickerContext = nil
        _lastEnrichedPrompt = nil
    }

    // MARK: - Query Enrichment & Pronoun Resolution

    /// Enriches a user prompt with active ticker context if it represents a follow-up
    /// question referring to an ongoing discussion.
    ///
    /// - Parameters:
    ///   - prompt: The raw user query (e.g. "will it go up or down").
    ///   - fallbackHistory: Previous conversation turns used to recover context if in-memory ticker is nil.
    /// - Returns: A tuple of `(enrichedPrompt, resolvedTicker, wasEnriched)`.
    func enrichPromptIfFollowUp(
        _ prompt: String,
        fallbackHistory: [(role: String, content: String)] = []
    ) -> (enrichedPrompt: String, resolvedTicker: String?, wasEnriched: Bool) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (prompt, activeTickerContext, false)
        }

        // 1. Check if the prompt explicitly mentions a ticker or known company alias
        let explicitTicker = extractExplicitTicker(from: trimmed)

        if let explicit = explicitTicker {
            // User explicitly mentioned a new stock; update active conversation context
            self.activeTickerContext = explicit
            recordEnriched(trimmed)
            return (trimmed, explicit, false)
        }

        // 2. No explicit ticker in prompt. Determine candidate context from memory or history.
        let candidate = self.activeTickerContext ?? extractLastTickerFromHistory(fallbackHistory)

        guard let candidateTicker = candidate, !isGeneralPortfolioQuery(trimmed) else {
            recordEnriched(trimmed)
            return (trimmed, nil, false)
        }

        // 3. Determine if the query is a follow-up or contains anaphora / pronouns
        if isAnaphoricOrFollowUp(trimmed) {
            self.activeTickerContext = candidateTicker
            let enriched = rewritePrompt(trimmed, with: candidateTicker)
            recordEnriched(enriched)
            return (enriched, candidateTicker, true)
        }

        recordEnriched(trimmed)
        return (trimmed, candidateTicker, false)
    }

    // MARK: - Private Helpers

    private func recordEnriched(_ prompt: String) {
        lock.lock()
        defer { lock.unlock() }
        _lastEnrichedPrompt = prompt
    }

    private func extractExplicitTicker(from text: String) -> String? {
        let extracted = StockTickerExtractor().extractTickers(from: text)
        if let first = extracted.first {
            return first
        }

        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let known = [
            "BBCA", "BMRI", "BBRI", "TLKM", "ASII", "BBNI", "GOTO", "ICBP", "UNVR", "AMMN",
            "AAPL", "MSFT", "NVDA", "GOOGL", "AMZN", "META", "TSLA", "AMD", "INTC", "MU"
        ]
        return words.first(where: { known.contains($0.uppercased()) })?.uppercased()
    }

    private func extractLastTickerFromHistory(_ history: [(role: String, content: String)]) -> String? {
        let extractor = StockTickerExtractor()
        for turn in history.reversed() {
            let extracted = extractor.extractTickers(from: turn.content)
            if let first = extracted.first {
                return first
            }

            let words = turn.content.components(separatedBy: CharacterSet.alphanumerics.inverted)
            let known = [
                "BBCA", "BMRI", "BBRI", "TLKM", "ASII", "BBNI", "GOTO", "ICBP", "UNVR", "AMMN",
                "AAPL", "MSFT", "NVDA", "GOOGL", "AMZN", "META", "TSLA", "AMD", "INTC", "MU"
            ]
            if let match = words.first(where: { known.contains($0.uppercased()) })?.uppercased() {
                return match
            }
        }
        return nil
    }

    private func isGeneralPortfolioQuery(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let portfolioKeywords = [
            "semua saham", "all holding", "all holdings", "daftar saham",
            "posisi portofolio", "my portfolio", "portofolio saya", "total aset",
            "total balance", "saldo saya", "nilai portofolio", "alokasi portofolio",
            "simulasi resesi", "simulasi inflasi", "fed rate"
        ]
        return portfolioKeywords.contains { lowered.contains($0) }
    }

    private func isAnaphoricOrFollowUp(_ text: String) -> Bool {
        let lowered = text.lowercased()

        // Explicit pronouns or noun phrases
        let pronounKeywords = [
            " it ", " it?", " it.", " it,", "its",
            "will it", "is it", "can it", "does it", "should it",
            "saham ini", "saham itu", "saham tersebut",
            "emiten ini", "emiten itu", "emiten tersebut",
            "perusahaan ini", "perusahaan itu",
            "ini", "itu", "dia", "tersebut", "tersebut?",
            "this stock", "that stock", "the stock", "this company", "the company"
        ]
        if pronounKeywords.contains(where: { lowered.contains($0) }) || lowered.hasPrefix("it ") || lowered.hasSuffix(" it") || lowered == "it" {
            return true
        }

        // Directional / decision / analysis questions with implicit subject
        let implicitSubjectPatterns = [
            "up or down", "naik atau turun", "naik apa turun", "turun atau naik",
            "will go up", "will go down", "akan naik", "akan turun", "bakal naik", "bakal turun",
            "buy or sell", "beli atau jual", "layak beli", "worth buying", "layak dikoleksi",
            "target price", "target harga", "harga wajar", "fair value", "support", "resistance",
            "rsi", "moving average", "ma20", "ma50", "golden cross", "pe ratio", "pbv", "dividend",
            "bagaimana prospek", "gimana prospek", "prospek kedepan", "prospek ke depan",
            "bagaimana kedepan", "gimana kedepan", "how about future", "how about tomorrow",
            "outlook", "prospeknya", "harganya", "pergerakannya", "rekomendasinya"
        ]
        return implicitSubjectPatterns.contains { lowered.contains($0) }
    }

    private func rewritePrompt(_ prompt: String, with ticker: String) -> String {
        var result = prompt

        // 1. Replace explicit English phrase "will it " -> "will <ticker> "
        if let range = result.range(of: #"(?i)\bwill it\b"#, options: .regularExpression) {
            result.replaceSubrange(range, with: "will \(ticker)")
            return result
        }

        // 2. Replace "is it " -> "is <ticker> "
        if let range = result.range(of: #"(?i)\bis it\b"#, options: .regularExpression) {
            result.replaceSubrange(range, with: "is \(ticker)")
            return result
        }

        // 3. Replace standalone "it" with "<ticker>"
        if let range = result.range(of: #"(?i)\bit\b"#, options: .regularExpression) {
            result.replaceSubrange(range, with: ticker)
            return result
        }

        // 4. Replace Indonesian "saham ini" / "emiten ini" -> "saham <ticker>"
        if let range = result.range(of: #"(?i)\b(saham|emiten)\s+(ini|itu|tersebut)\b"#, options: .regularExpression) {
            result.replaceSubrange(range, with: "saham \(ticker)")
            return result
        }

        // 5. Replace "perusahaan ini" -> "<ticker>"
        if let range = result.range(of: #"(?i)\bperusahaan\s+(ini|itu|tersebut)\b"#, options: .regularExpression) {
            result.replaceSubrange(range, with: "\(ticker)")
            return result
        }

        // 6. If no direct pronoun was replaced (e.g. "bagaimana prospeknya?", "RSI dan supportnya berapa?"),
        // prepend the context explicitly so agents, RAG, and tools understand the subject.
        let isIndonesian = prompt.range(of: #"(?i)\b(bagaimana|gimana|apakah|berapa|naik|turun|prospek|saham)\b"#, options: .regularExpression) != nil
        if isIndonesian {
            return "Mengenai \(ticker): \(prompt)"
        } else {
            return "Regarding \(ticker): \(prompt)"
        }
    }
}
