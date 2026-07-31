import Foundation

/// Rate limit 은 **클라이언트 × API 그룹** 단위 TPS 로 걸린다.
/// 여기 적힌 수치는 문서 기준 기본값이며, 실제 허용치는 응답 헤더 `X-RateLimit-Limit` 으로
/// 갱신된다 (문서가 "사전 공지 없이 조정될 수 있다" 고 명시).
public enum RateLimitGroup: String, Sendable, CaseIterable {
    case auth = "AUTH"
    case account = "ACCOUNT"
    case asset = "ASSET"
    case stock = "STOCK"
    case marketInfo = "MARKET_INFO"
    case marketData = "MARKET_DATA"
    /// 주문 **조회** 전용 그룹. 주문 생성·정정·취소는 별도의 `ORDER` 그룹이며 이 앱은 쓰지 않는다.
    case orderHistory = "ORDER_HISTORY"

    public var defaultRequestsPerSecond: Double {
        switch self {
        case .auth: 5
        case .account: 1
        case .asset: 5
        case .stock: 5
        case .marketInfo: 3
        case .marketData: 10
        // 문서가 이 그룹의 TPS 를 명시하지 않아 보수적으로 잡았다. 실제 허용치는 첫 응답의
        // `X-RateLimit-Limit` 으로 갱신되므로, 낮게 시작해도 곧 실측값으로 바뀐다.
        case .orderHistory: 3
        }
    }
}

/// 매매 내역 조회 조건.
///
/// `from`/`to` 는 `format: date` 이며 **KST 기준 날짜**다 (`2026-03-01`). 타임스탬프가 아니다.
/// 문자열로 받는 이유는 앱이 임의의 타임존으로 날짜를 만들어 보내는 사고를 막기 위해서다 —
/// `OrderHistoryQuery.dateString(_:)` 로만 만들게 한다.
public struct OrderHistoryQuery: Sendable, Hashable {
    public var status: OrderStatusFilter
    public var symbol: String?
    public var from: String?
    public var to: String?
    public var cursor: String?
    public var limit: Int?

    public init(
        status: OrderStatusFilter,
        symbol: String? = nil,
        from: String? = nil,
        to: String? = nil,
        cursor: String? = nil,
        limit: Int? = nil
    ) {
        self.status = status
        self.symbol = symbol
        self.from = from
        self.to = to
        self.cursor = cursor
        self.limit = limit
    }

    /// 서버가 기대하는 `yyyy-MM-dd` 를 **KST 기준으로** 만든다.
    /// 기기 타임존으로 만들면 자정 근처에서 하루가 밀린다.
    public static func dateString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MarketTimeZone.kst.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 페이지 크기 상한. 넘겨도 서버가 잘라내지만, 잘렸는지 알 수 없으니 앱에서 맞춘다.
    public static let maxLimit = 100

    /// 조회 구간. `[from, to]` 를 **둘 다** 채운 날짜 문자열 쌍이다.
    public struct DateWindow: Sendable, Hashable {
        public let from: String
        public let to: String
    }

    /// `days` 일치를 `windowDays` 일 단위 구간으로 잘라 **최신 구간부터** 돌려준다.
    ///
    /// 한 번에 긴 기간을 조회하지 않는 이유는 실측 때문이다. `from` 만 보내고 `to` 를 비우면
    /// 서버가 `from` 부터 약 30일까지만 돌려주는 것을 확인했다 (90일을 요청했는데 그 뒤 두 달의
    /// 거래가 빠졌다). 문서에는 그런 제약이 없어서 정확한 규칙을 알 수 없으므로, **항상 `to` 를
    /// 채우고 구간을 짧게 끊는다.** 그러면 숨은 상한이 무엇이든 구간 안에 들어온다.
    ///
    /// 최신 구간을 먼저 조회하는 이유는 CLOSED 의 정렬 순서가 문서에 없기 때문이다. 오래된
    /// 구간부터 받으면 페이지 상한에 걸렸을 때 방금 한 거래가 빠질 수 있다.
    public static func windows(
        days: Int,
        windowDays: Int = 30,
        now: Date = Date()
    ) -> [DateWindow] {
        precondition(days > 0 && windowDays > 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MarketTimeZone.kst.timeZone

        var result: [DateWindow] = []
        var offset = 0
        while offset < days {
            // to 는 offset 일 전, from 은 그보다 windowDays - 1 일 더 전. 구간이 겹치지 않는다.
            let span = min(windowDays, days - offset) - 1
            guard
                let to = calendar.date(byAdding: .day, value: -offset, to: now),
                let from = calendar.date(byAdding: .day, value: -(offset + span), to: now)
            else { break }
            result.append(DateWindow(from: dateString(from), to: dateString(to)))
            offset += span + 1
        }
        return result
    }
}

/// 이 앱이 호출하는 엔드포인트.
///
/// **주문 생성·정정·취소는 넣지 않는다.** `orders` 는 `GET` 조회이며 rate limit 그룹도
/// 쓰기용 `ORDER` 가 아닌 `ORDER_HISTORY` 다. 조건주문 계열도 전부 제외한다.
/// 이 규칙은 검증 항목으로 강제된다 — `NetworkingChecks` 의 "쓰기 엔드포인트가 없다" 항목.
public enum TossEndpoint: Sendable {
    case token
    case accounts
    case holdings(symbol: String?)
    case prices(symbols: [String])
    case stocks(symbols: [String])
    /// `baseCurrency` 와 `quoteCurrency` 는 **필수** 파라미터다. 빼면 400 이 떨어진다.
    case exchangeRate(base: Currency, quote: Currency)
    case marketCalendarKR
    case marketCalendarUS
    /// 매매 내역. `status` 는 필수다.
    case orders(OrderHistoryQuery)

    public var path: String {
        switch self {
        case .token: "/oauth2/token"
        case .accounts: "/api/v1/accounts"
        case .holdings: "/api/v1/holdings"
        case .prices: "/api/v1/prices"
        case .stocks: "/api/v1/stocks"
        case .exchangeRate: "/api/v1/exchange-rate"
        case .marketCalendarKR: "/api/v1/market-calendar/KR"
        case .marketCalendarUS: "/api/v1/market-calendar/US"
        case .orders: "/api/v1/orders"
        }
    }

    public var group: RateLimitGroup {
        switch self {
        case .token: .auth
        case .accounts: .account
        case .holdings: .asset
        case .prices: .marketData
        case .stocks: .stock
        case .exchangeRate, .marketCalendarKR, .marketCalendarUS: .marketInfo
        case .orders: .orderHistory
        }
    }

    /// 계좌 컨텍스트가 필요한 엔드포인트는 `X-Tossinvest-Account` 헤더를 반드시 붙여야 한다.
    ///
    /// `/accounts` 는 여기서 제외한다. 그 헤더에 넣을 `accountSeq` 를 바로 이 API 로 알아내기 때문에
    /// 자기 자신이 계좌를 요구할 수는 없다.
    public var requiresAccount: Bool {
        switch self {
        case .holdings, .orders: true
        case .token, .accounts, .prices, .stocks, .exchangeRate, .marketCalendarKR, .marketCalendarUS: false
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .holdings(let symbol):
            return symbol.map { [URLQueryItem(name: "symbol", value: $0)] } ?? []
        case .prices(let symbols):
            return [URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))]
        case .stocks(let symbols):
            return [URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))]
        case .exchangeRate(let base, let quote):
            return [
                URLQueryItem(name: "baseCurrency", value: base.rawValue),
                URLQueryItem(name: "quoteCurrency", value: quote.rawValue),
            ]
        case .orders(let query):
            // status 는 필수다. 나머지는 값이 있을 때만 붙인다 — 빈 문자열을 보내면
            // 서버가 "전체 기간" 대신 잘못된 필터로 받을 수 있다.
            var items = [URLQueryItem(name: "status", value: query.status.rawValue)]
            if let symbol = query.symbol { items.append(URLQueryItem(name: "symbol", value: symbol)) }
            if let from = query.from { items.append(URLQueryItem(name: "from", value: from)) }
            if let to = query.to { items.append(URLQueryItem(name: "to", value: to)) }
            if let cursor = query.cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            if let limit = query.limit {
                items.append(URLQueryItem(name: "limit", value: String(min(limit, OrderHistoryQuery.maxLimit))))
            }
            return items
        case .token, .accounts, .marketCalendarKR, .marketCalendarUS:
            return []
        }
    }
}

/// `/prices`, `/stocks` 는 한 번에 최대 200 심볼까지 받는다.
public let tossMaxSymbolsPerRequest = 200
