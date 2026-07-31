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

/// `GET /api/v1/price-limits` 응답. 국내 종목만 값이 있고 해외는 `null` 이다.
public struct PriceLimits: Decodable, Sendable, Hashable {
    public let upperLimitPrice: TossDecimal?
    public let lowerLimitPrice: TossDecimal?
    public let currency: Currency

    public init(upperLimitPrice: TossDecimal?, lowerLimitPrice: TossDecimal?, currency: Currency) {
        self.upperLimitPrice = upperLimitPrice
        self.lowerLimitPrice = lowerLimitPrice
        self.currency = currency
    }
}

/// 종목 자체의 등락률.
///
/// 보유 종목의 `dailyProfitLoss` 는 **내 포지션의 손익률**이다. 오늘 산 종목이면 매수가가
/// 기준이 되어 종목이 실제로 얼마나 올랐는지와 다른 값이 나온다. 종목의 등락률을 보려면
/// 전일 종가가 필요한데, 토스 API 에서 임의 종목의 기준가를 주는 곳은 일봉뿐이다
/// (`basePrice` 는 `/rankings` 에만 있고 상위 종목만 나온다).
public enum DailyChange {
    /// 일봉 목록에서 기준가(현재가가 속한 세션의 **직전 거래일 종가**)를 고른다.
    ///
    /// 두 번 틀린 자리다. 남겨 둔다.
    ///
    /// 1. **"두 번째로 최신인 봉"** — 장중에 오늘 일봉이 응답에 없으면 최신 봉이 어제가 되고
    ///    기준가로 그제가 잡힌다. 상한가 종목이 +30% 대신 `+26.42%` 로 보였다 (어제 -2.75%).
    /// 2. **"지금 장이 열려 있는가"** — 폐장 직후에도 현재가는 오늘 종가인데 닫혔다고 보고
    ///    그제를 기준으로 삼았다. 그래서 15:30 이후에도 여전히 `+26.42%` 였다.
    ///
    /// 옳은 기준은 **오늘 장이 시작됐는가**다. 개장 여부가 아니다.
    ///
    /// | 오늘 장 | 기준가 |
    /// |---|---|
    /// | 시작됐다 (장중·폐장 후) | 오늘보다 앞선 가장 최근 봉 — 오늘 봉이 있든 없든 같은 답이다 |
    /// | 시작 안 됐다 (개장 전·휴장일·주말) | 두 번째 봉 — 현재가가 곧 최신 봉의 종가다 |
    ///
    /// 날짜 비교는 **그 종목 시장의 타임존** 기준이어야 한다. 미국 종목을 KST 로 따지면
    /// 자정을 넘긴 정규장에서 날짜가 하루 밀린다.
    public static func basePrice(
        from candles: [Candle],
        now: Date = Date(),
        zone: MarketTimeZone,
        hasSessionStartedToday: Bool
    ) -> TossDecimal? {
        let sorted = candles.sorted { $0.timestamp > $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone.timeZone

        if hasSessionStartedToday {
            return sorted
                .first { !calendar.isDate($0.timestamp, inSameDayAs: now) }?
                .closePrice
        }
        guard sorted.count >= 2 else { return nil }
        return sorted[1].closePrice
    }

    /// 상/하한가에서 기준가를 역산한다. **국내 종목에는 이 방법을 쓴다.**
    ///
    /// 국내는 상·하한가가 기준가의 ±30% 로 정해지므로 중간값이 곧 기준가다.
    /// 문서 예시로 검산된다 — 상한가 93,000 + 하한가 50,400 → 71,700, 그리고
    /// 71,700 × 1.3 = 93,210 이 호가 단위로 93,000 이 된다.
    ///
    /// 일봉으로 구하지 않는 이유는 실측 때문이다. 어떤 국내 종목은 일봉의 직전 종가가
    /// 실제 기준가와 달랐다 — 상한가 종목이 토스 앱의 +29.9% 대신 +24.06% 로 계산됐다.
    /// 상/하한가는 같은 시세 피드에서 오고 날짜 경계·수정주가 해석이 개입하지 않는다.
    ///
    /// 해외 종목은 상/하한가가 없어(`null`) 여기서 `nil` 이 나온다. 그때는 일봉을 쓴다.
    public static func basePrice(from limits: PriceLimits) -> TossDecimal? {
        guard let upper = limits.upperLimitPrice, let lower = limits.lowerLimitPrice else {
            return nil
        }
        let mid = (upper.value + lower.value) / 2
        guard mid > 0 else { return nil }
        return TossDecimal(mid)
    }

    /// `(현재가 - 기준가) / 기준가`. 기준가가 0 이면 나눌 수 없으므로 `nil`.
    public static func rate(lastPrice: TossDecimal, basePrice: TossDecimal?) -> TossDecimal? {
        guard let basePrice, !basePrice.isZero else { return nil }
        return TossDecimal((lastPrice.value - basePrice.value) / basePrice.value)
    }
}
