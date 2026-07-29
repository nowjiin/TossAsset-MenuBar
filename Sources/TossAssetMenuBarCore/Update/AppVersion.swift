import Foundation

/// `0.1.0` 형태의 semver. 릴리스 태그(`v0.2.0`)와 `CFBundleShortVersionString` 을 같은 잣대로 비교한다.
///
/// 문자열 비교로는 안 된다: `"0.10.0" < "0.9.0"` 이 되어 버린다.
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `v0.2.0`, `0.2.0`, `0.2` 를 모두 받는다. 그 밖의 형식은 nil.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        // `0.2.0-beta.1` 같은 pre-release 표기는 앞부분만 본다.
        if let dash = text.firstIndex(of: "-") {
            text = String(text[text.startIndex..<dash])
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        self.major = numbers[0]
        self.minor = numbers.count > 1 ? numbers[1] : 0
        self.patch = numbers.count > 2 ? numbers[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
