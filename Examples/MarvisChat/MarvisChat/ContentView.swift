import AVFoundation
import FoundationModels
import SwiftUI

@Observable
class ContentViewModel {
    var speechController = SpeechController()
    
    private static let instructions = "You are a helpful voice assistant that answers the user's questions with very consise and natural full sentences, as it will be TTS-rendered downstream as speech. You always answer in two sentences or less. You NEVER use lists, emojis, markdown, or other non-essential embellishments."
    
    @ObservationIgnored
    private var session: LanguageModelSession?
    
    init() {
        speechController.delegate = self
    }
    
    func startConversation() async throws {
        print("Starting conversation...")
        
        session = LanguageModelSession(instructions: Self.instructions)
        
        try await speechController.start()
        
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    
    func stopConversation() async throws {
        try await speechController.stop()
        
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
        
        print("Stopped conversation.")
    }
}

extension ContentViewModel: SpeechControllerDelegate {
    func speechController(_ controller: SpeechController, didFinish buffer: AVAudioPCMBuffer, transcription: String) {
        Task {
            guard !controller.isSpeaking else { return }
            
            let response = try await self.session?.respond(to: transcription)
            try await self.speechController.speak(text: response?.content ?? "I'm sorry, I didn't get that.")
        }
    }
}

struct ContentView: View {
    @State private var permissionStatus: AVAudioApplication.recordPermission = .undetermined
    @State private var viewModel = ContentViewModel()
    
    var body: some View {
        VStack {
            Spacer()
            
            assistantCircle
            
            Spacer()
            
            micButton
        }
        .padding()
        .background(Color.black.opacity(0.01))
        .preferredColorScheme(.light)
        .onChange(of: viewModel.speechController.canSpeak) { _, newValue in
            if newValue {
                Task {
                    if !viewModel.speechController.isActive {
                        try await viewModel.startConversation()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var assistantCircle: some View {
        let isActive = viewModel.speechController.isActive
        let isSpeaking = viewModel.speechController.isSpeaking
        let isDetectingSpeech = viewModel.speechController.isDetectingSpeech
        
        ZStack {
            Circle()
                .fill(.clear)
                .frame(maxWidth: .infinity)
                .background {
                    if !isActive {
                        RadialGradient(colors: [.black.opacity(0.4), .black.opacity(0.3)], center: .topLeading, startRadius: 0, endRadius: 300)
                    } else if isDetectingSpeech {
                        RadialGradient(colors: [.black.opacity(0.5), .black], center: .topLeading, startRadius: 0, endRadius: 300)
                    } else {
                        RadialGradient(colors: isSpeaking ? [.red, .purple.opacity(0.9)] : [.black, .black], center: .topLeading, startRadius: 0, endRadius: 300)
                    }
                }
                .clipShape(Circle())
                .padding(64)
        }
        .scaleEffect(CGSize(width: isActive ? 1.0 : 0.7, height: isActive ? 1.0 : 0.7))
        .animation(.easeOut(duration: 0.2), value: viewModel.speechController.isActive)
        .animation(.easeOut(duration: 0.4), value: viewModel.speechController.isSpeaking)
        .animation(.easeOut(duration: 0.4), value: viewModel.speechController.isDetectingSpeech)
    }
    
    @ViewBuilder
    private var micButton: some View {
        let isActive = viewModel.speechController.isActive
        
        Button {
            if viewModel.speechController.canSpeak {
                Task {
                    if permissionStatus == .undetermined {
                        let granted = await AVAudioApplication.requestRecordPermission()
                        withAnimation {
                            permissionStatus = granted ? .granted : .denied
                        }
                    }
                    
                    try await toggleConversation()
                }
            }
        } label: {
            if !viewModel.speechController.canSpeak {
                Image(systemName: "ellipsis")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white)
                    .padding(24)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
                    .compositingGroup()
                    .blendMode(.multiply)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous))
            } else {
                Image(systemName: isActive ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white)
                    .padding(24)
                    .background(Color.orange.opacity(isActive ? 0.8 : 0.5))
                    .clipShape(Circle())
                    .compositingGroup()
                    .blendMode(.multiply)
            }
        }
    }
    
    private func toggleConversation() async throws {
        do {
            if !viewModel.speechController.isActive {
                try await viewModel.startConversation()
            } else {
                try await viewModel.stopConversation()
            }
        } catch {
            print("Failed to start conversation: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
