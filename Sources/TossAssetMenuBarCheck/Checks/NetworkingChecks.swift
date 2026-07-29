import Foundation
import TossAssetMenuBarCore

/// 인증·요청 구성·오류 매핑·rate limit. 실제 네트워크는 타지 않고 `StubTransport` 로 대신한다.
func runNetworkingChecks(_ check: CheckHarness) async throws {
    // MARK: 오류 매핑

    await check.group("TossAPIError — 상태코드·에러코드 매핑")

    await check.expectEqual(
        TossAPIError.from(status: 401, body: apiErrorBody("invalid-token"), retryAfter: nil),
        TossAPIError.tokenRejected(code: "invalid-token"),
        "401 invalid-token 은 재발급 대상이다"
    )
    await check.expect(
        TossAPIError.from(status: 401, body: apiErrorBody("expired-token"), retryAfter: nil).isTokenRecoverable,
        "만료 토큰은 재시도 가능으로 분류한다"
    )
    await check.expectEqual(
        TossAPIError.from(status: 403, body: apiErrorBody("edge-blocked"), retryAfter: nil),
        TossAPIError.ipNotAllowed,
        "403 edge-blocked 는 허용 IP 문제로 안내한다"
    )
    await check.expectEqual(
        TossAPIError.from(status: 429, body: apiErrorBody("rate-limit-exceeded"), retryAfter: 2),
        TossAPIError.rateLimited(retryAfter: 2),
        "429 는 Retry-After 를 보존한다"
    )
    await check.expectEqual(
        TossAPIError.from(status: 404, body: apiErrorBody("account-not-found"), retryAfter: nil),
        TossAPIError.accountNotFound,
        "404 account-not-found 는 계좌 재선택을 유도한다"
    )
    await check.expectEqual(
        TossAPIError.from(status: 500, body: apiErrorBody("maintenance"), retryAfter: nil),
        TossAPIError.maintenance,
        "점검 중은 별도로 구분한다"
    )
    await check.expect(
        TossAPIError.ipNotAllowed.needsUserAction,
        "허용 IP 문제는 사용자 조치가 필요하다"
    )
    await check.expect(
        !TossAPIError.rateLimited(retryAfter: nil).needsUserAction,
        "rate limit 은 자동 회복 대상이다"
    )
    await check.expect(
        TossAPIError.ipNotAllowed.userMessage.contains("허용 IP"),
        "허용 IP 안내 문구가 사용자 메시지에 들어 있다"
    )

    // MARK: 토큰 발급 직렬화

    await check.group("TokenStore — client 당 유효 토큰 1개 제약")

    do {
        let transport = StubTransport(stubs: ["/oauth2/token": [.init(body: Fixtures.token)]])
        let store = TokenStore(
            baseURL: TossAPIClient.defaultBaseURL,
            transport: transport,
            gate: RateLimitGate()
        )
        await store.setCredentials(TossCredentials(clientID: "id", clientSecret: "secret"))

        // 동시에 8개가 토큰을 요구해도 발급은 한 번만 일어나야 한다.
        // 재발급은 이전 토큰을 즉시 무효화하므로 중복 발급은 곧 서로를 죽이는 버그가 된다.
        let tokens = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<8 {
                group.addTask { try? await store.token() }
            }
            var collected: [String?] = []
            for await token in group { collected.append(token) }
            return collected
        }

        await check.expectEqual(tokens.compactMap { $0 }.count, 8, "8개 요청 모두 토큰을 받는다")
        await check.expectEqual(transport.requestCount(path: "/oauth2/token"), 1, "발급 요청은 한 번만 나간다")
        await check.expectEqual(Set(tokens.compactMap { $0 }).count, 1, "모두 같은 토큰을 공유한다")

        // 캐시된 토큰은 재발급하지 않는다.
        _ = try? await store.token()
        await check.expectEqual(transport.requestCount(path: "/oauth2/token"), 1, "캐시가 살아 있으면 재발급하지 않는다")

        // 401 을 받아 무효화하면 다시 발급한다.
        await store.invalidate()
        _ = try? await store.token()
        await check.expectEqual(transport.requestCount(path: "/oauth2/token"), 2, "무효화 후에는 다시 발급한다")
    }

    do {
        let store = TokenStore(
            baseURL: TossAPIClient.defaultBaseURL,
            transport: StubTransport(stubs: [:]),
            gate: RateLimitGate()
        )
        await check.expectError(.notConfigured, "키가 없으면 발급을 시도하지 않는다") {
            _ = try await store.token()
        }
    }

    do {
        let transport = StubTransport(stubs: [
            "/oauth2/token": [.init(status: 401, body: #"{"error":"invalid_client","error_description":"bad key"}"#)]
        ])
        let store = TokenStore(
            baseURL: TossAPIClient.defaultBaseURL,
            transport: transport,
            gate: RateLimitGate()
        )
        await store.setCredentials(TossCredentials(clientID: "id", clientSecret: "wrong"))
        await check.expectError(.invalidCredentials, "잘못된 키는 OAuth2 표준 오류로 판별한다") {
            _ = try await store.token()
        }
    }

    do {
        let transport = StubTransport(stubs: ["/oauth2/token": [.init(status: 403, body: "")]])
        let store = TokenStore(
            baseURL: TossAPIClient.defaultBaseURL,
            transport: transport,
            gate: RateLimitGate()
        )
        await store.setCredentials(TossCredentials(clientID: "id", clientSecret: "secret"))
        await check.expectError(.ipNotAllowed, "토큰 발급 단계의 403 도 허용 IP 문제로 안내한다") {
            _ = try await store.token()
        }
    }

    // MARK: 요청 구성

    await check.group("TossAPIClient — 헤더와 요청 구성")

    do {
        let (client, transport) = await makeClient(["/api/v1/accounts": [.init(body: Fixtures.accounts)]])

        let accounts = try await client.accounts()
        await check.expectEqual(accounts.count, 1, "계좌 목록을 읽는다")
        await check.expectEqual(accounts[0].accountSeq, 1, "accountSeq 를 읽는다")
        await check.expectEqual(accounts[0].maskedAccountNo, "•••• 8901", "계좌번호는 뒤 4자리만 노출한다")
        await check.expect(
            transport.header("X-Tossinvest-Account", forPath: "/api/v1/accounts") == nil,
            "/accounts 는 계좌 헤더 없이 호출한다"
        )
        await check.expectEqual(
            transport.header("Authorization", forPath: "/api/v1/accounts"),
            "Bearer eyJhbGciOi.stub",
            "Bearer 토큰을 헤더에 넣는다"
        )
    }

    do {
        let (client, transport) = await makeClient(["/api/v1/holdings": [.init(body: Fixtures.holdings)]])
        await client.setAccountSeq(7)

        let overview = try await client.holdings()
        await check.expectEqual(overview.items.count, 2, "보유 주식을 조회한다")
        await check.expectEqual(
            transport.header("X-Tossinvest-Account", forPath: "/api/v1/holdings"),
            "7",
            "보유 조회에는 계좌 헤더를 붙인다"
        )
    }

    do {
        let (client, _) = await makeClient(["/api/v1/holdings": [.init(body: Fixtures.holdings)]])
        await check.expectError(.accountNotSelected, "계좌를 고르지 않으면 호출 전에 막는다") {
            _ = try await client.holdings()
        }
    }

    do {
        // 201 심볼이면 200 + 1 로 두 번 나눠 호출해야 한다.
        let (client, transport) = await makeClient(["/api/v1/prices": [.init(body: #"{"result":[]}"#)]])
        let symbols = (0..<201).map { "SYM\($0)" }
        _ = try await client.prices(symbols: symbols)
        await check.expectEqual(
            transport.requestCount(path: "/api/v1/prices"),
            2,
            "200 심볼 제한에 맞춰 요청을 나눈다"
        )

        await check.expectEqual(
            try await client.prices(symbols: []).count,
            0,
            "심볼이 없으면 호출하지 않는다"
        )
        await check.expectEqual(
            transport.requestCount(path: "/api/v1/prices"),
            2,
            "빈 목록은 네트워크 요청을 만들지 않는다"
        )
    }

    do {
        // 401 을 한 번 받으면 토큰을 다시 받아 재시도해야 한다.
        let (client, transport) = await makeClient([
            "/api/v1/holdings": [
                .init(status: 401, body: #"{"error":{"requestId":"r","code":"expired-token","message":"만료"}}"#),
                .init(body: Fixtures.holdings),
            ]
        ])
        await client.setAccountSeq(1)

        let overview = try await client.holdings()
        await check.expectEqual(overview.items.count, 2, "401 후 재발급하고 재시도해 성공한다")
        await check.expectEqual(transport.requestCount(path: "/oauth2/token"), 2, "토큰을 한 번 다시 받는다")
        await check.expectEqual(transport.requestCount(path: "/api/v1/holdings"), 2, "보유 조회를 한 번만 재시도한다")
    }

    do {
        // baseCurrency·quoteCurrency 는 API 필수값이다. 빼먹으면 400 이 떨어지는데,
        // 환율은 부가 정보라 조용히 실패해서 원인을 찾기 어려웠다.
        let (client, transport) = await makeClient([
            "/api/v1/exchange-rate": [.init(body: Fixtures.exchangeRate)]
        ])

        let rate = try await client.exchangeRate()
        await check.expectEqual(rate.midRate.value, Decimal(1375), "매매기준율을 읽는다")
        await check.expectEqual(rate.baseCurrency, Currency.usd, "기준 통화는 USD")

        let query = transport.query(forPath: "/api/v1/exchange-rate")
        await check.expectEqual(query["baseCurrency"], "USD", "baseCurrency 를 반드시 보낸다")
        await check.expectEqual(query["quoteCurrency"], "KRW", "quoteCurrency 를 반드시 보낸다")
    }

    do {
        let (client, _) = await makeClient([
            "/api/v1/holdings": [.init(status: 403, body: #"{"error":{"requestId":"r","code":"edge-blocked","message":""}}"#)]
        ])
        await client.setAccountSeq(1)
        await check.expectError(.ipNotAllowed, "403 은 재시도하지 않고 즉시 안내한다") {
            _ = try await client.holdings()
        }
    }

    do {
        let (client, _) = await makeClient(["/api/v1/prices": [.init(body: #"{"result":"엉뚱한값"}"#)]])
        await check.expectError(.decoding, "스펙과 다른 응답은 디코딩 오류로 구분한다") {
            _ = try await client.prices(symbols: ["005930"])
        }
    }

    // MARK: rate limit 게이트

    await check.group("RateLimitGate — 초당 요청 수 준수")

    do {
        // ACCOUNT 그룹은 초당 1회다. 3회 연속 호출이면 최소 2초 이상 걸려야 한다.
        let gate = RateLimitGate()
        let started = ContinuousClock().now
        for _ in 0..<3 {
            await gate.waitForSlot(.account)
        }
        let elapsed = ContinuousClock().now - started
        await check.expect(
            elapsed > .seconds(2),
            "1 TPS 그룹은 3회 호출에 2초 이상 소요된다 (실제 \(elapsed))"
        )
    }

    do {
        // MARKET_DATA 는 10 TPS 라 3회는 거의 즉시 통과해야 한다.
        let gate = RateLimitGate()
        let started = ContinuousClock().now
        for _ in 0..<3 {
            await gate.waitForSlot(.marketData)
        }
        let elapsed = ContinuousClock().now - started
        await check.expect(
            elapsed < .seconds(1),
            "10 TPS 그룹은 3회 호출이 1초 안에 끝난다 (실제 \(elapsed))"
        )
    }
}
