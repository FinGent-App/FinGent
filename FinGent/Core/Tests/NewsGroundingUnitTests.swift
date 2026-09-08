// Core/Tests/NewsGroundingUnitTests.swift

import Foundation

/// Standalone test suite verifying the News Grounding pipeline:
/// 1. RSS Parser (valid, invalid, missing fields, deterministic SHA-256 IDs)
/// 2. Ticker Extractor (company aliases, symbol boundaries, false positive filtering)
/// 3. Query Analyzer & News Retrieval (MU query -> MU news, conceptual -> no news)
/// 4. Relevance Ranking (ticker match, keyword, recency, source)
/// 5. Citation & AI Response consistency
final class NewsGroundingUnitTests: Sendable {

    static func runAllTests() async -> (passed: Int, failed: Int, errors: [String]) {
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

        print("🧪 Running News Grounding Unit Tests...")

        // MARK: - 1. RSS Parser Tests

        // Test 1.1: Valid RSS 2.0 XML
        let sampleValidRSS = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Yahoo Finance: Market News</title>
                <link>https://finance.yahoo.com</link>
                <item>
                    <title>Micron &amp; Nvidia Surge on Strong AI Memory Demand</title>
                    <link>https://finance.yahoo.com/news/micron-nvidia-surge-1234.html?tsrc=rss</link>
                    <guid isPermaLink="false">guid-1234</guid>
                    <pubDate>Mon, 07 Sep 2026 08:30:00 +0000</pubDate>
                    <description>&lt;p&gt;Micron Technology shares rose 6% after guidance hike.&lt;/p&gt;</description>
                    <author>Jane Doe</author>
                </item>
            </channel>
        </rss>
        """

        let parser = RSSParser(defaultSource: .yahooFinance)
        let articles = parser.parse(data: Data(sampleValidRSS.utf8))
        assertTest(articles.count == 1, name: "RSS Parser: parses valid item")

        if let first = articles.first {
            assertTest(first.title == "Micron & Nvidia Surge on Strong AI Memory Demand", name: "RSS Parser: unescapes HTML entities in title")
            assertTest(first.summary == "Micron Technology shares rose 6% after guidance hike.", name: "RSS Parser: strips HTML tags from description")
            assertTest(first.author == "Jane Doe", name: "RSS Parser: extracts author correctly")
            assertTest(!first.id.isEmpty, name: "RSS Parser: generates deterministic non-empty ID")

            // Test 1.2: Deterministic ID verification (tracking params stripped)
            let id1 = RSSParser.generateDeterministicId(from: "https://finance.yahoo.com/news/article-1.html?tsrc=rss&utm_source=feed")
            let id2 = RSSParser.generateDeterministicId(from: "https://finance.yahoo.com/news/article-1.html")
            assertTest(id1 == id2, name: "RSS Parser: ID is deterministic and strips query params")
        }

        // Test 1.3: Invalid / Malformed RSS
        let invalidRSS = "<invalid>This is not an RSS feed</item>"
        let invalidArticles = parser.parse(data: Data(invalidRSS.utf8))
        assertTest(invalidArticles.isEmpty, name: "RSS Parser: returns empty array on invalid XML without crashing")

        // Test 1.4: Missing Title or Link
        let missingLinkRSS = """
        <rss version="2.0"><channel><item><title>Headline Without Link</title></item></channel></rss>
        """
        let noLinkArticles = parser.parse(data: Data(missingLinkRSS.utf8))
        assertTest(noLinkArticles.isEmpty, name: "RSS Parser: skips items with missing link and guid")

        // MARK: - 2. Ticker Extraction Tests

        let extractor = StockTickerExtractor()

        // Test 2.1: Known company name alias -> ticker
        let t1 = extractor.extractTickers(from: "Micron shares rose sharply today following upbeat comments.")
        assertTest(t1.contains("MU"), name: "Ticker Extractor: extracts 'MU' from company name 'Micron'")

        let t2 = extractor.extractTickers(from: "NVIDIA announces new Blackwell platform delivery date.")
        assertTest(t2.contains("NVDA"), name: "Ticker Extractor: extracts 'NVDA' from 'NVIDIA'")

        let t3 = extractor.extractTickers(from: "Apple and Microsoft reported strong quarterly earnings growth.")
        assertTest(t3.contains("AAPL") && t3.contains("MSFT"), name: "Ticker Extractor: extracts multiple US tech tickers 'AAPL' & 'MSFT'")

        // Test 2.2: Explicit symbol syntax ($TSLA, (NASDAQ:AAPL), and parenthetical (XYZ))
        let t4 = extractor.extractTickers(from: "Stock $TSLA, (NASDAQ:AAPL), and (BBCA) reached new milestones.")
        assertTest(t4.contains("TSLA") && t4.contains("AAPL") && t4.contains("BBCA"), name: "Ticker Extractor: extracts from $TSLA, (NASDAQ:AAPL), and (BBCA)")

        // Test 2.3: Avoid False Positives on single-letter/common English words
        let t5 = extractor.extractTickers(from: "An investor is in for a treat today with all the news.")
        assertTest(!t5.contains("A") && !t5.contains("IN") && !t5.contains("IT") && !t5.contains("FOR") && !t5.contains("ALL"), name: "Ticker Extractor: avoids false positives for 'A', 'IN', 'IT', 'FOR', 'ALL'")

        // MARK: - 3. Query Analyzer Tests

        let analyzer = QueryAnalyzer(extractor: extractor)

        // Test 3.1: Stock Outlook Query -> requiresNews: true
        let q1 = analyzer.analyze(prompt: "Apakah MU akan naik atau turun?")
        assertTest(q1.requiresNews == true && q1.tickers.contains("MU"), name: "Query Analyzer: 'Apakah MU akan naik atau turun?' requires news and detects MU")

        // Test 3.2: Catalyst Query -> requiresNews: true
        let q2 = analyzer.analyze(prompt: "Apa katalis terbaru untuk saham Micron?")
        assertTest(q2.requiresNews == true && q2.tickers.contains("MU") && q2.queryType == .newsCatalyst, name: "Query Analyzer: 'Apa katalis terbaru untuk saham Micron?' detects catalyst and MU")

        // Test 3.3: Conceptual Query -> requiresNews: false
        let q3 = analyzer.analyze(prompt: "Apa itu P/E ratio?")
        assertTest(q3.requiresNews == false && q3.tickers.isEmpty, name: "Query Analyzer: 'Apa itu P/E ratio?' correctly sets requiresNews = false")

        let q4 = analyzer.analyze(prompt: "Bagaimana cara membaca grafik candlestick?")
        assertTest(q4.requiresNews == false, name: "Query Analyzer: 'Bagaimana cara membaca candlestick' sets requiresNews = false")

        // MARK: - 4. Relevance Ranking Tests

        let rankingService = NewsRankingService()

        let artA = NewsArticle(
            id: "art-mu-1",
            title: "Micron Reports Record Revenue on AI HBM Demand",
            summary: "MU quarterly results beat analyst expectations.",
            url: URL(string: "https://finance.yahoo.com/news/mu-1")!,
            source: .yahooFinance,
            publishedAt: Date().addingTimeInterval(-3600 * 2), // 2 hours ago
            tickers: ["MU"]
        )

        let artB = NewsArticle(
            id: "art-apple-old",
            title: "Apple Announces New Accessories",
            summary: "New cases and cables.",
            url: URL(string: "https://finance.yahoo.com/news/aapl-old")!,
            source: .yahooFinance,
            publishedAt: Date().addingTimeInterval(-3600 * 24 * 10), // 10 days ago
            tickers: ["AAPL"]
        )

        let ranked = rankingService.rank(articles: [artB, artA], for: q1, userPrompt: "Apakah MU akan naik atau turun?")
        assertTest(ranked.first?.id == "art-mu-1", name: "News Ranking: ranks relevant ticker MU above unrelated old article")

        // MARK: - 5. Citation & AI Response Integrity Tests

        let citation = NewsCitation(from: artA)
        assertTest(citation.id == artA.id, name: "Citation Integrity: citation ID matches article ID")
        assertTest(citation.url == artA.url, name: "Citation Integrity: citation URL matches article URL")
        assertTest(citation.source == .yahooFinance, name: "Citation Integrity: citation source matches")

        let aiResponse = AIResponse(
            answer: "MU saat ini memiliki bias bullish berdasarkan katalis HBM terbaru.",
            bias: .bullish,
            confidence: 0.78,
            sources: [citation]
        )
        assertTest(aiResponse.bias == .bullish, name: "AI Response: structured bias is preserved")
        assertTest(aiResponse.sources.count == 1, name: "AI Response: sources count is consistent")

        print("🏁 Finished News Grounding Unit Tests: \(passed) passed, \(failed) failed.")
        return (passed, failed, errors)
    }
}
