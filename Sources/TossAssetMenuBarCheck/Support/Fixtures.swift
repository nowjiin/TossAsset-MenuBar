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
