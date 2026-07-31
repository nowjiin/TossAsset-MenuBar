import Foundation
import TossAssetMenuBarCore

/// 매매 내역 조회 검증.
///
/// 이 영역의 첫 번째 목적은 **조회 전용이라는 약속을 고정하는 것**이다. `/orders` 는 주문 계열
/// 경로이므로, 실수로 쓰기 요청을 보내는 코드가 들어오면 여기서 막혀야 한다.
func runOrderHistoryChecks(_ check: CheckHarness) async throws {
    let decoder = TossJSON.decoder()

    await check.group("OrderHistory — 조회 전용 보장")

    do {
        // 앱이 실제로 부르는 모든 엔드포인트를 한 번씩 태워, 전송된 요청이 전부 GET 인지 본다.
        // makeRequest 가 "GET" 을 하드코딩하고 있지만, 하드코딩이 풀리는 순간을 잡는 게 이 검증이다.
        let (client, transport) = await makeClient([
            "/api/v1/accounts": [.init(body: Fixtures.accounts)],
            "/api/v1/holdings": [.init(body: Fixtures.holdings)],
            "/api/v1/prices": [.init(body: #"{"result":[]}"#)],
            "/api/v1/stocks": [.init(body: #"{"result":[]}"#)],
            "/api/v1/exchange-rate": [.init(body: Fixtures.exchangeRate)],
            "/api/v1/orders": [.init(body: Fixtures.closedOrdersPage2)],
        ])
        await client.setAccountSeq(1)
        _ = try? await client.accounts()
        _ = try? await client.holdings()
        _ = try? await client.prices(symbols: ["005930"])
        _ = try? await client.stocks(symbols: ["005930"])
        _ = try? await client.exchangeRate()
        _ = try? await client.orders(OrderHistoryQuery(status: .closed))

        // 토큰 발급만 POST 다 (OAuth2 가 form 본문을 요구한다). 그 외에 GET 이 아닌 요청이
        // 생기면 조회 전용이라는 약속이 깨진 것이다.
        let nonGet = transport.nonGetRequests()
        let apiWrites = nonGet.filter { $0.path.hasPrefix("/api/") }
        await check.expect(
            apiWrites.isEmpty,
            "/api 경로 요청은 전부 GET 이다" + (apiWrites.isEmpty ? "" : " — 위반: \(apiWrites)")
        )
        await check.expectEqual(
            nonGet.map(\.path).sorted(),
            ["/oauth2/token"],
            "GET 이 아닌 요청은 토큰 발급 하나뿐이다"
        )
    }

    await check.expectEqual(
        TossEndpoint.orders(OrderHistoryQuery(status: .closed)).group,
        .orderHistory,
        "매매 내역은 쓰기용 ORDER 가 아닌 ORDER_HISTORY 그룹이다"
    )

    await check.expect(
        TossEndpoint.orders(OrderHistoryQuery(status: .closed)).requiresAccount,
        "매매 내역 조회에는 계좌 헤더가 필요하다"
    )

    await check.group("OrderHistoryQuery — 쿼리 구성")

    do {
        let items = TossEndpoint.orders(OrderHistoryQuery(status: .open)).queryItems
        await check.expectEqual(items.count, 1, "값이 없는 파라미터는 붙이지 않는다")
        await check.expectEqual(items.first?.name, "status", "status 는 필수라 항상 붙는다")
        await check.expectEqual(items.first?.value, "OPEN", "status 값이 그대로 실린다")
    }

    do {
        let query = OrderHistoryQuery(
            status: .closed,
            symbol: "AAPL",
            from: "2026-03-01",
            to: "2026-03-31",
            cursor: "CURSOR",
            limit: 50
        )
        let items = Dictionary(
            TossEndpoint.orders(query).queryItems.compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        await check.expectEqual(items["status"], "CLOSED", "종료된 주문 필터")
        await check.expectEqual(items["symbol"], "AAPL", "종목 필터")
        await check.expectEqual(items["from"], "2026-03-01", "시작일")
        await check.expectEqual(items["to"], "2026-03-31", "종료일")
        await check.expectEqual(items["cursor"], "CURSOR", "페이지 커서")
        await check.expectEqual(items["limit"], "50", "페이지 크기")
    }

    do {
        // 상한을 넘겨 보내면 서버가 잘라내지만 잘렸는지 알 수 없다. 앱에서 맞춘다.
        let query = OrderHistoryQuery(status: .closed, limit: 500)
        let limit = TossEndpoint.orders(query).queryItems.first { $0.name == "limit" }?.value
        await check.expectEqual(limit, "100", "limit 은 최대 100 으로 잘린다")
    }

    do {
        // KST 기준으로 날짜를 만들어야 한다. 기기 타임존으로 만들면 자정 근처에서 하루가 밀린다.
        // 2026-03-01T15:30:00Z 은 KST 로 2026-03-02 00:30 이다.
        // UTC 로 날짜를 만들면 03-01 이 되어 하루가 밀린다.
        let instant = Date(timeIntervalSince1970: 1_772_379_000)
        await check.expectEqual(
            OrderHistoryQuery.dateString(instant),
            "2026-03-02",
            "날짜 문자열은 KST 기준으로 만든다"
        )
    }

    await check.group("OrderRecord — 문서 예시 디코딩")

    do {
        let page = try decoder.decode(
            ApiEnvelope<OrderHistoryPage>.self,
            from: Data(Fixtures.closedOrdersPage1.utf8)
        ).result
        await check.expectEqual(page.orders.count, 1, "주문 1건")
        await check.expectEqual(page.hasNext, true, "다음 페이지가 있다")
        await check.expectEqual(page.nextCursor, "CURSOR-2", "다음 커서를 그대로 보존한다")

        let order = page.orders[0]
        await check.expectEqual(order.symbol, "005930", "종목")
        await check.expectEqual(order.side, .buy, "매수")
        await check.expectEqual(order.orderType, .limit, "지정가")
        await check.expectEqual(order.status, .filled, "전량 체결")
        await check.expectEqual(order.price, "70000", "주문 가격")
        await check.expectEqual(order.quantity, "10", "주문 수량")
        await check.expectEqual(order.currency, .krw, "거래 통화")
        await check.expectEqual(order.execution.filledQuantity, "10", "체결 수량")
        await check.expectEqual(order.execution.averageFilledPrice, "70000", "평균 체결가")
        await check.expectEqual(order.execution.commission, "1400", "수수료는 토스가 내려준 값")
        await check.expectEqual(order.execution.tax, "0", "세금 0 과 미정산(null) 은 다르다")
        await check.expectEqual(order.execution.settlementDate, "2026-03-30", "결제일은 날짜 문자열")
        await check.expect(order.execution.hasFill, "체결이 있다")
        await check.expectEqual(order.execution.totalCost, "1400", "수수료 + 세금")
    }

    do {
        // 시장가 주문은 price 가 null 이다. 0 으로 채우면 "0원에 주문" 이 되어 버린다.
        let page = try decoder.decode(
            ApiEnvelope<OrderHistoryPage>.self,
            from: Data(Fixtures.closedOrdersPage2.utf8)
        ).result
        let order = page.orders[0]
        await check.expect(order.price == nil, "시장가 주문의 가격은 nil 이다")
        await check.expectEqual(order.orderType, .market, "시장가")
        await check.expectEqual(order.status, .canceled, "취소됨")
        await check.expect(order.canceledAt != nil, "취소 시각이 있다")

        // 취소된 주문에도 부분 체결이 남을 수 있다. 문서가 명시적으로 안내하는 부분이다.
        await check.expect(order.execution.hasFill, "취소된 주문에도 부분 체결이 남아 있다")
        await check.expectEqual(order.execution.filledQuantity, "2", "부분 체결 수량")
        await check.expectEqual(
            order.execution.totalCost, "0.66",
            "tax 가 null 이면 commission 만으로 합산한다"
        )
        await check.expectEqual(page.hasNext, false, "마지막 페이지")
        await check.expect(page.nextCursor == nil, "마지막 페이지에는 커서가 없다")
    }

    do {
        let page = try decoder.decode(
            ApiEnvelope<OrderHistoryPage>.self,
            from: Data(Fixtures.openOrders.utf8)
        ).result
        let order = page.orders[0]
        await check.expectEqual(order.status, .pending, "체결 대기")
        await check.expect(!order.execution.hasFill, "체결 수량이 0 이다")
        await check.expect(
            order.execution.totalCost == nil,
            "수수료·세금이 모두 없으면 합계는 nil 이다 — 0 으로 바꾸면 미정산과 구분되지 않는다"
        )
        await check.expect(order.execution.filledAt == nil, "체결 시각이 없다")
        await check.expectEqual(
            order.displayDate, order.orderedAt,
            "미체결이면 표시 시각은 주문 시각이다"
        )
    }

    do {
        // status=OPEN 은 전량 반환이라 커서가 없다.
        await check.expect(
            !TossEndpoint.orders(OrderHistoryQuery(status: .open)).queryItems
                .contains { $0.name == "cursor" },
            "OPEN 조회에는 커서를 붙이지 않는다"
        )
    }

    await check.group("OrderStatus — unknown 값 허용")

    do {
        let page = try decoder.decode(
            ApiEnvelope<OrderHistoryPage>.self,
            from: Data(Fixtures.ordersWithUnknownEnums.utf8)
        ).result
        let order = page.orders[0]
        await check.expectEqual(order.side, .other("SHORT_SELL"), "모르는 side 를 흡수한다")
        await check.expectEqual(order.orderType, .other("TRAILING_STOP"), "모르는 orderType 을 흡수한다")
        await check.expectEqual(order.timeInForce, .other("IOC"), "모르는 timeInForce 를 흡수한다")
        await check.expectEqual(order.status, .other("SOMETHING_NEW"), "모르는 status 를 흡수한다")
        await check.expect(!order.status.isTerminal, "모르는 상태를 종료 상태로 단정하지 않는다")
    }

    await check.group("조회 구간 — to 를 반드시 채운다")

    do {
        // 실측 회귀: from 만 보내고 to 를 비우면 서버가 기간을 잘라낸다.
        // 90일을 요청했는데 그 뒤 두 달의 거래가 빠지는 것을 확인했다.
        let now = Date(timeIntervalSince1970: 1_784_000_000)  // 2026-07-31 KST 근처
        let windows = OrderHistoryQuery.windows(days: 90, now: now)

        await check.expectEqual(windows.count, 3, "90일을 30일 구간 3개로 나눈다")
        await check.expect(
            windows.allSatisfy { !$0.from.isEmpty && !$0.to.isEmpty },
            "모든 구간이 from 과 to 를 함께 갖는다"
        )
        await check.expect(
            windows[0].to > windows[1].to && windows[1].to > windows[2].to,
            "최신 구간부터 온다 — 상한에 걸려도 방금 한 거래를 놓치지 않는다"
        )
        await check.expectEqual(
            windows[0].to, OrderHistoryQuery.dateString(now),
            "첫 구간의 to 는 오늘이다"
        )
        await check.expect(
            windows[0].from > windows[1].to,
            "구간이 겹치지 않는다"
        )
        await check.expectEqual(
            OrderHistoryQuery.windows(days: 30, now: now).count, 1,
            "30일이면 구간 하나"
        )
        await check.expectEqual(
            OrderHistoryQuery.windows(days: 31, now: now).count, 2,
            "31일이면 구간 둘 — 하루가 남으면 버리지 않는다"
        )
    }

    await check.group("closedOrders — 구간·커서 수집")

    do {
        // 구간 3개 × 각 1페이지.
        let (client, transport) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.closedOrdersPage2)]
        ])
        await client.setAccountSeq(1)
        let page = try await client.closedOrders()
        await check.expectEqual(
            transport.requestCount(path: "/api/v1/orders"), 3,
            "구간마다 한 번씩 조회한다"
        )
        await check.expectEqual(
            page.orders.count, 1,
            "구간마다 같은 주문이 와도 orderId 로 중복을 걸러낸다"
        )
        let query = transport.query(forPath: "/api/v1/orders")
        await check.expect(
            query["from"] != nil && query["to"] != nil,
            "from 과 to 를 항상 함께 보낸다"
        )
        await check.expect(!page.hasNext, "상한에 걸리지 않았으면 더 없다고 알린다")
    }

    do {
        // 한 구간 안에서 커서를 따라가는지.
        let (client, transport) = await makeClient([
            "/api/v1/orders": [
                .init(body: Fixtures.closedOrdersPage1),
                .init(body: Fixtures.closedOrdersPage2),
            ]
        ])
        await client.setAccountSeq(1)
        let page = try await client.closedOrders(days: 30)
        await check.expectEqual(
            transport.requestCount(path: "/api/v1/orders"), 2,
            "커서를 따라 다음 페이지를 가져온다"
        )
        await check.expectEqual(page.orders.count, 2, "두 페이지를 이어 붙인다")
        await check.expectEqual(
            transport.query(forPath: "/api/v1/orders")["cursor"], "CURSOR-2",
            "두 번째 호출에 앞 페이지의 커서를 넘긴다"
        )
    }

    do {
        // 상한에 걸리면 잘렸다고 알려야 한다. 조용히 자르면 전체라고 믿는다.
        let (client, transport) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.closedOrdersPage1)]
        ])
        await client.setAccountSeq(1)
        let page = try await client.closedOrders(days: 30, maxPagesPerWindow: 2)
        await check.expectEqual(
            transport.requestCount(path: "/api/v1/orders"), 2,
            "maxPagesPerWindow 에서 멈춘다"
        )
        await check.expect(page.hasNext, "상한에 걸려 남은 페이지가 있음을 알린다")
    }

    do {
        let (client, _) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.emptyOrders)]
        ])
        await client.setAccountSeq(1)
        let page = try await client.closedOrders()
        await check.expect(page.orders.isEmpty, "거래가 없으면 빈 목록이다")
        await check.expect(!page.hasNext, "빈 목록에는 다음 페이지가 없다")
    }

    do {
        let (client, _) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.closedOrdersPage2)]
        ])
        await check.expectError(.accountNotSelected, "계좌를 고르지 않으면 호출 전에 막는다") {
            _ = try await client.orders(OrderHistoryQuery(status: .closed))
        }
    }

    await check.group("openOrders — 진행 중 주문도 보여준다")

    do {
        // CLOSED 만 조회하면 오늘 낸 미체결 주문이 목록에 없다. 그 회귀를 막는다.
        let (client, transport) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.openOrders)]
        ])
        await client.setAccountSeq(1)
        let orders = try await client.openOrders()

        await check.expectEqual(orders.count, 1, "진행 중 주문을 받아온다")
        await check.expectEqual(orders.first?.status, .pending, "체결 대기 상태")
        await check.expectEqual(
            transport.query(forPath: "/api/v1/orders")["status"], "OPEN",
            "status=OPEN 으로 조회한다"
        )
        await check.expectEqual(
            transport.requestCount(path: "/api/v1/orders"), 1,
            "OPEN 은 전량 반환이라 커서를 따라가지 않는다"
        )
        let query = transport.query(forPath: "/api/v1/orders")
        await check.expect(
            query["from"] == nil && query["to"] == nil,
            "진행 중 주문에는 기간 필터를 걸지 않는다 — 걸면 놓칠 여지만 생긴다"
        )
        await check.expect(
            query["cursor"] == nil && query["limit"] == nil,
            "OPEN 에서 무시되는 파라미터는 보내지 않는다"
        )
    }

    do {
        let (client, transport) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.openOrders)]
        ])
        await client.setAccountSeq(1)
        _ = try await client.openOrders(symbol: "005930")
        await check.expectEqual(
            transport.query(forPath: "/api/v1/orders")["symbol"], "005930",
            "종목 필터는 진행 중 주문에도 넘어간다"
        )
    }

    await check.group("OrderHistoryFilter — 종목별 필터")

    do {
        let orders = try decoder.decode(
            ApiEnvelope<OrderHistoryPage>.self,
            from: Data(Fixtures.mixedSymbolOrders.utf8)
        ).result.orders

        await check.expectEqual(
            OrderHistoryFilter.apply(orders, symbol: nil).count, orders.count,
            "필터가 없으면 전부 통과한다"
        )
        await check.expectEqual(
            OrderHistoryFilter.apply(orders, symbol: "").count, orders.count,
            "빈 문자열도 전체로 취급한다 — Picker 의 전체 항목이 빈 태그다"
        )
        await check.expectEqual(
            OrderHistoryFilter.apply(orders, symbol: "005930").map(\.orderId),
            ["S-1", "S-3"],
            "해당 종목만 남긴다"
        )
        await check.expectEqual(
            OrderHistoryFilter.apply(orders, symbol: "aapl").map(\.orderId),
            ["S-2"],
            "심볼 비교는 대소문자를 무시한다"
        )
        await check.expect(
            OrderHistoryFilter.apply(orders, symbol: "TSLA").isEmpty,
            "거래가 없는 종목은 빈 목록이다"
        )
        await check.expect(
            OrderHistoryFilter.apply(orders, symbol: "0059").isEmpty,
            "부분 일치로 걸리지 않는다 — 005930 이 0059 로 잡히면 안 된다"
        )
    }

    do {
        let orders = try decoder.decode(
            ApiEnvelope<OrderHistoryPage>.self,
            from: Data(Fixtures.mixedSymbolOrders.utf8)
        ).result.orders

        let symbols = OrderHistoryFilter.symbols(in: orders)
        await check.expectEqual(symbols.count, 2, "중복 없이 모은다")
        await check.expectEqual(
            symbols, ["AAPL", "005930"],
            "최근 거래 순으로 준다 — 방금 거래한 종목을 먼저 고르게 된다"
        )
        await check.expect(
            OrderHistoryFilter.symbols(in: []).isEmpty,
            "빈 목록에서는 선택지가 없다"
        )
    }

    do {
        // 필터를 서버에 넘길 때도 심볼이 그대로 실려야 한다.
        let query = OrderHistoryQuery(status: .closed, symbol: "005930")
        await check.expectEqual(
            TossEndpoint.orders(query).queryItems.first { $0.name == "symbol" }?.value,
            "005930",
            "종목 필터를 서버 조회에 넘길 수 있다"
        )
    }

    do {
        // 잘린 목록에서는 앱이 종목을 서버에 넘겨 다시 조회한다. 그 경로가 동작하는지 본다.
        let (client, transport) = await makeClient([
            "/api/v1/orders": [.init(body: Fixtures.closedOrdersPage2)]
        ])
        await client.setAccountSeq(1)
        _ = try await client.closedOrders(symbol: "AAPL")
        await check.expectEqual(
            transport.query(forPath: "/api/v1/orders")["symbol"], "AAPL",
            "closedOrders 가 종목을 쿼리로 넘긴다"
        )
    }
}
