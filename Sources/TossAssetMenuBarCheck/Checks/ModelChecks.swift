import Foundation
import TossAssetMenuBarCore

/// 응답 디코딩. API 스펙과 모델이 어긋나면 여기서 먼저 깨진다.
func runModelChecks(_ check: CheckHarness) async throws {
    let decoder = TossJSON.decoder()

    // MARK: decimal 파싱

    await check.group("TossDecimal — 문자열 decimal 파싱")

    do {
        let value = try decoder.decode(TossDecimal.self, from: Data(#""0.1179""#.utf8))
        await check.expectEqual(value.value, Decimal(string: "0.1179")!, "비율 문자열을 Decimal 로 파싱한다")
    }
    do {
        let value = try decoder.decode(TossDecimal.self, from: Data(#""7200000""#.utf8))
        await check.expectEqual(value.value, Decimal(7_200_000), "정수 금액 문자열을 파싱한다")
    }
    // Double 로 파싱하면 0.1 + 0.2 처럼 오차가 생기는 값이 정확히 유지되는지 확인한다.
    do {
        let a = try decoder.decode(TossDecimal.self, from: Data(#""1771.43""#.utf8))
        let b = try decoder.decode(TossDecimal.self, from: Data(#""1771.42""#.utf8))
        await check.expectEqual(a.value - b.value, Decimal(string: "0.01")!, "소수 연산에서 오차가 생기지 않는다")
    }
    await check.expectThrows("숫자가 아닌 문자열은 디코딩 실패로 처리한다") {
        _ = try decoder.decode(TossDecimal.self, from: Data(#""not-a-number""#.utf8))
    }

    // MARK: 보유 주식 디코딩

    await check.group("HoldingsOverview — 문서 예시 디코딩")

    do {
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.holdings.utf8)).result

        await check.expectEqual(overview.items.count, 2, "보유 종목 2건을 읽는다")
        await check.expectEqual(overview.profitLoss.rate.value, Decimal(string: "0.1179")!, "전체 손익률을 그대로 읽는다")
        await check.expectEqual(overview.marketValue.amount.krw.value, Decimal(7_200_000), "국내 평가금액 합산")
        await check.expectEqual(overview.marketValue.amount.usd?.value, Decimal(1785), "해외 평가금액 합산")

        let samsung = overview.items[0]
        await check.expectEqual(samsung.name, "삼성전자", "종목명을 읽는다")
        await check.expectEqual(samsung.currency, Currency.krw, "거래 통화를 읽는다")
        await check.expectEqual(samsung.marketCountry, MarketCountry.kr, "시장 국가를 읽는다")
        await check.expect(samsung.cost.tax != nil, "국내 종목은 세금이 있다")

        let apple = overview.items[1]
        await check.expectEqual(apple.currency, Currency.usd, "해외 종목 통화는 USD")
        await check.expect(apple.cost.tax == nil, "tax 가 null 이면 nil 로 들어온다")
        await check.expectEqual(apple.lastPrice.value, Decimal(string: "178.5")!, "소수 가격을 유지한다")

        // 공제 후 값은 토스가 계산해 내려준다. 앱이 세율을 추정하지 않는다는 걸 고정한다.
        await check.expectEqual(
            overview.profitLoss.rateAfterCost.value,
            Decimal(string: "0.0983")!,
            "공제 후 손익률은 응답 값을 그대로 읽는다"
        )
        await check.expectEqual(
            overview.marketValue.amountAfterCost.krw.value,
            Decimal(7_050_000),
            "공제 후 평가금액도 응답 값이다"
        )
    }

    do {
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.emptyHoldings.utf8)).result
        await check.expect(overview.items.isEmpty, "보유 종목이 없으면 빈 배열이다")
        await check.expect(overview.marketValue.amount.usd == nil, "해외 종목이 없으면 usd 는 nil 이다")
    }

    // MARK: 통화별 합산

    await check.group("CurrencyAmount — 통화별 합산은 직접 더하지 않는다")

    do {
        let amount = CurrencyAmount(krw: "7200000", usd: "1785")
        let rate = Decimal(1380)
        await check.expectEqual(
            amount.totalInKRW(usdToKrw: rate),
            Decimal(7_200_000) + Decimal(1785) * Decimal(1380),
            "환율을 알면 원화로 환산해 합산한다"
        )
        await check.expectEqual(
            amount.totalInKRW(usdToKrw: nil),
            Decimal(7_200_000),
            "환율을 모르면 국내분만 반환한다"
        )
    }

    // MARK: unknown enum 흡수

    await check.group("OpenEnum — 문서가 요구하는 unknown 값 허용")

    do {
        let currency = try decoder.decode(Currency.self, from: Data(#""JPY""#.utf8))
        await check.expectEqual(currency, Currency.other("JPY"), "모르는 통화는 .other 로 흡수한다")

        let accountType = try decoder.decode(AccountType.self, from: Data(#""FUTURE_TYPE""#.utf8))
        await check.expectEqual(accountType, AccountType.other("FUTURE_TYPE"), "모르는 계좌 유형도 디코딩이 깨지지 않는다")

        let known = try decoder.decode(AccountType.self, from: Data(#""BROKERAGE""#.utf8))
        await check.expectEqual(known, AccountType.brokerage, "알려진 값은 정상 매핑된다")
    }
}
