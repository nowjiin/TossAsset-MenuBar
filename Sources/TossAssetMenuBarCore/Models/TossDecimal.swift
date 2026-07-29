import Foundation

/// 토스증권 Open API 는 모든 금액·비율을 **문자열 decimal** 로 내려준다 (`"72000"`, `"0.1179"`).
/// 통화 계산에서 `Double` 은 쓸 수 없으므로 디코딩 시점에 `Decimal` 로 고정한다.
public struct TossDecimal: Sendable, Hashable, Codable {
    public let value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "decimal 문자열로 해석할 수 없습니다: \(raw)"
            )
        }
        self.value = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value.description)
    }
}

extension TossDecimal: ExpressibleByStringLiteral {
    /// 테스트 fixture 작성 편의용. 잘못된 리터럴은 개발 중에 즉시 드러나야 하므로 크래시시킨다.
    public init(stringLiteral literal: StringLiteralType) {
        guard let parsed = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX")) else {
            preconditionFailure("잘못된 decimal 리터럴: \(literal)")
        }
        self.value = parsed
    }
}

extension TossDecimal: Comparable {
    public static func < (lhs: TossDecimal, rhs: TossDecimal) -> Bool {
        lhs.value < rhs.value
    }
}

extension TossDecimal {
    public static let zero = TossDecimal(.zero)

    public var isNegative: Bool { value < .zero }
    public var isZero: Bool { value == .zero }
}
