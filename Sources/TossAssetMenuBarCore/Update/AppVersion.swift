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

/// 설정 탭에 보여줄 버전 문구.
///
/// 번들에는 값이 두 개 있다.
///   `CFBundleShortVersionString` — 비교용. 릴리스 태그와 같은 형태(`0.3.0`)여야
///                                  `AppVersion` 이 파싱해 업데이트 여부를 판단한다.
///   `CFBundleVersion`            — 빌드 식별용. 로컬 빌드는 `0.3.0+3` 처럼 태그 이후 커밋 수가
///                                  붙고, 작업 트리가 더러우면 `.dirty` 가 더 붙는다.
///
/// 릴리스 빌드는 `package-release.sh` 가 두 값을 같게 맞춘다. 그래서 **둘이 다르면 로컬 빌드**다.
public enum BuildLabel {
    /// 로컬 빌드 표식. 릴리스 빌드면 `nil`.
    public static func localSuffix(shortVersion: String?, bundleVersion: String?) -> String? {
        guard
            let bundleVersion = bundleVersion?.trimmingCharacters(in: .whitespaces),
            !bundleVersion.isEmpty
        else { return nil }
        let short = shortVersion?.trimmingCharacters(in: .whitespaces) ?? ""
        guard bundleVersion != short else { return nil }
        // `0.3.0+3.dirty` 에서 `+3.dirty` 만 남긴다. 접두가 다르면 값 전체를 보여준다.
        guard bundleVersion.hasPrefix(short), !short.isEmpty else { return bundleVersion }
        return String(bundleVersion.dropFirst(short.count))
    }

    /// 표시 문구. 릴리스면 `0.3.0`, 로컬 빌드면 `0.3.0 +3` 처럼 표식을 덧붙인다.
    ///
    /// 로컬 빌드임을 드러내는 이유는, 릴리스본과 같은 버전으로 보이면 "고쳤는데 왜 그대로지" 를
    /// 판단할 수 없기 때문이다.
    public static func display(shortVersion: String?, bundleVersion: String?) -> String {
        let version = AppVersion(shortVersion ?? "")?.description ?? "0.0.0"
        guard let suffix = localSuffix(shortVersion: shortVersion, bundleVersion: bundleVersion) else {
            return version
        }
        return "\(version) \(suffix)"
    }
}
