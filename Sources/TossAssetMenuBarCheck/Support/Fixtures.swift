import Foundation
import TossAssetMenuBarCore

/// 문서의 응답 예시를 그대로 fixture 로 쓴다. API 스펙이 바뀌면 여기서 먼저 깨진다.
enum Fixtures {
    /// 국내 1종목 + 해외 1종목 보유.
    static let holdings = """
    {"result":{"totalPurchaseAmount":{"krw":"6500000","usd":"1553"},
    "marketValue":{"amount":{"krw":"7200000","usd":"1785"},"amountAfterCost":{"krw":"7050000","usd":"1771.43"}},
    "profitLoss":{"amount":{"krw":"700000","usd":"232"},"amountAfterCost":{"krw":"550000","usd":"218.43"},
    "rate":"0.1179","rateAfterCost":"0.0983"},
    "dailyProfitLoss":{"amount":{"krw":"100000","usd":"25"},"rate":"0.0141"},
    "items":[
    {"symbol":"005930","name":"삼성전자","marketCountry":"KR","currency":"KRW","quantity":"100",
    "lastPrice":"72000","averagePurchasePrice":"65000",
    "marketValue":{"purchaseAmount":"6500000","amount":"7200000","amountAfterCost":"7050000"},
    "profitLoss":{"amount":"700000","amountAfterCost":"550000","rate":"0.1077","rateAfterCost":"0.0846"},
    "dailyProfitLoss":{"amount":"100000","rate":"0.0141"},
    "cost":{"commission":"14400","tax":"135600"}},
    {"symbol":"AAPL","name":"Apple Inc.","marketCountry":"US","currency":"USD","quantity":"10",
    "lastPrice":"178.5","averagePurchasePrice":"155.3",
    "marketValue":{"purchaseAmount":"1553","amount":"1785","amountAfterCost":"1771.43"},
    "profitLoss":{"amount":"232","amountAfterCost":"218.43","rate":"0.1494","rateAfterCost":"0.1406"},
    "dailyProfitLoss":{"amount":"25","rate":"0.0142"},
    "cost":{"commission":"13.57","tax":null}}
    ]}}
    """

    /// 보유 종목이 없는 계좌. 해외 종목이 없으면 `usd` 는 아예 null 로 온다.
    static let emptyHoldings = """
    {"result":{"totalPurchaseAmount":{"krw":"0","usd":null},
    "marketValue":{"amount":{"krw":"0","usd":null},"amountAfterCost":{"krw":"0","usd":null}},
    "profitLoss":{"amount":{"krw":"0","usd":null},"amountAfterCost":{"krw":"0","usd":null},"rate":"0","rateAfterCost":"0"},
    "dailyProfitLoss":{"amount":{"krw":"0","usd":null},"rate":"0"},"items":[]}}
    """

    static let token = #"{"access_token":"eyJhbGciOi.stub","token_type":"Bearer","expires_in":3600}"#

    static let accounts = #"{"result":[{"accountNo":"12345678901","accountSeq":1,"accountType":"BROKERAGE"}]}"#

    static let exchangeRate = """
    {"result":{"baseCurrency":"USD","quoteCurrency":"KRW","rate":"1380.5","midRate":"1375",
    "basisPoint":"40","rateChangeType":"UP",
    "validFrom":"2026-03-25T09:30:00+09:00","validUntil":"2026-03-25T09:31:00+09:00"}}
    """

    /// 국내 정규장 09:00~15:30 KST. 전날은 휴장, 다음날은 정규장만.
    static let krCalendar = """
    {"result":{
    "today":{"date":"2026-03-25","integrated":{
    "preMarket":{"startTime":"2026-03-25T08:00:00+09:00","endTime":"2026-03-25T08:50:00+09:00"},
    "regularMarket":{"startTime":"2026-03-25T09:00:00+09:00","singlePriceAuctionStartTime":"2026-03-25T15:20:00+09:00","endTime":"2026-03-25T15:30:00+09:00"},
    "afterMarket":{"startTime":"2026-03-25T16:00:00+09:00","endTime":"2026-03-25T20:00:00+09:00"}}},
    "previousBusinessDay":{"date":"2026-03-24","integrated":null},
    "nextBusinessDay":{"date":"2026-03-26","integrated":{
    "preMarket":null,
    "regularMarket":{"startTime":"2026-03-26T09:00:00+09:00","endTime":"2026-03-26T15:30:00+09:00"},
    "afterMarket":null}}}}
    """

    /// 미국 정규장 22:30~다음날 05:00 KST. 자정을 넘기는 경계가 여기서 나온다.
    static let usCalendar = """
    {"result":{
    "today":{"date":"2026-03-25","dayMarket":null,"preMarket":null,
    "regularMarket":{"startTime":"2026-03-25T22:30:00+09:00","endTime":"2026-03-26T05:00:00+09:00"},
    "afterMarket":null},
    "previousBusinessDay":{"date":"2026-03-24","dayMarket":null,"preMarket":null,"regularMarket":null,"afterMarket":null},
    "nextBusinessDay":{"date":"2026-03-26","dayMarket":null,"preMarket":null,"regularMarket":null,"afterMarket":null}}}
    """
}

/// ISO 8601 문자열을 `Date` 로. 검증에서 특정 시점을 지정할 때 쓴다.
func kst(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

extension Fixtures {
    /// 종료된 주문 — 문서 예시 `completedWithNextPage` 그대로. 다음 페이지가 있다.
    static let closedOrdersPage1 = """
    {"result":{"orders":[
    {"orderId":"ORD-1","symbol":"005930","side":"BUY","orderType":"LIMIT","timeInForce":"DAY",
    "status":"FILLED","price":"70000","quantity":"10","orderAmount":null,"currency":"KRW",
    "orderedAt":"2026-03-28T09:30:00+09:00","canceledAt":null,
    "execution":{"filledQuantity":"10","averageFilledPrice":"70000","filledAmount":"700000",
    "commission":"1400","tax":"0","filledAt":"2026-03-28T09:31:15+09:00","settlementDate":"2026-03-30"}}
    ],"nextCursor":"CURSOR-2","hasNext":true}}
    """

    /// 두 번째 페이지. 부분 체결 후 취소된 해외 주문 — 상태만 보고 "체결 없음" 이라 단정하면 틀린다.
    static let closedOrdersPage2 = """
    {"result":{"orders":[
    {"orderId":"ORD-2","symbol":"AAPL","side":"SELL","orderType":"MARKET","timeInForce":"DAY",
    "status":"CANCELED","price":null,"quantity":"5","orderAmount":null,"currency":"USD",
    "orderedAt":"2026-03-27T22:30:00+09:00","canceledAt":"2026-03-27T22:35:00+09:00",
    "execution":{"filledQuantity":"2","averageFilledPrice":"185.25","filledAmount":"370.5",
    "commission":"0.66","tax":null,"filledAt":"2026-03-27T22:31:00+09:00","settlementDate":"2026-03-31"}}
    ],"nextCursor":null,"hasNext":false}}
    """

    /// 미체결 주문 — `filledQuantity` 를 뺀 execution 전부가 null 이다.
    static let openOrders = """
    {"result":{"orders":[
    {"orderId":"ORD-3","symbol":"005930","side":"BUY","orderType":"LIMIT","timeInForce":"DAY",
    "status":"PENDING","price":"70000","quantity":"10","orderAmount":null,"currency":"KRW",
    "orderedAt":"2026-03-29T09:30:00+09:00","canceledAt":null,
    "execution":{"filledQuantity":"0","averageFilledPrice":null,"filledAmount":null,
    "commission":null,"tax":null,"filledAt":null,"settlementDate":null}}
    ],"nextCursor":null,"hasNext":false}}
    """

    /// 문서에 없는 상태·주문유형. unknown 값을 흡수해야 디코딩이 깨지지 않는다.
    static let ordersWithUnknownEnums = """
    {"result":{"orders":[
    {"orderId":"ORD-4","symbol":"005930","side":"SHORT_SELL","orderType":"TRAILING_STOP",
    "timeInForce":"IOC","status":"SOMETHING_NEW","price":"70000","quantity":"1","orderAmount":null,
    "currency":"KRW","orderedAt":"2026-03-28T09:30:00+09:00","canceledAt":null,
    "execution":{"filledQuantity":"0","averageFilledPrice":null,"filledAmount":null,
    "commission":null,"tax":null,"filledAt":null,"settlementDate":null}}
    ],"nextCursor":null,"hasNext":false}}
    """

    static let emptyOrders = """
    {"result":{"orders":[],"nextCursor":null,"hasNext":false}}
    """

    /// 두 종목이 섞인 목록. 같은 종목이 두 번 나오고, 체결 시각 순서가 주문 순서와 다르다.
    /// AAPL(03-28) 이 005930(03-27, 03-26) 보다 최근이다.
    static let mixedSymbolOrders = """
    {"result":{"orders":[
    {"orderId":"S-1","symbol":"005930","side":"BUY","orderType":"LIMIT","timeInForce":"DAY",
    "status":"FILLED","price":"70000","quantity":"1","orderAmount":null,"currency":"KRW",
    "orderedAt":"2026-03-27T09:30:00+09:00","canceledAt":null,
    "execution":{"filledQuantity":"1","averageFilledPrice":"70000","filledAmount":"70000",
    "commission":"105","tax":"0","filledAt":"2026-03-27T09:31:00+09:00","settlementDate":"2026-03-31"}},
    {"orderId":"S-2","symbol":"AAPL","side":"SELL","orderType":"LIMIT","timeInForce":"DAY",
    "status":"FILLED","price":"185","quantity":"2","orderAmount":null,"currency":"USD",
    "orderedAt":"2026-03-28T22:30:00+09:00","canceledAt":null,
    "execution":{"filledQuantity":"2","averageFilledPrice":"185","filledAmount":"370",
    "commission":"0.66","tax":"0","filledAt":"2026-03-28T22:31:00+09:00","settlementDate":"2026-04-01"}},
    {"orderId":"S-3","symbol":"005930","side":"SELL","orderType":"MARKET","timeInForce":"DAY",
    "status":"FILLED","price":null,"quantity":"1","orderAmount":null,"currency":"KRW",
    "orderedAt":"2026-03-26T09:30:00+09:00","canceledAt":null,
    "execution":{"filledQuantity":"1","averageFilledPrice":"71000","filledAmount":"71000",
    "commission":"106","tax":"163","filledAt":"2026-03-26T09:31:00+09:00","settlementDate":"2026-03-30"}}
    ],"nextCursor":null,"hasNext":false}}
    """
}

/// 오류 매핑 검증용 envelope 본문.
func apiErrorBody(_ code: String, _ message: String = "") -> ApiErrorBody {
    ApiErrorBody(requestId: "01HXYZ", code: code, message: message)
}

/// 토큰 스텁이 미리 꽂힌 클라이언트. 모든 조회 검증이 이걸로 시작한다.
func makeClient(
    _ stubs: [String: [StubTransport.Stub]]
) async -> (TossAPIClient, StubTransport) {
    var withToken = stubs
    withToken["/oauth2/token"] = [.init(body: Fixtures.token)]
    let transport = StubTransport(stubs: withToken)
    let client = TossAPIClient(transport: transport)
    await client.setCredentials(TossCredentials(clientID: "id", clientSecret: "secret"))
    return (client, transport)
}
