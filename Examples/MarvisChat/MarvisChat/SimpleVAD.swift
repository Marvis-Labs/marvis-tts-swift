import Accelerate
import AVFoundation
import SoundAnalysis
import Speech

protocol SimpleVADDelegate: AnyObject {
    func vadDidStartSpeaking()
    func vadDidStopSpeaking(buffer: AVAudioPCMBuffer?, transcription: String?)
}

class SimpleVAD {
    weak var delegate: SimpleVADDelegate?
    var hangTime: TimeInterval
    
    private let speechBuffer = SpeechBuffer()
    private let speechBufferTranscriber = SpeechBufferTranscriber()
    private var verifier: SpeechVerifier?
    
    private var lastSpeechTime: TimeInterval?
    private var isListening = false
    
    init(hangTime: TimeInterval = 0.3) {
        self.hangTime = hangTime
        
        Task {
            do {
                let result = try await speechBufferTranscriber.prepare()
                print("On-device transcription preparation result: \(result)")
            } catch {
                print("Unable to prepare on-device transcription: \(error)")
            }
        }
    }
    
    static let baseThreshold: Float = 0.012
    private var postprocessTask: Task<Void, any Error>?
    
    func process(buffer: AVAudioPCMBuffer) {
        guard let micChannelData = buffer.floatChannelData else { return }
        
        let micData = micChannelData[0]
        let micRMS = max(rms(micData, count: Int(buffer.frameLength)), 1e-4)
        
        speechBuffer.append(buffer)
        
        let now = CACurrentMediaTime()
        
        if micRMS > Self.baseThreshold, postprocessTask == nil {
            if !isListening {
                speechBuffer.reset()
                isListening = true
                delegate?.vadDidStartSpeaking()
                print("Did start listening with mic rms: \(micRMS)")
            }
            lastSpeechTime = now
        } else if isListening, let last = lastSpeechTime, now - last > hangTime {
            let buffer = speechBuffer.finalize()
            isListening = false
            lastSpeechTime = nil
            speechBuffer.reset()
            print("Did stop listening with rms: \(micRMS), time since last speech: \(CACurrentMediaTime() - last)")
            
            guard let buffer else {
                delegate?.vadDidStopSpeaking(buffer: nil, transcription: nil)
                return
            }
            
            postprocessTask = Task {
                guard !Task.isCancelled, let verifiedBuffer = await verifiedBuffer(for: buffer) else {
                    delegate?.vadDidStopSpeaking(buffer: nil, transcription: nil)
                    return
                }
                
                guard !Task.isCancelled, let transcription = try await transcription(for: verifiedBuffer) else {
                    delegate?.vadDidStopSpeaking(buffer: nil, transcription: nil)
                    return
                }
                
                delegate?.vadDidStopSpeaking(buffer: verifiedBuffer, transcription: transcription)
                postprocessTask = nil
            }
        }
    }
    
    func reset() {
        lastSpeechTime = nil
        isListening = false
        speechBuffer.reset()
        postprocessTask?.cancel()
        postprocessTask = nil
    }
    
    private func verifiedBuffer(for buffer: AVAudioPCMBuffer) async -> AVAudioPCMBuffer? {
        verifier = try? SpeechVerifier(format: buffer.format)
        
        guard let verifier else {
            print("Error: Unable to create speech verifier.")
            return nil
        }
        
        print("Verifying speech buffer...")
        let startTime = CACurrentMediaTime()
        
        let isSpeech = await withCheckedContinuation { continuation in
            verifier.verify(buffer: buffer) { isSpeech in
                self.verifier = nil
                print("Buffer is speech: \(isSpeech) -- time taken: \(CACurrentMediaTime() - startTime)s")
                continuation.resume(returning: isSpeech)
            }
        }
        return isSpeech ? buffer : nil
    }
    
    private func transcription(for buffer: AVAudioPCMBuffer) async throws -> String? {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let audioURL = cacheDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try AVAudioFile(forWriting: audioURL, settings: buffer.format.settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved).write(from: buffer)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        let start = CACurrentMediaTime()
        let audioFile = try AVAudioFile(forReading: audioURL, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
        let message = try await speechBufferTranscriber.transcribe(from: audioFile)
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Transcription completed in \(CACurrentMediaTime() - start): \(message)")
            return message
        }
        return nil
    }
}

// MARK: -

class SpeechBuffer {
    private var chunks: [AVAudioPCMBuffer] = []
    
    func append(_ buffer: AVAudioPCMBuffer) {
        chunks.append(buffer)
    }
    
    func finalize() -> AVAudioPCMBuffer? {
        guard let first = chunks.first else { return nil }
        let fmt = first.format
        let totalFrames = chunks.reduce(0) { $0 + Int($1.frameLength) }
        guard let out = AVAudioPCMBuffer(
            pcmFormat: fmt,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else { return nil }
        out.frameLength = AVAudioFrameCount(totalFrames)
        
        var offset: AVAudioFrameCount = 0
        for buf in chunks {
            let len = buf.frameLength
            for ch in 0 ..< Int(fmt.channelCount) {
                let dst = out.floatChannelData![ch] + Int(offset)
                let src = buf.floatChannelData![ch]
                memcpy(dst, src, Int(len) * MemoryLayout<Float>.size)
            }
            offset += len
        }
        
        return out
    }
    
    func reset() {
        chunks.removeAll()
    }
}

// MARK: -

class SpeechBufferTranscriber {
    enum SpeechBufferTranscriberError: Error {
        case localeNotSupported
        case assetsNotInstalled
    }

    func prepare() async throws -> Bool {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            print("Warning: Current locale (\(Locale.current)) is not supported for transcription.")
            throw SpeechBufferTranscriberError.localeNotSupported
        }
        
        // Installed required assets as needed.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
            return true
        }
        return false
    }
    
    func transcribe(from audioFile: AVAudioFile) async throws -> String? {
        let transcriber = SpeechTranscriber(locale: Locale.current, preset: .transcription)
        
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechBufferTranscriberError.assetsNotInstalled
        }
        
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        if let _ = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } else {
            await analyzer.cancelAndFinishNow()
        }
        
        var transcription = ""
        for try await result in transcriber.results {
            transcription += String(result.text.characters)
        }
        return transcription
    }
}

// MARK: -

class SpeechVerifier: NSObject {
    private let analyzer: SNAudioStreamAnalyzer
    private let request: SNClassifySoundRequest
    private let confidenceThreshold: Double
    private let analysisQueue = DispatchQueue(label: "analysisQueue")
    
    private var detectedSpeech = false
    private var completion: ((Bool) -> Void)?
    
    init(format: AVAudioFormat, confidenceThreshold: Double = 0.3) throws {
        self.confidenceThreshold = confidenceThreshold
        analyzer = SNAudioStreamAnalyzer(format: format)
        request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(value: 16000, timescale: 16000)
        super.init()
        try analyzer.add(request, withObserver: self)
    }
    
    func verify(buffer: AVAudioPCMBuffer, completion: @escaping (Bool) -> Void) {
        analysisQueue.async {
            self.completion = completion
            self.detectedSpeech = false
            self.analyzer.analyze(buffer, atAudioFramePosition: 0)
            self.analyzer.completeAnalysis()
        }
    }
}

extension SpeechVerifier: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        analysisQueue.async {
            guard let classificationResult = result as? SNClassificationResult,
                  let classification = classificationResult.classifications.first(where: { $0.identifier == "speech" }) else {
                return
            }
            self.detectedSpeech = self.detectedSpeech || (classification.confidence >= self.confidenceThreshold)
        }
    }
    
    func requestDidComplete(_ request: SNRequest) {
        analysisQueue.async {
            if let completion = self.completion {
                self.completion = nil
                
                if self.detectedSpeech {
                    Task { @MainActor in completion(true) }
                } else {
                    Task { @MainActor in completion(false) }
                }
            }
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        analysisQueue.async {
            if let completion = self.completion {
                self.completion = nil
                
                Task { @MainActor in completion(false) }
            }
        }
    }
}

// MARK: - Accelerate Helpers

@inline(__always)
private func rms(_ ptr: UnsafePointer<Float>, count: Int) -> Float {
    var meanSq: Float = 0
    vDSP_measqv(ptr, 1, &meanSq, vDSP_Length(count))
    return sqrt(meanSq)
}

@inline(__always)
private func rms(_ vec: [Float]) -> Float {
    vec.withUnsafeBufferPointer { buf -> Float in
        guard let base = buf.baseAddress else { return 0 }
        return rms(base, count: vec.count)
    }
}
