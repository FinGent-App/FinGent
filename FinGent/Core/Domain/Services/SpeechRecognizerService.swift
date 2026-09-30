// Core/Domain/Services/SpeechRecognizerService.swift

import Foundation
import Speech
import AVFoundation
import Observation

/// Native Apple Speech-to-Text service utilizing SFSpeechRecognizer and AVAudioEngine.
/// Transcribes live speech into text in real time with per-word streaming updates.
@Observable
@MainActor
final class SpeechRecognizerService {

    // MARK: - Speech Locale Options

    enum SpeechLocale: String, CaseIterable, Identifiable, Sendable {
        case indonesian = "id-ID"
        case english = "en-US"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .indonesian: return "Indonesia (ID)"
            case .english: return "English (US)"
            }
        }

        var flag: String {
            switch self {
            case .indonesian: return "🇮🇩"
            case .english: return "🇺🇸"
            }
        }
    }

    // MARK: - Published State

    var isListening: Bool = false
    var transcript: String = ""
    var recognizedWords: [String] = []
    var latestWord: String = ""
    var audioLevel: CGFloat = 0.0
    var isSpeaking: Bool = false
    var isAuthorized: Bool = false
    var errorMessage: String? = nil
    var selectedLocale: SpeechLocale = .indonesian {
        didSet {
            if isListening {
                restartListening()
            }
        }
    }

    // Callback for live transcription updates: (fullTranscript, wordsList)
    var onTranscriptionUpdate: ((String, [String]) -> Void)? = nil
    // Callback when silence is detected after speaking: (completedTranscript)
    var onSilenceDetected: ((String) -> Void)? = nil
    private var silenceTimer: Task<Void, Never>? = nil

    // MARK: - Private Engine Components

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Init

    init(preferredLocale: SpeechLocale = .indonesian) {
        self.selectedLocale = preferredLocale
    }

    deinit {
        // Stop audio engine if still active
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    // MARK: - Permission Handling

    /// Requests permissions for both Speech Recognition and Microphone.
    @discardableResult
    func requestPermissions() async -> Bool {
        // Fast synchronous check if already authorized
        let currentSpeech = SFSpeechRecognizer.authorizationStatus()
        let currentMic: Bool
        if #available(iOS 17.0, *) {
            currentMic = AVAudioApplication.shared.recordPermission == .granted
        } else {
            currentMic = AVAudioSession.sharedInstance().recordPermission == .granted
        }

        if currentSpeech == .authorized && currentMic {
            self.errorMessage = nil
            self.isAuthorized = true
            return true
        }

        // Request Speech Recognition permission if needed
        let speechAuthorized: Bool
        if currentSpeech == .authorized {
            speechAuthorized = true
        } else {
            speechAuthorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }

        guard speechAuthorized else {
            self.errorMessage = "Izin Speech Recognition ditolak. Mohon aktifkan di Pengaturan."
            self.isAuthorized = false
            return false
        }

        // Request Microphone permission if needed
        let micAuthorized: Bool
        if currentMic {
            micAuthorized = true
        } else if #available(iOS 17.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micAuthorized else {
            self.errorMessage = "Izin Mikrofon ditolak. Mohon aktifkan di Pengaturan."
            self.isAuthorized = false
            return false
        }

        self.errorMessage = nil
        self.isAuthorized = true
        return true
    }

    // MARK: - Control Actions

    /// Starts audio recording and real-time speech transcription.
    func startListening(onUpdate: ((String, [String]) -> Void)? = nil) {
        print("🎤 [SpeechService] startListening called. isListening=\(isListening)")
        if let onUpdate = onUpdate {
            self.onTranscriptionUpdate = onUpdate
        }

        Task {
            print("🎤 [SpeechService] Requesting permissions...")
            let authorized = await requestPermissions()
            print("🎤 [SpeechService] Permissions result: \(authorized)")
            guard authorized else { return }

            self.beginRecording()
        }
    }

    /// Stops audio recording and finalizes recognition task.
    func stopListening() {
        print("🎤 [SpeechService] stopListening called. isListening=\(isListening), engineRunning=\(audioEngine.isRunning)")
        guard isListening || audioEngine.isRunning else {
            isListening = false
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        silenceTimer?.cancel()
        silenceTimer = nil
        isListening = false
        audioLevel = 0.0
        isSpeaking = false

        Task.detached(priority: .background) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Toggles listening on or off.
    func toggleListening() {
        print("🎤 [SpeechService] toggleListening called. Current isListening=\(isListening)")
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    /// Resets all accumulated speech data.
    func reset() {
        print("🎤 [SpeechService] reset called")
        stopListening()
        silenceTimer?.cancel()
        silenceTimer = nil
        transcript = ""
        recognizedWords = []
        latestWord = ""
        audioLevel = 0.0
        isSpeaking = false
        errorMessage = nil
    }

    /// Updates transcription state with formatted string and segment tokens (useful for testing or direct text injection).
    func simulateTranscription(_ formatted: String, segments: [String]) {
        self.transcript = formatted
        self.recognizedWords = segments
        self.latestWord = segments.last ?? ""
        self.isSpeaking = true
        self.audioLevel = 0.5
        self.onTranscriptionUpdate?(formatted, segments)
    }

    private func restartListening() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.startListening()
        }
    }

    // MARK: - Private Engine Setup

    private func beginRecording() {
        print("🎤 [SpeechService] beginRecording starting...")
        // Cancel any pending task
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // Configure Audio Session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("🎤 [SpeechService] AudioSession successfully configured and activated")
        } catch {
            print("❌ [SpeechService] AudioSession error: \(error.localizedDescription)")
            self.errorMessage = "Gagal menginisialisasi sesi audio: \(error.localizedDescription)"
            self.isListening = false
            return
        }

        // Initialize SFSpeechRecognizer with chosen locale
        let locale = Locale(identifier: selectedLocale.rawValue)
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale.autoupdatingCurrent) ?? SFSpeechRecognizer()

        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("❌ [SpeechService] Speech recognizer not available for locale \(selectedLocale.rawValue)")
            self.errorMessage = "Layanan pengenalan suara tidak tersedia untuk bahasa ini saat ini."
            self.isListening = false
            return
        }
        self.speechRecognizer = recognizer

        // Create Recognition Request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        // Setup input node & audio tap
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        audioEngine.prepare()

        let nodeFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat: AVAudioFormat
        if nodeFormat.sampleRate > 0 && nodeFormat.channelCount > 0 {
            recordingFormat = nodeFormat
        } else if let fallbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) {
            recordingFormat = fallbackFormat
        } else {
            recordingFormat = nodeFormat
        }
        print("🎤 [SpeechService] inputNode recordingFormat: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            let level = min(max(CGFloat(rms * 9.0), 0.0), 1.0)

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioLevel = level
                if level > 0.04 {
                    self.isSpeaking = true
                }
            }
        }

        // Start recognition task
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let formatted = result.bestTranscription.formattedString
                let segments = result.bestTranscription.segments.map { $0.substring }
                let lastWord = segments.last ?? ""

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.transcript = formatted
                    self.recognizedWords = segments
                    self.latestWord = lastWord
                    self.isSpeaking = true
                    self.onTranscriptionUpdate?(formatted, segments)

                    self.silenceTimer?.cancel()
                    let currentTranscript = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !currentTranscript.isEmpty {
                        self.silenceTimer = Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                guard let self = self, !self.transcript.isEmpty else { return }
                                self.isSpeaking = false
                                self.onSilenceDetected?(self.transcript)
                            }
                        }
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Filter out standard cancellation codes (216, 203, kAFAssistantErrorDomain)
                let isCancel = (nsError.code == 216 || nsError.code == 203 || nsError.domain == "kAFAssistantErrorDomain")
                print("🎤 [SpeechService] Task callback with error: code=\(nsError.code), domain=\(nsError.domain), isCancel=\(isCancel)")
                if !isCancel {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.stopListening()
                    }
                }
            } else if result?.isFinal == true {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            self.isListening = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Tidak dapat memulai engine audio: \(error.localizedDescription)"
            self.stopListening()
        }
    }
}
