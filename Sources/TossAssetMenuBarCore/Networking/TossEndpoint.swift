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

    public var defaultRequestsPerSecond: Double {
        switch self {
        case .auth: 5
        case .account: 1
        case .asset: 5
        case .stock: 5
        case .marketInfo: 3
        case .marketData: 10
        }
    }
}

/// 이 앱이 호출하는 엔드포인트. 조회 전용이므로 주문·조건주문 계열은 의도적으로 넣지 않는다.
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
        }
    }

    /// 계좌 컨텍스트가 필요한 엔드포인트는 `X-Tossinvest-Account` 헤더를 반드시 붙여야 한다.
    ///
    /// `/accounts` 는 여기서 제외한다. 그 헤더에 넣을 `accountSeq` 를 바로 이 API 로 알아내기 때문에
    /// 자기 자신이 계좌를 요구할 수는 없다.
    public var requiresAccount: Bool {
        switch self {
        case .holdings: true
        case .token, .accounts, .prices, .stocks, .exchangeRate, .marketCalendarKR, .marketCalendarUS: false
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .holdings(let symbol):
            symbol.map { [URLQueryItem(name: "symbol", value: $0)] } ?? []
        case .prices(let symbols):
            [URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))]
        case .stocks(let symbols):
            [URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))]
        case .exchangeRate(let base, let quote):
            [
                URLQueryItem(name: "baseCurrency", value: base.rawValue),
                URLQueryItem(name: "quoteCurrency", value: quote.rawValue),
            ]
        case .token, .accounts, .marketCalendarKR, .marketCalendarUS:
            []
        }
    }
}

/// `/prices`, `/stocks` 는 한 번에 최대 200 심볼까지 받는다.
public let tossMaxSymbolsPerRequest = 200
