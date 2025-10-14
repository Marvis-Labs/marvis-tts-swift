import AVFoundation
import MarvisTTS
import MLX

protocol SpeechControllerDelegate: AnyObject {
    func speechController(_ controller: SpeechController, didFinish buffer: AVAudioPCMBuffer, transcription: String)
}

@Observable
final class SpeechController {
    @ObservationIgnored
    weak var delegate: SpeechControllerDelegate?

    private(set) var isActive: Bool = false
    private(set) var isDetectingSpeech = false
    private(set) var canSpeak: Bool = false
    private(set) var isSpeaking: Bool = false

    var isMicrophoneMuted: Bool {
        audioEngine.isMicrophoneMuted
    }

    @ObservationIgnored
    private let audioEngine: AudioEngine
    @ObservationIgnored
    private var configuredAudioEngine = false
    @ObservationIgnored
    private let vad: SimpleVAD
    @ObservationIgnored
    private var model: MarvisTTS?

    init(ttsRepoId: String = "Marvis-AI/marvis-tts-250m-v0.1-MLX-8bit") {
        self.audioEngine = AudioEngine(inputBufferSize: 1024)
        self.vad = SimpleVAD()
        audioEngine.delegate = self
        vad.delegate = self

        Task {
#if !targetEnvironment(simulator)
            print("Memory before loading TTS model: \(MLX.GPU.snapshot())")
            self.model = try await MarvisTTS.fromPretrained(repoId: ttsRepoId) { _ in }
            print("Memory after loading TTS model: \(MLX.GPU.snapshot())")

            self.canSpeak = model != nil
#endif
        }
    }

    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false)
        try session.setCategory(.playAndRecord, mode: .voiceChat, policy: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        try await ensureEngineStarted()
        isActive = true
    }

    func stop() async throws {
        audioEngine.endSpeaking()
        audioEngine.stop()
        isDetectingSpeech = false
        vad.reset()
        try AVAudioSession.sharedInstance().setActive(false)
        isActive = false
    }

    func toggleInputMute(toMuted: Bool?) async {
        let currentMuted = audioEngine.isMicrophoneMuted
        let newMuted = toMuted ?? !currentMuted
        audioEngine.isMicrophoneMuted = newMuted

        if newMuted, isDetectingSpeech {
            vad.reset()
            isDetectingSpeech = false
        }
    }

    func stopSpeaking() async {
        audioEngine.endSpeaking()
    }

    func speak(text: String) async throws {
        guard let model else {
            print("TTS model not loaded.")
            return
        }
        let stream = proxyAudioStream(
            model.generate(text: text, voice: .conversationalA, qualityLevel: .high, streamingInterval: 0.16),
            extract: { $0.audio }
        )
        try await ensureEngineStarted()
        audioEngine.speak(samplesStream: stream)
    }

    private func ensureEngineStarted() async throws {
        if !configuredAudioEngine {
            try audioEngine.setup()
            configuredAudioEngine = true
            print("Configured audio engine.")
        }
        try audioEngine.start()
        audioEngine.isMicrophoneMuted = false
        print("Started audio engine.")
    }

    private func proxyAudioStream<T>(_ upstream: AsyncThrowingStream<T, any Error>, extract: @escaping (T) -> [Float]) -> AsyncThrowingStream<[Float], any Error> {
        AsyncThrowingStream<[Float], any Error> { continuation in
            let task = Task {
                do {
                    for try await value in upstream {
                        continuation.yield(extract(value))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

// MARK: - AudioEngineDelegate

extension SpeechController: AudioEngineDelegate {
    func audioCaptureEngine(_ engine: AudioEngine, didReceive buffer: AVAudioPCMBuffer) {
        guard !audioEngine.isSpeaking else { return }

        Task {
            vad.process(buffer: buffer)
        }
    }

    func audioCaptureEngine(_ engine: AudioEngine, isSpeakingDidChange speaking: Bool) {
        isSpeaking = speaking
    }
}

// MARK: - SimpleVADDelegate

extension SpeechController: SimpleVADDelegate {
    func vadDidStartSpeaking() {
        isDetectingSpeech = true
    }

    func vadDidStopSpeaking(buffer: AVAudioPCMBuffer?, transcription: String?) {
        if let buffer, let transcription {
            delegate?.speechController(self, didFinish: buffer, transcription: transcription)
        }
        vad.reset()
        isDetectingSpeech = false
    }
}
