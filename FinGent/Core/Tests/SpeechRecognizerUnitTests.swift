// Core/Tests/SpeechRecognizerUnitTests.swift

import Foundation

/// Unit test suite verifying Native Apple Speech-to-Text integration:
/// 1. SpeechRecognizerService initialization & initial state
/// 2. Locale selection & toggle (id-ID vs en-US)
/// 3. ChatViewModel speech bindings & real-time text streaming
/// 4. Sending message stops & resets speech state
/// 5. Session reset stops & resets speech state
final class SpeechRecognizerUnitTests: Sendable {

    @MainActor
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

        print("🧪 Running Speech Recognizer Unit Tests...")

        // MARK: - 1. Service Initialization & Locale

        let service = SpeechRecognizerService(preferredLocale: .indonesian)
        assertTest(!service.isListening, name: "SpeechRecognizerService: starts in not-listening state")
        assertTest(service.transcript.isEmpty, name: "SpeechRecognizerService: transcript is initially empty")
        assertTest(service.recognizedWords.isEmpty, name: "SpeechRecognizerService: recognizedWords is initially empty")
        assertTest(service.latestWord.isEmpty, name: "SpeechRecognizerService: latestWord is initially empty")
        assertTest(service.selectedLocale == .indonesian, name: "SpeechRecognizerService: defaults to Indonesian locale")
        assertTest(service.selectedLocale.flag == "🇮🇩", name: "SpeechRecognizerService: Indonesian flag is correct")

        // Switch to English
        service.selectedLocale = .english
        assertTest(service.selectedLocale == .english, name: "SpeechRecognizerService: switches to English")
        assertTest(service.selectedLocale.flag == "🇺🇸", name: "SpeechRecognizerService: English flag is correct")

        // Test permissions method doesn't throw or crash
        let isAuth = await service.requestPermissions()
        assertTest(isAuth == service.isAuthorized, name: "SpeechRecognizerService.requestPermissions: returned matches isAuthorized state")

        // Reset
        service.transcript = "Test speech"
        service.recognizedWords = ["Test", "speech"]
        service.latestWord = "speech"
        service.reset()
        assertTest(service.transcript.isEmpty, name: "SpeechRecognizerService.reset: clears transcript")
        assertTest(service.recognizedWords.isEmpty, name: "SpeechRecognizerService.reset: clears words")
        assertTest(service.latestWord.isEmpty, name: "SpeechRecognizerService.reset: clears latestWord")

        // MARK: - 2. ChatViewModel Integration

        let chatVM = ChatViewModel(
            chatUseCase: ChatUseCase(),
            speechService: service
        )

        assertTest(!chatVM.isListening, name: "ChatViewModel: isListening reflects service state")
        assertTest(chatVM.inputText.isEmpty, name: "ChatViewModel: inputText is initially empty")

        // Simulate streaming transcription update callback
        service.simulateTranscription("apakah saham bbri bagus", segments: ["apakah", "saham", "bbri", "bagus"])
        assertTest(chatVM.speechTranscript == "apakah saham bbri bagus", name: "ChatViewModel: speechTranscript receives live streamed transcription")
        assertTest(chatVM.inputText.isEmpty, name: "ChatViewModel: inputText is untouched by speech recognition")
        assertTest(chatVM.latestWord == "bagus", name: "ChatViewModel: latestWord updates to last spoken word")
        assertTest(chatVM.recognizedWords.count == 4, name: "ChatViewModel: recognizedWords contains all segments")

        // Test locale toggle in ChatViewModel
        let initialLocale = chatVM.speechLocale
        chatVM.toggleSpeechLocale()
        assertTest(chatVM.speechLocale != initialLocale, name: "ChatViewModel.toggleSpeechLocale: toggles locale successfully")

        // Test sending resets speech state
        chatVM.send("apakah saham bbri bagus")
        assertTest(!chatVM.isListening, name: "ChatViewModel.send: stops listening")
        assertTest(service.transcript.isEmpty, name: "ChatViewModel.send: resets speech service transcript")

        // Test resetSession resets speech state
        chatVM.resetSession()
        assertTest(!chatVM.isListening, name: "ChatViewModel.resetSession: stops listening")
        assertTest(chatVM.messages.isEmpty, name: "ChatViewModel.resetSession: clears messages")

        print("🏁 Speech Recognizer Unit Tests Finished: \(passed) passed, \(failed) failed")
        return (passed, failed, errors)
    }
}
