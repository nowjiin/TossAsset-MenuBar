import Foundation

/// 문서가 "클라이언트는 unknown enum 값을 허용하도록 구현해야 합니다" 를 명시적으로 요구한다.
/// 따라서 모든 서버 enum 은 알 수 없는 값을 `.unknown(String)` 으로 흡수해 디코딩이 깨지지 않게 한다.
public protocol OpenEnum: RawRepresentable, Codable, Sendable, Hashable where RawValue == String {
    static func unknown(_ raw: String) -> Self
}

extension OpenEnum {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknown(raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum Currency: OpenEnum {
    case krw
    case usd
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "KRW": self = .krw
        case "USD": self = .usd
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .krw: "KRW"
        case .usd: "USD"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> Currency { .other(raw) }
}

public enum MarketCountry: OpenEnum {
    case kr
    case us
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "KR": self = .kr
        case "US": self = .us
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .kr: "KR"
        case .us: "US"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> MarketCountry { .other(raw) }
}

public enum AccountType: OpenEnum {
    case brokerage
    case overseasDerivatives
    case pensionSavings
    case reshoringInvestment
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "BROKERAGE": self = .brokerage
        case "OVERSEAS_DERIVATIVES": self = .overseasDerivatives
        case "PENSION_SAVINGS": self = .pensionSavings
        case "RESHORING_INVESTMENT": self = .reshoringInvestment
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .brokerage: "BROKERAGE"
        case .overseasDerivatives: "OVERSEAS_DERIVATIVES"
        case .pensionSavings: "PENSION_SAVINGS"
        case .reshoringInvestment: "RESHORING_INVESTMENT"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> AccountType { .other(raw) }
}

public enum StockMarket: OpenEnum {
    case kospi, kosdaq, nyse, nasdaq, amex, krEtc, usEtc
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "KOSPI": self = .kospi
        case "KOSDAQ": self = .kosdaq
        case "NYSE": self = .nyse
        case "NASDAQ": self = .nasdaq
        case "AMEX": self = .amex
        case "KR_ETC": self = .krEtc
        case "US_ETC": self = .usEtc
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .kospi: "KOSPI"
        case .kosdaq: "KOSDAQ"
        case .nyse: "NYSE"
        case .nasdaq: "NASDAQ"
        case .amex: "AMEX"
        case .krEtc: "KR_ETC"
        case .usEtc: "US_ETC"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> StockMarket { .other(raw) }

    public var country: MarketCountry {
        switch self {
        case .kospi, .kosdaq, .krEtc: .kr
        case .nyse, .nasdaq, .amex, .usEtc: .us
        case .other: .other("")
        }
    }
}

public enum ListingStatus: OpenEnum {
    case scheduled, active, delisted
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "SCHEDULED": self = .scheduled
        case "ACTIVE": self = .active
        case "DELISTED": self = .delisted
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .scheduled: "SCHEDULED"
        case .active: "ACTIVE"
        case .delisted: "DELISTED"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> ListingStatus { .other(raw) }
}
