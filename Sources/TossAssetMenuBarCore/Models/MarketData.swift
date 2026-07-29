import Foundation

/// `GET /api/v1/prices?symbols=` 의 항목.
public struct StockPrice: Decodable, Sendable, Identifiable, Hashable {
    public let symbol: String
    /// 체결이 없으면 nil.
    public let timestamp: Date?
    public let lastPrice: TossDecimal
    public let currency: Currency

    public var id: String { symbol }

    public init(symbol: String, timestamp: Date?, lastPrice: TossDecimal, currency: Currency) {
        self.symbol = symbol
        self.timestamp = timestamp
        self.lastPrice = lastPrice
        self.currency = currency
    }
}

/// `GET /api/v1/stocks?symbols=` 의 항목. 관심종목 심볼 검증과 종목명 표시에 쓴다.
public struct StockInfo: Decodable, Sendable, Identifiable, Hashable {
    public let symbol: String
    public let name: String
    public let englishName: String
    public let market: StockMarket
    public let status: ListingStatus
    public let currency: Currency

    public var id: String { symbol }

    public init(
        symbol: String,
        name: String,
        englishName: String,
        market: StockMarket,
        status: ListingStatus,
        currency: Currency
    ) {
        self.symbol = symbol
        self.name = name
        self.englishName = englishName
        self.market = market
        self.status = status
        self.currency = currency
    }

    /// 한글명이 비어 있는 해외 종목은 영문명으로 대체한다.
    public var displayName: String {
        name.isEmpty ? englishName : name
    }
}

/// `GET /api/v1/exchange-rate` 응답. `validUntil` 까지 캐시할 수 있다.
public struct ExchangeRate: Decodable, Sendable {
    public let baseCurrency: Currency
    public let quoteCurrency: Currency
    public let rate: TossDecimal
    public let midRate: TossDecimal
    public let validFrom: Date
    public let validUntil: Date

    public init(
        baseCurrency: Currency,
        quoteCurrency: Currency,
        rate: TossDecimal,
        midRate: TossDecimal,
        validFrom: Date,
        validUntil: Date
    ) {
        self.baseCurrency = baseCurrency
        self.quoteCurrency = quoteCurrency
        self.rate = rate
        self.midRate = midRate
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}
