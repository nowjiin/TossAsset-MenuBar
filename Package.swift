// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TossAssetMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 로직. UI 프레임워크에 의존하지 않으므로 검증 러너에서 그대로 쓸 수 있다.
        .target(
            name: "TossAssetMenuBarCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // 메뉴바 앱 본체.
        .executableTarget(
            name: "TossAssetMenuBar",
            dependencies: ["TossAssetMenuBarCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // XCTest / swift-testing 은 Xcode.app 에만 포함되어 있어 Command Line Tools 환경에서는
        // 쓸 수 없다. 대신 자체 assert 러너를 executable 로 두어 `swift run TossAssetMenuBarCheck`
        // 한 줄로 검증이 돌아가게 한다.
        .executableTarget(
            name: "TossAssetMenuBarCheck",
            dependencies: ["TossAssetMenuBarCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
