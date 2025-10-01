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
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.25.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", .upToNextMajor(from: "2.25.8")),
    ],
    targets: [
        .target(name: "MarvisTTS",
                dependencies: [
                    .product(name: "MLX", package: "mlx-swift"),
                    .product(name: "MLXNN", package: "mlx-swift"),
                    .product(name: "MLXRandom", package: "mlx-swift"),
                    .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                    .product(name: "MLXLLM", package: "mlx-swift-examples"),
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
