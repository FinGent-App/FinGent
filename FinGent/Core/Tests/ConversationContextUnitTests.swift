// Core/Tests/ConversationContextUnitTests.swift

import Foundation

/// Unit tests for ConversationContextManager:
/// 1. Ticker retention from initial turn (e.g. "how is bbca prospect in future")
/// 2. Pronoun resolution ("will it go up or down" -> "will BBCA go up or down")
/// 3. Indonesian follow-up resolution ("apakah saham ini akan naik?" -> "apakah saham BBCA akan naik?")
/// 4. Context switching to a new stock (e.g. "kalau NVDA gimana?")
/// 5. General portfolio queries preserved without false ticker injection
/// 6. History recovery when in-memory ticker is reset
final class ConversationContextUnitTests: Sendable {

    static func runAllTests() -> (passed: Int, failed: Int, errors: [String]) {
        var passed = 0
        var failed = 0
        var errors: [String] = []

        func assertTest(_ condition: Bool, name: String) {
            if condition {
                passed += 1
                print("  ✅ [PASS] \(name)")
            } else {
                failed += 1
                let msg = "❌ [FAIL] \(name)"
                print("  " + msg)
                errors.append(msg)
            }
        }

        print("🧪 Running Conversation Context Memory Unit Tests...")
        let context = ConversationContextManager.shared

        // Test 1: Initial query with explicit ticker BBCA sets active context
        context.reset()
        let t1 = context.enrichPromptIfFollowUp("how is bbca prospect in future")
        assertTest(
            t1.resolvedTicker == "BBCA" && context.activeTickerContext == "BBCA" && !t1.wasEnriched,
            name: "Initial query sets active ticker context to BBCA"
        )

        // Test 2: Follow-up "will it go up or down" resolves "it" to BBCA
        let t2 = context.enrichPromptIfFollowUp("will it go up or down")
        assertTest(
            t2.resolvedTicker == "BBCA" && t2.wasEnriched && t2.enrichedPrompt.contains("will BBCA go up or down"),
            name: "English pronoun 'it' rewrites to 'will BBCA go up or down'"
        )

        // Test 3: Indonesian follow-up "apakah saham ini akan naik atau turun?"
        let t3 = context.enrichPromptIfFollowUp("apakah saham ini akan naik atau turun?")
        assertTest(
            t3.resolvedTicker == "BBCA" && t3.wasEnriched && t3.enrichedPrompt.contains("saham BBCA"),
            name: "Indonesian 'saham ini' rewrites to 'saham BBCA'"
        )

        // Test 4: Follow-up without pronoun "prospeknya bagaimana?"
        let t4 = context.enrichPromptIfFollowUp("prospeknya bagaimana?")
        assertTest(
            t4.resolvedTicker == "BBCA" && t4.wasEnriched && t4.enrichedPrompt.contains("Mengenai BBCA:"),
            name: "Implicit follow-up prepends 'Mengenai BBCA:' context"
        )

        // Test 5: Context switch to new ticker "kalau NVDA gimana?"
        let t5 = context.enrichPromptIfFollowUp("kalau NVDA gimana?")
        assertTest(
            t5.resolvedTicker == "NVDA" && context.activeTickerContext == "NVDA",
            name: "New ticker 'NVDA' switches active context from BBCA to NVDA"
        )

        // Test 6: Subsequent follow-up refers to new context NVDA
        let t6 = context.enrichPromptIfFollowUp("is it a buy right now?")
        assertTest(
            t6.resolvedTicker == "NVDA" && t6.wasEnriched && t6.enrichedPrompt.contains("is NVDA a buy right now?"),
            name: "Subsequent pronoun 'it' refers to newly switched NVDA context"
        )

        // Test 7: General portfolio query is not mutated
        let t7 = context.enrichPromptIfFollowUp("tampilkan semua saham di portofolio saya")
        assertTest(
            !t7.wasEnriched && t7.enrichedPrompt == "tampilkan semua saham di portofolio saya",
            name: "General portfolio query preserves original text without ticker injection"
        )

        // Test 8: Recovery from conversation history when in-memory context was reset
        context.reset()
        let mockHistory: [(role: String, content: String)] = [
            ("user", "Analisis saham TLKM dong"),
            ("assistant", "TLKM saat ini diperdagangkan pada level 2950 dengan valuasi menarik.")
        ]
        let t8 = context.enrichPromptIfFollowUp("apakah layak beli?", fallbackHistory: mockHistory)
        assertTest(
            t8.resolvedTicker == "TLKM" && t8.wasEnriched && context.activeTickerContext == "TLKM",
            name: "History fallback restores last referenced ticker TLKM"
        )

        return (passed, failed, errors)
    }
}
