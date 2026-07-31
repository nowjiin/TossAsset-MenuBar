import Foundation

/// 세션 하나의 시작·종료. 응답에는 종가단일가 시각 같은 필드가 더 있지만
/// 폴링 여부를 판단하는 데는 구간만 필요하다.
public struct MarketSession: Decodable, Sendable, Hashable {
    public let startTime: Date
    public let endTime: Date

    public init(startTime: Date, endTime: Date) {
        self.startTime = startTime
        self.endTime = endTime
    }

    public func contains(_ date: Date) -> Bool {
        date >= startTime && date <= endTime
    }
}

/// 국내 거래 가능 시간 (통합 모드 KRX+NXT). 세션이 휴장이면 nil.
public struct KrTradingHours: Decodable, Sendable {
    public let preMarket: MarketSession?
    public let regularMarket: MarketSession?
    public let afterMarket: MarketSession?

    public init(preMarket: MarketSession?, regularMarket: MarketSession?, afterMarket: MarketSession?) {
        self.preMarket = preMarket
        self.regularMarket = regularMarket
        self.afterMarket = afterMarket
    }

    var sessions: [MarketSession] {
        [preMarket, regularMarket, afterMarket].compactMap { $0 }
    }
}

public struct KrMarketDay: Decodable, Sendable {
    /// `2026-03-25` 형식. 커스텀 날짜 디코딩 전략이 ISO 8601 date-time 만 받으므로
    /// 여기서는 문자열로 그대로 둔다.
    public let date: String
    /// KRX·NXT 둘 다 휴장이면 nil.
    public let integrated: KrTradingHours?

    public init(date: String, integrated: KrTradingHours?) {
        self.date = date
        self.integrated = integrated
    }

    var sessions: [MarketSession] { integrated?.sessions ?? [] }
}

public struct KrMarketCalendar: Decodable, Sendable {
    public let today: KrMarketDay
    public let previousBusinessDay: KrMarketDay
    public let nextBusinessDay: KrMarketDay

    public init(today: KrMarketDay, previousBusinessDay: KrMarketDay, nextBusinessDay: KrMarketDay) {
        self.today = today
        self.previousBusinessDay = previousBusinessDay
        self.nextBusinessDay = nextBusinessDay
    }

    var allSessions: [MarketSession] {
        previousBusinessDay.sessions + today.sessions + nextBusinessDay.sessions
    }
}

public struct UsMarketDay: Decodable, Sendable {
    public let date: String
    public let dayMarket: MarketSession?
    public let preMarket: MarketSession?
    public let regularMarket: MarketSession?
    public let afterMarket: MarketSession?

    public init(
        date: String,
        dayMarket: MarketSession?,
        preMarket: MarketSession?,
        regularMarket: MarketSession?,
        afterMarket: MarketSession?
    ) {
        self.date = date
        self.dayMarket = dayMarket
        self.preMarket = preMarket
        self.regularMarket = regularMarket
        self.afterMarket = afterMarket
    }

    var sessions: [MarketSession] {
        [dayMarket, preMarket, regularMarket, afterMarket].compactMap { $0 }
    }
}

public struct UsMarketCalendar: Decodable, Sendable {
    public let today: UsMarketDay
    public let previousBusinessDay: UsMarketDay
    public let nextBusinessDay: UsMarketDay

    public init(today: UsMarketDay, previousBusinessDay: UsMarketDay, nextBusinessDay: UsMarketDay) {
        self.today = today
        self.previousBusinessDay = previousBusinessDay
        self.nextBusinessDay = nextBusinessDay
    }

    var allSessions: [MarketSession] {
        previousBusinessDay.sessions + today.sessions + nextBusinessDay.sessions
    }
}

/// 다음 개장 시각과 그게 어느 시장인지.
public struct MarketOpening: Sendable, Hashable {
    public let date: Date
    public let market: MarketCountry

    public init(date: Date, market: MarketCountry) {
        self.date = date
        self.market = market
    }

    /// 이 시각을 보여줄 때 쓸 타임존. 국내는 KST, 미국은 미국 동부.
    public var displayTimeZone: MarketTimeZone {
        MarketTimeZone.forMarket(market)
    }

    public var marketLabel: String {
        switch market {
        case .kr: "국내"
        case .us: "해외"
        case .other(let raw): raw
        }
    }
}

/// 지금 어느 시장이든 열려 있는지 판단한다.
///
/// 폐장 중에는 시세가 움직이지 않으므로 폴링을 멈춰 rate limit 과 배터리를 아낀다.
///
/// 전날·다음날 세션까지 함께 보는 이유: 미국 정규장은 KST 로 22:30~다음날 05:00 이라
/// 자정을 넘어가고, "오늘" 의 기준일도 KR(KST) 과 US(현지) 가 다르다. 세션 시각은 절대 시간이므로
/// 세 날짜의 세션을 모두 훑으면 경계에서 잘못 판단할 일이 없다.
public struct MarketHours: Sendable {
    public let kr: KrMarketCalendar?
    public let us: UsMarketCalendar?

    public init(kr: KrMarketCalendar?, us: UsMarketCalendar?) {
        self.kr = kr
        self.us = us
    }

    /// 세션마다 어느 시장인지 함께 들고 있어야 한다.
    /// 표시할 타임존이 시장에 따라 달라지기 때문이다 (국내는 KST, 미국은 현지 시간).
    private var taggedSessions: [(session: MarketSession, market: MarketCountry)] {
        (kr?.allSessions ?? []).map { ($0, MarketCountry.kr) }
            + (us?.allSessions ?? []).map { ($0, MarketCountry.us) }
    }

    public func isAnyMarketOpen(at date: Date = Date()) -> Bool {
        taggedSessions.contains { $0.session.contains(date) }
    }

    /// 지금 열려 있는 시장들. 국내·미국이 동시에 열리는 구간도 있다.
    public func openMarkets(at date: Date = Date()) -> [MarketCountry] {
        var markets: [MarketCountry] = []
        for tagged in taggedSessions where tagged.session.contains(date) {
            if !markets.contains(tagged.market) { markets.append(tagged.market) }
        }
        return markets
    }

    /// 다음 개장. 폐장 중일 때 "몇 시에 다시 열립니다" 안내에 쓴다.
    /// 어느 시장인지 함께 돌려주므로 호출부가 알맞은 타임존으로 표시할 수 있다.
    public func nextOpening(after date: Date = Date()) -> MarketOpening? {
        taggedSessions
            .filter { $0.session.startTime > date }
            .min { $0.session.startTime < $1.session.startTime }
            .map { MarketOpening(date: $0.session.startTime, market: $0.market) }
    }

    /// 그 시장의 **오늘 장이 이미 시작됐는지**.
    ///
    /// "지금 열려 있는지"(`openMarkets`)와 다르다. 폐장 후에도 오늘 장이 있었다면 현재가는
    /// 오늘 종가이고, 기준가는 어제 종가여야 한다. 개장 여부로 판단하면 폐장 직후에
    /// 그제 종가가 기준이 되어 이틀치 등락률이 나온다 — 실제로 그렇게 틀렸다.
    ///
    /// 휴장일이면 오늘 세션이 없으므로 `false` 다. 그때 현재가는 마지막 거래일 종가다.
    public func hasSessionStartedToday(_ market: MarketCountry, at date: Date = Date()) -> Bool {
        let sessions: [MarketSession]
        switch market {
        case .kr: sessions = kr?.today.sessions ?? []
        case .us: sessions = us?.today.sessions ?? []
        case .other: sessions = []
        }
        guard let firstStart = sessions.map(\.startTime).min() else { return false }
        return date >= firstStart
    }

    /// 캘린더를 하나도 못 받았으면 판단할 근거가 없다.
    /// 이때는 폴링을 멈추지 않는다 — 조회가 안 되는 것보다 조금 더 부르는 게 낫다.
    public var isUnknown: Bool {
        kr == nil && us == nil
    }
}
