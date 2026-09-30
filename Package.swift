// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tympan",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tympan",
            path: "Sources/Tympan"
        )
    ]
)
