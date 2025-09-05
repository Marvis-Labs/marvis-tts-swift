# Marvis TTS (Swift)

A Swift version of [Marvis TTS](https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.1), running locally on Apple Silicon using [MLX Swift](https://github.com/ml-explore/mlx-swift).

- Streaming generation for realtime playback
- Expressive voice presets
- On-device inference
- Simple API

## Requirements

- **macOS 14+**
- **Xcode 15+** / **Swift 5.10+**

## Installation

### Xcode

In Xcode you can add `https://github.com/Marvis-Labs/marvis-tts-swift.git` as a package
dependency.

### SwiftPM

To use `marvis-tts-swift` with SwiftPM you can add this to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Marvis-Labs/marvis-tts-swift", from: "0.1")
]
```

and add the libraries as dependencies:

```swift
dependencies: [.product(name: "MarvisTTS", package: "marvis-tts-swift")]
```

> [!Note]
> SwiftPM (command line) cannot build the Metal shaders in MLX Swift, so Xcode is required to build.

## Quick Start

```swift
import MarvisTTS

let model = try await MarvisTTS.fromPretrained { progress in /* optionally show download progress */ }
let player = LocalAudioPlayer(sampleRate: model.sampleRate)

// Stream audio for playback as it's generated.
let text = "With Marvis TTS, you can stream audio generated directly on device, fully locally and privately."

for try await result in model.generate(text: text) {
    player.enqueue(samples: $0.audio)
}

player.stop(waitForEnd: true)
```
> [!Note]
> Using a release build or enabling optimizations will signficantly increase generation performance.

## More Info

#### Technical Limitations

- Language Support: Currently only English is supported.
- Hallucinations: The model might hallucinate words, specially for new words or short sentences.

#### Legal and Ethical Considerations

- Users are responsible for complying with local laws regarding voice synthesis and impersonation
- Consider intellectual property rights when cloning voices of public figures
- Respect privacy laws and regulations in your jurisdiction
- Obtain appropriate consent and permissions before deployment

#### License & Agreement

* Apache 2.0
