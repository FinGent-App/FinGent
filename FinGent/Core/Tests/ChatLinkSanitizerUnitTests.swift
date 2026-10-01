// Core/Tests/ChatLinkSanitizerUnitTests.swift

import Foundation

/// Unit tests for ChatUseCase.sanitizeFriendlyText
/// Ensures responses do not contain long, messy raw URLs or source link tags in the message body,
/// while keeping citations available as structured metadata for the app's interactive source logos.
final class ChatLinkSanitizerUnitTests: Sendable {

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

        print("🧪 Running Chat Link Sanitizer Unit Tests...")

        // Test 1: Strips raw standalone https:// URL
        let input1 = "Informasi lengkap saham BBCA di https://finance.yahoo.com/quote/BBCA.JK hari ini."
        let out1 = ChatUseCase.sanitizeFriendlyText(input1)
        assertTest(!out1.contains("http") && out1.contains("Informasi lengkap saham BBCA di hari ini."), name: "Strips standalone https URL")

        // Test 2: Strips 'Link: https://...' line
        let input2 = """
        • Laba Bersih BBCA Tumbuh 12% (Kontan)
          Link: https://investasi.kontan.co.id/news/laba-bersih-bbca-12345
        • Saham BBCA Menguat
        """
        let out2 = ChatUseCase.sanitizeFriendlyText(input2)
        assertTest(!out2.contains("Link:") && !out2.contains("http") && out2.contains("Laba Bersih BBCA Tumbuh 12% (Kontan)"), name: "Strips 'Link: https://...' line")

        // Test 3: Strips 'Sumber: https://...' line
        let input3 = """
        • Kinerja Kuartal II Bank Mandiri
          Sumber: https://bisnis.com/market/read/123456/kinerja-bmri
        """
        let out3 = ChatUseCase.sanitizeFriendlyText(input3)
        assertTest(!out3.contains("Sumber:") && !out3.contains("http") && out3.contains("Kinerja Kuartal II Bank Mandiri"), name: "Strips 'Sumber: https://...' line")

        // Test 4: Converts markdown link [Title](https://...) to Title
        let input4 = "Simak rinciannya di [Laporan Keuangan BBCA](https://www.idx.co.id/perusahaan-tercatat) sekarang."
        let out4 = ChatUseCase.sanitizeFriendlyText(input4)
        assertTest(out4.contains("Simak rinciannya di Laporan Keuangan BBCA sekarang.") && !out4.contains("http"), name: "Converts markdown link to label text")

        // Test 5: Drops markdown link if the title itself is a URL
        let input5 = "Kunjungi [https://sec.gov](https://sec.gov) untuk arsip 10-K."
        let out5 = ChatUseCase.sanitizeFriendlyText(input5)
        assertTest(!out5.contains("http") && out5.contains("Kunjungi untuk arsip 10-K."), name: "Drops markdown link when label is URL")

        // Test 6: Strips parenthesized source link '(Sumber: https://...)'
        let input6 = "IHSG ditutup di level 7.800 (Sumber: https://market.bisnis.com)."
        let out6 = ChatUseCase.sanitizeFriendlyText(input6)
        assertTest(!out6.contains("Sumber:") && !out6.contains("http") && out6 == "IHSG ditutup di level 7.800.", name: "Strips parenthesized (Sumber: https://...) and fixes punctuation spacing")

        // Test 7: Cleans up dangling empty 'Sumber:' or 'Link:' labels left on separate lines
        let input7 = """
        • Perkembangan IHSG
          Sumber:
          https://kontan.co.id/news/ihsg
        """
        let out7 = ChatUseCase.sanitizeFriendlyText(input7)
        assertTest(!out7.contains("Sumber:") && !out7.contains("http") && out7.contains("Perkembangan IHSG"), name: "Cleans dangling empty 'Sumber:' label")

        // Test 8: Collapses multiple blank lines and trims
        let input8 = "Paragraf 1\n\n\n\nParagraf 2\n\n\n"
        let out8 = ChatUseCase.sanitizeFriendlyText(input8)
        assertTest(out8 == "Paragraf 1\n\nParagraf 2", name: "Collapses 3+ newlines to 2 and trims")

        // Test 9: Strips markdown bold asterisks and headers
        let input9 = "### Ringkasan Riset\n**BBCA** memiliki rekomendasi ***BUY***."
        let out9 = ChatUseCase.sanitizeFriendlyText(input9)
        assertTest(!out9.contains("*") && !out9.contains("#") && out9.contains("Ringkasan Riset\nBBCA memiliki rekomendasi BUY."), name: "Strips markdown bold and headers")

        print("🏁 Chat Link Sanitizer Tests Completed: \(passed) passed, \(failed) failed.")
        return (passed, failed, errors)
    }
}
