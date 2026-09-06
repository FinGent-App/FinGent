// Core/Data/Repository/NewsRepository.swift

import Foundation

final class NewsRepository: NewsRepositoryProtocol {

    static let shared = NewsRepository()

    private init() {}

    // MARK: - NewsRepositoryProtocol

    let allArticles: [NewsArticle] = [
        NewsArticle(id: "1", title: "Bank Indonesia Holds Interest Rate at 5.75%, Supports Rupiah Stability", source: "CNBC Indonesia", date: "2026-09-04", summary: "Bank Indonesia maintained its benchmark interest rate at 5.75% for the third consecutive month, citing the need to stabilize the rupiah exchange rate amid global uncertainty.", sentiment: .neutral, relatedTickers: ["BBCA", "BBRI", "BMRI"]),
        NewsArticle(id: "2", title: "BBCA Reports Record Q2 Net Profit of Rp 13.2 Trillion", source: "Bisnis Indonesia", date: "2026-09-03", summary: "Bank Central Asia recorded its highest-ever quarterly net profit of Rp 13.2 trillion in Q2 2026, driven by strong loan growth of 12% YoY and improved net interest margin.", sentiment: .positive, relatedTickers: ["BBCA"]),
        NewsArticle(id: "3", title: "GoTo Achieves First Full-Year Profitability, Stock Surges", source: "Kontan", date: "2026-09-03", summary: "GoTo Gojek Tokopedia reported its first full-year EBITDA profitability, marking a significant milestone for Indonesia's tech sector. The stock jumped 5% on the news.", sentiment: .positive, relatedTickers: ["GOTO", "EMTK"]),
        NewsArticle(id: "4", title: "Unilever Indonesia Faces Margin Pressure from Rising Raw Material Costs", source: "Investor Daily", date: "2026-09-02", summary: "Unilever Indonesia reported a 15% decline in Q2 net profit as rising palm oil and packaging costs squeezed margins. Management guided for continued cost pressures in H2.", sentiment: .negative, relatedTickers: ["UNVR"]),
        NewsArticle(id: "5", title: "IHSG Hits New All-Time High Above 8,200, Foreign Inflows Surge", source: "Detik Finance", date: "2026-09-04", summary: "The Jakarta Composite Index (IHSG) breached the 8,200 level for the first time, supported by strong foreign net buying of Rp 2.1 trillion in banking stocks.", sentiment: .positive, relatedTickers: ["BBCA", "BBRI", "BMRI"]),
        NewsArticle(id: "6", title: "Astra International Sees Strong Auto Sales in August, EV Adoption Grows", source: "Tempo", date: "2026-09-03", summary: "Astra International reported a 18% YoY increase in August auto sales, with electric vehicle sales contributing 12% of total units sold for the first time.", sentiment: .positive, relatedTickers: ["ASII"]),
        NewsArticle(id: "7", title: "Telkom Indonesia Accelerates 5G Rollout Across Java", source: "Kompas", date: "2026-09-02", summary: "Telkom Indonesia announced plans to deploy 5G in 15 additional cities across Java by year-end, investing Rp 8 trillion in network infrastructure upgrades.", sentiment: .positive, relatedTickers: ["TLKM"]),
        NewsArticle(id: "8", title: "The Fed Signals Potential Rate Cut in Q4, Asian Markets Rally", source: "Reuters", date: "2026-09-04", summary: "Federal Reserve officials hinted at a potential 25bps rate cut in the fourth quarter, sending Asian equities higher as expectations for easier monetary policy grow.", sentiment: .positive, relatedTickers: ["BBCA", "BBRI", "BMRI", "GOTO"]),
        NewsArticle(id: "9", title: "Barito Renewables Secures $500M Green Bond for Solar Projects", source: "Jakarta Post", date: "2026-09-01", summary: "Barito Renewables successfully issued a $500 million green bond to fund solar power projects across Indonesia, with orders oversubscribed 3x.", sentiment: .positive, relatedTickers: ["BREN"]),
        NewsArticle(id: "10", title: "Rupiah Weakens to 15,800 per USD Amid Global Risk-Off Sentiment", source: "Bloomberg", date: "2026-09-04", summary: "The Indonesian rupiah weakened 0.5% to 15,800 per US dollar as global risk-off sentiment impacted emerging market currencies. Bank Indonesia pledged to intervene if needed.", sentiment: .negative, relatedTickers: ["BBCA", "BBRI", "BMRI"]),
        NewsArticle(id: "11", title: "Amman Mineral Production Falls Short of Q3 Guidance", source: "Mining Weekly", date: "2026-09-03", summary: "Amman Mineral Internasional reported lower-than-expected copper and gold production in Q3 due to planned maintenance shutdowns at its Batu Hijau mine.", sentiment: .negative, relatedTickers: ["AMMN"]),
        NewsArticle(id: "12", title: "Indonesia's GDP Growth Accelerates to 5.3% in Q2 2026", source: "World Bank", date: "2026-09-01", summary: "Indonesia's economy grew 5.3% YoY in Q2 2026, beating expectations of 5.1%, driven by strong domestic consumption and government infrastructure spending.", sentiment: .positive, relatedTickers: ["BBCA", "BBRI", "ASII", "TLKM"])
    ]

    func searchArticles(query: String) -> [NewsArticle] {
        let lowered = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return allArticles }

        let stopWords: Set<String> = ["my", "about", "the", "a", "an", "is", "there", "any",
                                      "news", "berita", "saham", "stock", "holding", "holdings"]
        let keywords = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }

        return allArticles.filter { article in
            let title = article.title.lowercased()
            let summary = article.summary.lowercased()
            let tickers = article.relatedTickers.map { $0.lowercased() }

            if title.contains(lowered) || summary.contains(lowered) || tickers.contains(lowered) {
                return true
            }
            return keywords.contains { word in
                tickers.contains(word) || title.contains(word) || summary.contains(word)
            }
        }
    }

    func getArticles(for tickers: [String]) -> [NewsArticle] {
        let upperTickers = Set(tickers.map { $0.uppercased() })
        return allArticles.filter { !Set($0.relatedTickers).isDisjoint(with: upperTickers) }
    }
}
