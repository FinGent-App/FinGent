// Core/Data/Network/RSS/RSSParser.swift

import Foundation
import CryptoKit

// MARK: - RSSParser

final class RSSParser: NSObject, XMLParserDelegate, Sendable {

    // Parsed intermediate item
    private final class ItemBuilder {
        var title: String = ""
        var link: String = ""
        var guid: String = ""
        var itemDescription: String = ""
        var pubDate: String = ""
        var author: String = ""
        var imageURL: String = ""
    }

    // State maintained during parsing
    private var currentElement: String = ""
    private var currentCharacters: String = ""
    private var currentItem: ItemBuilder?
    private var items: [ItemBuilder] = []

    private let defaultSource: NewsSourceType

    init(defaultSource: NewsSourceType) {
        self.defaultSource = defaultSource
        super.init()
    }

    // MARK: - Public Parse Method

    func parse(data: Data) -> [NewsArticle] {
        self.items = []
        self.currentItem = nil
        self.currentCharacters = ""

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return []
        }

        return items.compactMap { builder -> NewsArticle? in
            let cleanTitle = Self.sanitize(builder.title)
            guard !cleanTitle.isEmpty else { return nil }

            let rawLink = builder.link.isEmpty ? builder.guid : builder.link
            let cleanLink = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: cleanLink) else { return nil }

            let id = Self.generateDeterministicId(from: cleanLink)
            let publishedAt = Self.parseDate(builder.pubDate) ?? Date()
            let cleanSummary = Self.sanitize(builder.itemDescription)
            let imageURL = URL(string: builder.imageURL.trimmingCharacters(in: .whitespacesAndNewlines))
            let cleanAuthor = builder.author.isEmpty ? nil : Self.sanitize(builder.author)

            return NewsArticle(
                id: id,
                title: cleanTitle,
                summary: cleanSummary.isEmpty ? nil : cleanSummary,
                url: url,
                source: self.defaultSource,
                publishedAt: publishedAt,
                author: cleanAuthor,
                imageURL: imageURL,
                tickers: [],
                fetchedAt: Date()
            )
        }
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let tag = elementName.lowercased()
        currentElement = tag
        currentCharacters = ""

        if tag == "item" || tag == "entry" {
            currentItem = ItemBuilder()
        }

        // Check media/enclosure attributes
        if tag == "enclosure" || tag == "media:content" || tag == "content" {
            if let mediaUrl = attributeDict["url"], currentItem?.imageURL.isEmpty ?? false {
                currentItem?.imageURL = mediaUrl
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentCharacters += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            currentCharacters += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let item = currentItem else { return }
        let tag = elementName.lowercased()
        let trimmed = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

        switch tag {
        case "title":
            if item.title.isEmpty { item.title = trimmed }
        case "link":
            if item.link.isEmpty { item.link = trimmed }
        case "guid", "id":
            if item.guid.isEmpty { item.guid = trimmed }
        case "description", "summary", "content:encoded":
            if item.itemDescription.isEmpty { item.itemDescription = trimmed }
        case "pubdate", "published", "updated", "dc:date":
            if item.pubDate.isEmpty { item.pubDate = trimmed }
        case "author", "dc:creator":
            if item.author.isEmpty { item.author = trimmed }
        case "item", "entry":
            items.append(item)
            currentItem = nil
        default:
            break
        }
    }

    // MARK: - Deterministic ID Generation (SHA-256 of normalized URL)

    static func generateDeterministicId(from rawURL: String) -> String {
        // Strip tracking parameters (?tsrc=rss, etc.)
        let normalized: String
        if let url = URL(string: rawURL), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.query = nil
            components.fragment = nil
            normalized = components.string ?? rawURL
        } else {
            normalized = rawURL
        }

        let inputData = Data(normalized.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Date Parsing

    static func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Formatter cache
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        // Try ISO8601DateFormatter
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        return nil
    }

    // MARK: - HTML Stripping & Entity Decoding

    static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        // Remove HTML tags
        var cleaned = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        let entities = [
            ("&quot;", "\""),
            ("&amp;", "&"),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&#8216;", "‘"),
            ("&#8217;", "’"),
            ("&#8220;", "“"),
            ("&#8221;", "”")
        ]

        for (entity, replacement) in entities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }

        // Collapse excess whitespace
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
