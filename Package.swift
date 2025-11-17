// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MarvisTTS",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MarvisTTS", targets: ["MarvisTTS"]),
        .executable(
            name: "marvis-tts-cli",
            targets: ["marvis-tts-cli"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMajor(from: "1.1.2")),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.29.1")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "2.29.2")),
    ],
    targets: [
        .target(name: "MarvisTTS",
                dependencies: [
                    .product(name: "MLX", package: "mlx-swift"),
                    .product(name: "MLXNN", package: "mlx-swift"),
                    .product(name: "MLXRandom", package: "mlx-swift"),
                    .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                    .product(name: "MLXLLM", package: "mlx-swift-lm"),
                    .product(name: "Transformers", package: "swift-transformers"),
                ],
                path: "Sources/MarvisTTS"),
        .executableTarget(
            name: "marvis-tts-cli",
            dependencies: ["MarvisTTS"],
            path: "Sources/marvis-tts-cli"
        ),
    ]
)
