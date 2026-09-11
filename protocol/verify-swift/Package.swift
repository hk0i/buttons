// swift-tools-version:5.9
import PackageDescription

// Codegen + round-trip prototype only — see
// docs/slices/06. Protobuf Codegen Prototype.spec.md. Not depended on by
// /ios. SwiftProtobuf pinned to exactly what `protoc-gen-swift --version`
// reported at generation time (Implementation Notes item 1) — don't bump
// without regenerating buttons.pb.swift to match.
let package = Package(
    name: "ButtonsProto",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ButtonsProto", targets: ["ButtonsProto"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1")
    ],
    targets: [
        .target(
            name: "ButtonsProto",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .testTarget(
            name: "ButtonsProtoTests",
            dependencies: ["ButtonsProto"]
        ),
    ]
)
