// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KhVolume",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KhVolume", targets: ["KhVolume"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "KhVolume",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/KhVolume",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
