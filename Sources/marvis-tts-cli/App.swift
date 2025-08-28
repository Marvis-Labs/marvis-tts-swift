import Foundation
import MarvisTTS

@main
enum App {
    static func main() async {
        do {
            let args = try CLI.parse()
            try await run(
                text: args.text,
                voice: args.voice,
                repoId: args.repoId
            )
        } catch {
            fputs("Error: \(error)\n", stderr)
            CLI.printUsage()
            exit(1)
        }
    }

    private static func run(
        text: String,
        voice: MarvisTTS.Voice?,
        repoId: String
    ) async throws {
        print("Loading model (\(repoId))…")

        let model = try await MarvisTTS.fromPretrained(repoId: repoId) { progress in
            let pct = Int((progress.fractionCompleted * 100).rounded())
            if pct % 10 == 0 {
                print("Download progress: \(pct)%")
            }
        }

        let player = LocalAudioPlayer(sampleRate: model.sampleRate)

        print("Generating…")
        let started = CFAbsoluteTimeGetCurrent()

        try model.generate(
            text: text,
            voice: voice ?? .conversationalA,
            stream: true,
            onStreamingResult: { result in
                player.enqueue(samples: result.audio)
            }
        )
        player.stop(waitForEnd: true)

        let elapsed = CFAbsoluteTimeGetCurrent() - started
        print(String(format: "Done. Elapsed: %.2fs", elapsed))
    }
}

// MARK: - Minimal CLI parser

enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownOption(String)

    var description: String {
        switch self {
        case .missingValue(let k): "Missing value for \(k)"
        case .unknownOption(let k): "Unknown option \(k)"
        }
    }
}

struct CLI {
    let text: String
    let voice: MarvisTTS.Voice?
    let repoId: String

    static func parse() throws -> CLI {
        var text: String?
        var voice: MarvisTTS.Voice? = nil
        var repoId = "Marvis-AI/marvis-tts-250m-v0.1"

        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--text", "-t":
                guard let v = it.next() else { throw CLIError.missingValue(arg) }
                text = v
            case "--voice", "-v":
                guard let v = it.next() else { throw CLIError.missingValue(arg) }
                voice = MarvisTTS.Voice(rawValue: v) ?? {
                    switch v.lowercased() {
                    case "a", "conversational_a": .conversationalA
                    case "b", "conversational_b": .conversationalB
                    default: nil
                    }
                }()
            case "--repo", "--repo-id":
                guard let v = it.next() else { throw CLIError.missingValue(arg) }
                repoId = v
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                // allow bare text as the final arg
                if text == nil, !arg.hasPrefix("-") {
                    text = arg
                } else {
                    throw CLIError.unknownOption(arg)
                }
            }
        }

        guard let finalText = text, !finalText.isEmpty else {
            throw CLIError.missingValue("--text")
        }

        return CLI(text: finalText, voice: voice, repoId: repoId)
    }

    static func printUsage() {
        let exe = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "marvis-tts-cli"
        print("""
        Usage:
          \(exe) --text "Hello world" [--voice conversational_b] [--repo-id <hf-repo>]

        Options:
          -t, --text <string>           Text to synthesize (required if not passed as trailing arg)
          -v, --voice <name>            Voice id (conversational_a | conversational_b). Default: conversational_b
              --repo-id <repo>          HF repo id. Default: Marvis-AI/marvis-tts-250m-v0.1
          -h, --help                    Show this help

        Examples:
          \(exe) -t "Streaming, fully on-device." -v conversational_b
        """)
    }
}
