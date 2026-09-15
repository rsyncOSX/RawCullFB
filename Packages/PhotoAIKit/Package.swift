// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "PhotoAIKit",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "PhotoAIContracts", targets: ["PhotoAIContracts"]),
        .library(name: "CoreAICLIPBackend", targets: ["CoreAICLIPBackend"]),
        .library(name: "CoreAIEfficientSAMBackend", targets: ["CoreAIEfficientSAMBackend"]),
        .library(name: "CoreAISAM3Backend", targets: ["CoreAISAM3Backend"]),
        .library(name: "CoreAIQwenBackend", targets: ["CoreAIQwenBackend"]),
        .library(name: "VisionFeaturePrintBackend", targets: ["VisionFeaturePrintBackend"]),
        .library(name: "PhotoAIWorkflows", targets: ["PhotoAIWorkflows"]),
        .library(name: "PhotoAIStorage", targets: ["PhotoAIStorage"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/coreai-models.git",
            revision: "7359dbcf6c3babb4fbfadfd015ffcc1cb6d87420"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            from: "1.3.3"
        )
    ],
    targets: [
        .target(name: "PhotoAIContracts"),
        .target(
            name: "CoreAICLIPBackend",
            dependencies: [
                "PhotoAIContracts",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .target(
            name: "CoreAIEfficientSAMBackend",
            dependencies: [
                "PhotoAIContracts",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
            ]
        ),
        .target(
            name: "CoreAISAM3Backend",
            dependencies: [
                "PhotoAIContracts",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
            ]
        ),
        .target(
            name: "CoreAIQwenBackend",
            dependencies: [
                "PhotoAIContracts",
                .product(name: "CoreAILM", package: "coreai-models"),
            ]
        ),
        .target(
            name: "VisionFeaturePrintBackend",
            dependencies: ["PhotoAIContracts"]
        ),
        .target(
            name: "PhotoAIWorkflows",
            dependencies: ["PhotoAIContracts"]
        ),
        .target(
            name: "PhotoAIStorage",
            dependencies: ["PhotoAIContracts"]
        ),
        .testTarget(
            name: "PhotoAIKitTests",
            dependencies: [
                "PhotoAIContracts",
                "PhotoAIWorkflows",
                "PhotoAIStorage",
                "CoreAICLIPBackend",
                "CoreAIEfficientSAMBackend",
                "CoreAISAM3Backend",
                "CoreAIQwenBackend",
                "VisionFeaturePrintBackend",
                .product(name: "CoreAISegmentation", package: "coreai-models"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
