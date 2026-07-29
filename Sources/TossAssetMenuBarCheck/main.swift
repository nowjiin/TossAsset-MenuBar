import Foundation
import TossAssetMenuBarCore

// XCTest 와 swift-testing 매크로 플러그인은 Xcode.app 안에만 있어서 Command Line Tools 환경에서는
// 쓸 수 없다. 그래서 검증을 일반 실행 파일로 만들었다: `swift run TossAssetMenuBarCheck`
//
// 검증 내용은 Checks/ 아래에 영역별로 나뉘어 있다.
let check = CheckHarness()

try await runModelChecks(check)
try await runFormattingChecks(check)
try await runNetworkingChecks(check)
try await runDomainChecks(check)
try await runUpdateChecks(check)

exit(await check.summary())
