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
