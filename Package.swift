// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuizKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        // ロジックのテストを `swift test` で手元の Mac でも回せるようにする
        .macOS(.v14)
    ],
    products: [
        // 出題・進行・スコア・記録・デイリー。UI に依存しない
        .library(name: "QuizCore", targets: ["QuizCore"]),
        // テーマと標準画面。レイアウトを丸ごと変えたいアプリは使わなくてよい
        .library(name: "QuizUI", targets: ["QuizUI"]),
        // Game Center のリーダーボード
        .library(name: "QuizGameCenter", targets: ["QuizGameCenter"])
    ],
    targets: [
        .target(name: "QuizCore"),
        .target(name: "QuizUI", dependencies: ["QuizCore"], resources: [.process("Resources")]),
        .target(name: "QuizGameCenter"),
        .testTarget(name: "QuizCoreTests", dependencies: ["QuizCore"]),
        .testTarget(name: "QuizUITests", dependencies: ["QuizUI"])
    ]
)
