// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "RealtimeAudioRecovery",
  platforms: [.iOS(.v13), .macOS(.v10_15)],
  products: [
    .library(name: "RealtimeAudioRecovery", targets: ["RealtimeAudioRecovery"]),
  ],
  targets: [
    .target(
      name: "RealtimeAudioRecovery",
      path: "darwin/Classes/Recovery"
    ),
    .testTarget(
      name: "RealtimeAudioRecoveryTests",
      dependencies: ["RealtimeAudioRecovery"],
      path: "darwin/Tests"
    ),
  ]
)
