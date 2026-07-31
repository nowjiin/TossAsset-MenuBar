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

/// `GET /api/v1/candles` 의 일봉 한 개.
///
/// 이 앱은 차트를 그리지 않는다. **전일 종가**만 알면 되므로 종가와 시각만 쓴다.
public struct Candle: Decodable, Sendable, Hashable {
    public let timestamp: Date
    public let closePrice: TossDecimal

    public init(timestamp: Date, closePrice: TossDecimal) {
        self.timestamp = timestamp
        self.closePrice = closePrice
    }
}

public struct CandleResponse: Decodable, Sendable, Hashable {
    public let candles: [Candle]

    public init(candles: [Candle]) {
        self.candles = candles
    }
}

/// 종목 자체의 등락률.
///
/// 보유 종목의 `dailyProfitLoss` 는 **내 포지션의 손익률**이다. 오늘 산 종목이면 매수가가
/// 기준이 되어 종목이 실제로 얼마나 올랐는지와 다른 값이 나온다. 종목의 등락률을 보려면
/// 전일 종가가 필요한데, 토스 API 에서 임의 종목의 기준가를 주는 곳은 일봉뿐이다
/// (`basePrice` 는 `/rankings` 에만 있고 상위 종목만 나온다).
public enum DailyChange {
    /// 일봉 목록에서 기준가(직전 거래일 종가)를 고른다.
    ///
    /// **두 번째로 최신인 봉**을 쓴다. 장중이면 최신 봉이 오늘이라 그 앞이 어제 종가이고,
    /// 폐장이면 최신 봉이 마지막 거래일이라 그 앞이 그 전날 종가다 — 두 경우 모두 맞다.
    ///
    /// 응답 정렬 순서가 문서에 없으므로 시각으로 직접 정렬한다.
    public static func basePrice(from candles: [Candle]) -> TossDecimal? {
        let sorted = candles.sorted { $0.timestamp > $1.timestamp }
        guard sorted.count >= 2 else { return nil }
        return sorted[1].closePrice
    }

    /// `(현재가 - 기준가) / 기준가`. 기준가가 0 이면 나눌 수 없으므로 `nil`.
    public static func rate(lastPrice: TossDecimal, basePrice: TossDecimal?) -> TossDecimal? {
        guard let basePrice, !basePrice.isZero else { return nil }
        return TossDecimal((lastPrice.value - basePrice.value) / basePrice.value)
    }
}
