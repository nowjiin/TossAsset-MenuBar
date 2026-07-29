#if DEBUG
import Foundation
import TossAssetMenuBarCore

/// 스크린샷용 예시 데이터.
///
/// `#if DEBUG` 안에 있으므로 **릴리스 빌드에는 포함되지 않는다.**
/// `./Scripts/build-app.sh debug` 로 만든 앱을 `TAMB_DEMO=1` 로 실행할 때만 쓰인다.
///
/// 실제 계좌 화면을 캡처하면 보유 종목·수량·평가금액·손익이 그대로 공개된다.
/// 가리기는 자릿수와 종목 수가 남고 매번 반복해야 하므로, 예시 데이터로 찍는다.
enum DemoData {
    /// 환경변수로만 켜진다. 기본값은 항상 꺼짐이다.
    ///
    ///   TAMB_DEMO=1           탭 화면 (예시 보유 종목)
    ///   TAMB_DEMO=onboarding  키 등록 화면
    private static var mode: String? {
        ProcessInfo.processInfo.environment["TAMB_DEMO"]
    }

    static var isEnabled: Bool {
        mode == "1" || mode == "onboarding"
    }

    static var showsOnboarding: Bool {
        mode == "onboarding"
    }

    /// 문서용 예시 IP 대역(RFC 5737). 실제 공용 IP 를 노출하지 않는다.
    static let publicIP = "203.0.113.7"

    /// 실제 설정·Keychain 을 건드리지 않도록 별도 UserDefaults 를 쓴다.
    static let defaultsSuiteName = "dev.tossassetmenubar.app.demo"

    static let watchlist = ["005930", "000660", "AAPL", "NVDA", "TSLA"]

    /// USD → KRW. 원화 환산과 비중 막대가 보이도록 값을 준다.
    static let usdToKrw = Decimal(1380)

    // 아래 숫자는 서로 맞아떨어지게 계산해 두었다.
    // 요약과 종목 목록이 어긋나면 화면을 자세히 보는 사람에게 바로 들킨다.
    //
    //   국내: 매입 10,100,000  평가 11,110,000  손익 +1,010,000
    //   해외: 매입      2,160  평가      2,476  손익     +316
    //   전체(환율 1380 환산): 매입 13,080,800  평가 14,526,880  손익 +1,446,080
    //   → 전체 수익률 1,446,080 / 13,080,800 = 0.1106

    static let holdings = HoldingsOverview(
        totalPurchaseAmount: CurrencyAmount(krw: "10100000", usd: "2160"),
        marketValue: OverviewMarketValue(
            amount: CurrencyAmount(krw: "11110000", usd: "2476"),
            amountAfterCost: CurrencyAmount(krw: "10860000", usd: "2457")
        ),
        profitLoss: OverviewProfitLoss(
            amount: CurrencyAmount(krw: "1010000", usd: "316"),
            amountAfterCost: CurrencyAmount(krw: "760000", usd: "297"),
            rate: "0.1106",
            rateAfterCost: "0.0894"
        ),
        dailyProfitLoss: OverviewDailyProfitLoss(
            amount: CurrencyAmount(krw: "150000", usd: "32"),
            rate: "0.0135"
        ),
        items: [
            item(
                symbol: "005930", name: "삼성전자", country: .kr, currency: .krw,
                quantity: "100", last: "72000", average: "65000",
                purchase: "6500000", value: "7200000", valueAfter: "7050000",
                profit: "700000", profitAfter: "550000", rate: "0.1077", rateAfter: "0.0846",
                daily: "100000", dailyRate: "0.0141",
                commission: "14400", tax: "135600"
            ),
            item(
                symbol: "000660", name: "SK하이닉스", country: .kr, currency: .krw,
                quantity: "20", last: "195500", average: "180000",
                purchase: "3600000", value: "3910000", valueAfter: "3810000",
                profit: "310000", profitAfter: "210000", rate: "0.0861", rateAfter: "0.0583",
                daily: "50000", dailyRate: "0.0130",
                commission: "7800", tax: "92000"
            ),
            item(
                symbol: "AAPL", name: "Apple Inc.", country: .us, currency: .usd,
                quantity: "10", last: "178.5", average: "155.3",
                purchase: "1553", value: "1785", valueAfter: "1771.43",
                profit: "232", profitAfter: "218.43", rate: "0.1494", rateAfter: "0.1406",
                daily: "25", dailyRate: "0.0142",
                commission: "13.57", tax: nil
            ),
            item(
                symbol: "NVDA", name: "NVIDIA", country: .us, currency: .usd,
                quantity: "5", last: "138.2", average: "121.4",
                purchase: "607", value: "691", valueAfter: "685.8",
                profit: "84", profitAfter: "78.8", rate: "0.1384", rateAfter: "0.1298",
                daily: "7", dailyRate: "0.0102",
                commission: "5.2", tax: nil
            ),
        ]
    )

    static let prices: [String: StockPrice] = [
        "005930": price("005930", "72000", .krw),
        "000660": price("000660", "195500", .krw),
        "AAPL": price("AAPL", "178.5", .usd),
        "NVDA": price("NVDA", "138.2", .usd),
        "TSLA": price("TSLA", "245.6", .usd),
    ]

    static let stockInfo: [String: StockInfo] = [
        "005930": info("005930", "삼성전자", "SamsungElec", .kospi, .krw),
        "000660": info("000660", "SK하이닉스", "SK hynix", .kospi, .krw),
        "AAPL": info("AAPL", "Apple Inc.", "Apple Inc.", .nasdaq, .usd),
        "NVDA": info("NVDA", "NVIDIA", "NVIDIA", .nasdaq, .usd),
        "TSLA": info("TSLA", "Tesla", "Tesla", .nasdaq, .usd),
    ]

    static let accounts = [
        Account(accountNo: "12345678901", accountSeq: 1, accountType: .brokerage)
    ]

    // MARK: - 조립 헬퍼

    private static func item(
        symbol: String, name: String, country: MarketCountry, currency: Currency,
        quantity: TossDecimal, last: TossDecimal, average: TossDecimal,
        purchase: TossDecimal, value: TossDecimal, valueAfter: TossDecimal,
        profit: TossDecimal, profitAfter: TossDecimal, rate: TossDecimal, rateAfter: TossDecimal,
        daily: TossDecimal, dailyRate: TossDecimal,
        commission: TossDecimal, tax: TossDecimal?
    ) -> HoldingsItem {
        HoldingsItem(
            symbol: symbol,
            name: name,
            marketCountry: country,
            currency: currency,
            quantity: quantity,
            lastPrice: last,
            averagePurchasePrice: average,
            marketValue: ItemMarketValue(
                purchaseAmount: purchase, amount: value, amountAfterCost: valueAfter
            ),
            profitLoss: ItemProfitLoss(
                amount: profit, amountAfterCost: profitAfter, rate: rate, rateAfterCost: rateAfter
            ),
            dailyProfitLoss: ItemDailyProfitLoss(amount: daily, rate: dailyRate),
            cost: ItemCost(commission: commission, tax: tax)
        )
    }

    private static func price(_ symbol: String, _ last: TossDecimal, _ currency: Currency) -> StockPrice {
        StockPrice(symbol: symbol, timestamp: Date(), lastPrice: last, currency: currency)
    }

    private static func info(
        _ symbol: String, _ name: String, _ english: String,
        _ market: StockMarket, _ currency: Currency
    ) -> StockInfo {
        StockInfo(
            symbol: symbol, name: name, englishName: english,
            market: market, status: .active, currency: currency
        )
    }
}
#endif
