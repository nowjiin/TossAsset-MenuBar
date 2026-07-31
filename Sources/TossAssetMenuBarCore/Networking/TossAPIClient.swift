import Foundation

/// 토스증권 Open API 호출의 단일 진입점.
///
/// 이 앱은 **조회 전용**이므로 주문·조건주문 엔드포인트는 의도적으로 노출하지 않는다.
/// 실수로도 매매가 발생할 여지를 코드에 두지 않는다.
public actor TossAPIClient {
    public static let defaultBaseURL = URL(string: "https://openapi.tossinvest.com")!

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let gate: RateLimitGate
    private let tokenStore: TokenStore

    private var accountSeq: Int64?

    public init(
        baseURL: URL = TossAPIClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        let gate = RateLimitGate()
        self.baseURL = baseURL
        self.transport = transport
        self.gate = gate
        self.tokenStore = TokenStore(baseURL: baseURL, transport: transport, gate: gate)
    }

    // MARK: - 설정

    public func setCredentials(_ credentials: TossCredentials?) async {
        await tokenStore.setCredentials(credentials)
    }

    public func setAccountSeq(_ seq: Int64?) {
        accountSeq = seq
    }

    public func hasCredentials() async -> Bool {
        await tokenStore.hasCredentials
    }

    /// 키가 유효한지 확인만 한다. 온보딩에서 "연결 확인" 버튼에 쓴다.
    public func verifyCredentials() async throws {
        _ = try await tokenStore.token()
    }

    // MARK: - 조회

    public func accounts() async throws -> [Account] {
        try await request(.accounts, as: [Account].self)
    }

    /// `symbol` 을 주면 그 종목만 반환하며 요약 금액도 해당 종목 기준으로 재계산된다.
    public func holdings(symbol: String? = nil) async throws -> HoldingsOverview {
        try await request(.holdings(symbol: symbol), as: HoldingsOverview.self)
    }

    /// 한 번에 최대 200 심볼. 그보다 많으면 나눠 호출한다.
    public func prices(symbols: [String]) async throws -> [StockPrice] {
        guard !symbols.isEmpty else { return [] }
        var results: [StockPrice] = []
        for chunk in symbols.chunked(into: tossMaxSymbolsPerRequest) {
            results += try await request(.prices(symbols: chunk), as: [StockPrice].self)
        }
        return results
    }

    public func stocks(symbols: [String]) async throws -> [StockInfo] {
        guard !symbols.isEmpty else { return [] }
        var results: [StockInfo] = []
        for chunk in symbols.chunked(into: tossMaxSymbolsPerRequest) {
            results += try await request(.stocks(symbols: chunk), as: [StockInfo].self)
        }
        return results
    }

    /// 기준 통화 1단위가 표시 통화로 얼마인지. 기본은 USD → KRW.
    /// 두 파라미터는 API 필수값이라 생략할 수 없다.
    public func exchangeRate(
        base: Currency = .usd,
        quote: Currency = .krw
    ) async throws -> ExchangeRate {
        try await request(.exchangeRate(base: base, quote: quote), as: ExchangeRate.self)
    }

    /// 매매 내역 한 페이지.
    ///
    /// **조회 전용이다.** 이 클라이언트에는 주문을 생성·정정·취소하는 메서드가 없다.
    public func orders(_ query: OrderHistoryQuery) async throws -> OrderHistoryPage {
        try await request(.orders(query), as: OrderHistoryPage.self)
    }

    /// 종목의 직전 거래일 종가.
    ///
    /// **하루에 한 번만 부르면 된다.** 전일 종가는 장중에 바뀌지 않는 상수라, 30초 폴링에
    /// 끼워 넣으면 MARKET_DATA_CHART 한도만 태운다. 호출하는 쪽이 날짜 단위로 캐시한다.
    ///
    /// 봉을 3개 받는 이유는 오늘 첫 체결 전이라 오늘 봉이 아직 없을 수 있어서다.
    /// 그 경우에도 직전 두 거래일이 들어와 기준가를 고를 수 있다.
    public func basePrice(symbol: String) async throws -> TossDecimal? {
        let response = try await request(.candles(symbol: symbol, count: 3), as: CandleResponse.self)
        return DailyChange.basePrice(from: response.candles)
    }

    /// 진행 중 주문 (체결 대기·부분 체결·취소 대기·정정 대기).
    ///
    /// 페이지를 넘기지 않는다 — 문서가 `status=OPEN` 에서는 `limit`/`cursor` 를 무시하고
    /// **전량 반환**한다고 명시한다. 그래서 커서를 따라갈 필요가 없다.
    ///
    /// `from`/`to` 도 넘기지 않는다. `timeInForce` 가 `DAY`/`CLS`/`OPG` 뿐이라 진행 중 주문은
    /// 당일 것밖에 없고, 기간을 걸면 오히려 놓칠 여지만 생긴다.
    public func openOrders(symbol: String? = nil) async throws -> [OrderRecord] {
        try await orders(OrderHistoryQuery(status: .open, symbol: symbol)).orders
    }

    /// 종료된 주문을 구간별·페이지별로 모은다.
    ///
    /// 기간을 한 번에 조회하지 않고 `OrderHistoryQuery.windows(days:)` 로 끊어 **최신 구간부터**
    /// 조회한다. 이유는 그 함수의 주석에 적어두었다 — `to` 를 비우면 서버가 기간을 잘라내고,
    /// 정렬 순서도 문서에 없기 때문이다.
    ///
    /// `maxPagesPerWindow` 로 상한을 두는 이유는, 이력이 길면 커서를 끝까지 따라가며 수십 번
    /// 호출하게 되고 `ORDER_HISTORY` TPS 를 소진하기 때문이다. 어느 구간에서든 남은 페이지가
    /// 있으면 `hasNext` 가 `true` 로 올라오므로 호출한 쪽이 잘렸음을 알 수 있다.
    public func closedOrders(
        symbol: String? = nil,
        days: Int = 90,
        pageSize: Int = 100,
        maxPagesPerWindow: Int = 3
    ) async throws -> OrderHistoryPage {
        var collected: [OrderRecord] = []
        var truncated = false

        let limit = max(1, maxPagesPerWindow)
        for window in OrderHistoryQuery.windows(days: days) {
            var cursor: String?
            for attempt in 0..<limit {
                let page = try await orders(
                    OrderHistoryQuery(
                        status: .closed,
                        symbol: symbol,
                        from: window.from,
                        to: window.to,
                        cursor: cursor,
                        limit: pageSize
                    )
                )
                collected += page.orders
                guard page.hasNext, let next = page.nextCursor else { break }
                cursor = next
                // 마지막으로 허용된 페이지까지 왔는데도 더 남았다 — 그때만 잘린 것이다.
                if attempt == limit - 1 { truncated = true }
            }
        }

        // 구간 경계에서 같은 주문이 두 번 들어올 여지를 없앤다.
        // 구간은 겹치지 않게 만들지만, 서버가 경계를 포함하는 방식이 바뀌어도 버티게 한다.
        var seen = Set<String>()
        let unique = collected.filter { seen.insert($0.orderId).inserted }

        return OrderHistoryPage(orders: unique, nextCursor: nil, hasNext: truncated)
    }

    /// 국내·해외 장 운영 시간. 하루 한 번만 부르면 된다.
    /// 한쪽이 실패해도 다른 쪽으로 판단할 수 있게 개별적으로 시도한다.
    public func marketHours() async -> MarketHours {
        let kr = try? await request(.marketCalendarKR, as: KrMarketCalendar.self)
        let us = try? await request(.marketCalendarUS, as: UsMarketCalendar.self)
        return MarketHours(kr: kr, us: us)
    }

    // MARK: - 요청 실행

    /// 최대 3회까지 시도한다. 429 는 백오프 후, 401 은 토큰 재발급 후 재시도한다.
    private func request<T: Decodable & Sendable>(
        _ endpoint: TossEndpoint,
        as type: T.Type
    ) async throws -> T {
        if endpoint.requiresAccount, accountSeq == nil {
            throw TossAPIError.accountNotSelected
        }

        var lastError: TossAPIError = .transport(description: "요청을 시도하지 못했습니다.")
        var didRefreshToken = false

        for attempt in 0..<3 {
            let token: String
            do {
                token = try await tokenStore.token()
            } catch let error as TossAPIError {
                throw error
            }

            await gate.waitForSlot(endpoint.group)

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(try makeRequest(endpoint, token: token))
            } catch let error as TossAPIError {
                lastError = error
                throw error
            } catch {
                throw TossAPIError.transport(description: (error as NSError).localizedDescription)
            }

            if let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Double.init) {
                await gate.observe(limit: limit, for: endpoint.group)
            }

            if response.statusCode == 200 {
                do {
                    return try TossJSON.decoder().decode(ApiEnvelope<T>.self, from: data).result
                } catch {
                    throw TossAPIError.decoding(description: "\(endpoint.path) 응답 해석 실패")
                }
            }

            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            let body = try? TossJSON.decoder().decode(ApiErrorEnvelope.self, from: data).error
            let error = TossAPIError.from(
                status: response.statusCode,
                body: body,
                retryAfter: retryAfter,
                symbol: endpoint.symbolHint
            )
            lastError = error

            switch error {
            case .rateLimited:
                await gate.penalize(endpoint.group, retryAfter: retryAfter, attempt: attempt)
            case .tokenRejected where !didRefreshToken:
                // 다른 곳에서 재발급해 우리 토큰이 무효화된 경우. 한 번만 다시 받아 본다.
                didRefreshToken = true
                await tokenStore.invalidate()
            default:
                throw error
            }
        }

        throw lastError
    }

    /// URL 조립에 실패하면 크래시시키지 않고 오류로 돌려준다.
    ///
    /// 쿼리 파라미터로 종목 심볼이 흘러드는 자리다. `SymbolValidator` 가 `A-Z0-9.-` 로 막고 있어
    /// 지금은 실패할 수 없지만, 검증을 우회하는 경로가 하나라도 생기면 강제 언랩은 앱을 죽인다.
    /// 메뉴바 앱이 조용히 사라지는 건 최악의 실패 방식이다.
    private func makeRequest(_ endpoint: TossEndpoint, token: String) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appending(path: endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw TossAPIError.transport(description: "요청 주소를 만들 수 없습니다: \(endpoint.path)")
        }
        let items = endpoint.queryItems
        if !items.isEmpty { components.queryItems = items }

        guard let url = components.url else {
            throw TossAPIError.transport(description: "요청 주소를 만들 수 없습니다: \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.requiresAccount, let accountSeq {
            request.setValue(String(accountSeq), forHTTPHeaderField: "X-Tossinvest-Account")
        }
        return request
    }
}

extension TossEndpoint {
    /// 404 stock-not-found 메시지에 종목을 끼워 넣기 위한 힌트.
    var symbolHint: String? {
        switch self {
        case .holdings(let symbol): symbol
        case .prices(let symbols), .stocks(let symbols): symbols.first
        default: nil
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
