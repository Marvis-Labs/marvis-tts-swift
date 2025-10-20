# Marvis Chat

Marvis Chat is a minimal example app running on iOS 26+ that implements a local voice assistant pipeline. It uses Marvis TTS for text-to-speech, and Apple's Foundation Models for speech-to-text & text generation.

## Requirements

- **iOS 26+**
- **Xcode 26+** / **Swift 5.10+**

## Quick Start

Open the `MarvisChat.xcodeproj` Xcode project and build & run the app targeting an iOS device. Note that Marvis Chat uses MLX, which is not currently available in the iOS simulator.

You can adjust the voice used, audio quality, and initial streaming latency using the Swift-based Marvis TTS API:

```swift
model.generate(
    text: text,
    voice: .conversationalA,
    qualityLevel: .high,
    streamingInterval: 0.16
)
```

> [!Note]
> Using a release build or enabling optimizations will signficantly increase speech generation performance.

#### License & Agreement

* Apache 2.0
