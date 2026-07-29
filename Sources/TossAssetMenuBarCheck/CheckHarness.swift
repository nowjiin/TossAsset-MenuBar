import Foundation

/// XCTest 와 swift-testing 매크로 플러그인은 Xcode.app 안에만 있어서 Command Line Tools 환경에서는
/// 쓸 수 없다. 그래서 검증을 일반 실행 파일로 만들었다. `swift run TossAssetMenuBarCheck` 로 돌아간다.
///
/// Xcode 를 설치하면 이 파일들을 그대로 테스트 타깃으로 옮길 수 있다.
actor CheckHarness {
    private var passed = 0
    private var failures: [String] = []
    private var currentGroup = ""

    func group(_ name: String) {
        currentGroup = name
        print("\n▸ \(name)")
    }

    func expect(_ condition: Bool, _ label: String) {
        if condition {
            passed += 1
            print("  ✓ \(label)")
        } else {
            failures.append("[\(currentGroup)] \(label)")
            print("  ✗ \(label)")
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        if actual == expected {
            passed += 1
            print("  ✓ \(label)")
        } else {
            failures.append("[\(currentGroup)] \(label) — 기대 \(expected), 실제 \(actual)")
            print("  ✗ \(label) — 기대 \(expected), 실제 \(actual)")
        }
    }

    /// 던지길 기대하는 코드. 던지지 않으면 실패로 기록한다.
    func expectThrows<T>(_ label: String, _ body: () async throws -> T) async {
        do {
            _ = try await body()
            failures.append("[\(currentGroup)] \(label) — 오류가 발생해야 하는데 성공했습니다")
            print("  ✗ \(label) — 오류가 발생해야 하는데 성공했습니다")
        } catch {
            passed += 1
            print("  ✓ \(label) (\(error))")
        }
    }

    /// 특정 오류가 나오길 기대한다.
    func expectError<T>(_ expected: TossAPIErrorMatcher, _ label: String, _ body: () async throws -> T) async {
        do {
            _ = try await body()
            failures.append("[\(currentGroup)] \(label) — 오류가 발생해야 하는데 성공했습니다")
            print("  ✗ \(label) — 오류가 발생해야 하는데 성공했습니다")
        } catch {
            if expected.matches(error) {
                passed += 1
                print("  ✓ \(label)")
            } else {
                failures.append("[\(currentGroup)] \(label) — 예상과 다른 오류: \(error)")
                print("  ✗ \(label) — 예상과 다른 오류: \(error)")
            }
        }
    }

    /// 종료 코드를 결정한다. 실패가 있으면 0 이 아닌 값을 돌려준다.
    func summary() -> Int32 {
        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("통과 \(passed)건, 실패 0건")
            return 0
        }
        print("통과 \(passed)건, 실패 \(failures.count)건")
        for failure in failures {
            print("  · \(failure)")
        }
        return 1
    }
}
