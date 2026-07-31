import Foundation
import TossAssetMenuBarCore

/// 화면 규칙을 결정하는 도메인 계산: 권역 집계, 장 운영 시간, 입력 검증.
func runDomainChecks(_ check: CheckHarness) async throws {
    let decoder = TossJSON.decoder()

    // MARK: 국내/해외/전체 집계

    await check.group("RegionBreakdown — 국내·해외·전체 집계")

    do {
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.holdings.utf8)).result
        let rate = Decimal(1380)
        let breakdown = RegionBreakdown(overview: overview, usdToKrw: rate, showAfterCost: false)

        // 통화 버킷이 곧 국내/해외 구분이다.
        await check.expectEqual(breakdown.domestic.itemCount, 1, "국내 종목 수를 센다")
        await check.expectEqual(breakdown.overseas.itemCount, 1, "해외 종목 수를 센다")
        await check.expectEqual(breakdown.total.itemCount, 2, "전체 종목 수를 센다")

        await check.expectEqual(breakdown.domestic.marketValue, Decimal(7_200_000), "국내 평가금액은 원 기준")
        await check.expectEqual(breakdown.overseas.marketValue, Decimal(1785), "해외 평가금액은 달러 기준")

        // 권역별 수익률은 API 가 주지 않아 직접 계산한다: 손익 ÷ 투자원금
        await check.expectEqual(
            breakdown.domestic.rate,
            Decimal(700_000) / Decimal(6_500_000),
            "국내 수익률은 손익÷원금으로 계산한다"
        )
        await check.expectEqual(
            breakdown.overseas.rate,
            Decimal(232) / Decimal(1553),
            "해외 수익률도 같은 통화 안에서 계산한다"
        )
        // 전체는 API 가 원화 환산 기준으로 준 값을 그대로 써야 한다. 직접 계산하면 값이 달라진다.
        await check.expectEqual(
            breakdown.total.rate,
            Decimal(string: "0.1179")!,
            "전체 수익률은 API 값을 그대로 쓴다"
        )

        // 비중은 원화 환산 후에만 비교할 수 있다.
        await check.expectEqual(
            breakdown.overseas.marketValueInKRW,
            Decimal(1785) * rate,
            "해외 평가금액을 원화로 환산한다"
        )
        let totalInKRW = Decimal(7_200_000) + Decimal(1785) * rate
        await check.expectEqual(
            breakdown.domestic.share,
            Decimal(7_200_000) / totalInKRW,
            "국내 비중"
        )
        await check.expectEqual(
            breakdown.overseas.share,
            (Decimal(1785) * rate) / totalInKRW,
            "해외 비중"
        )
        if let domesticShare = breakdown.domestic.share, let overseasShare = breakdown.overseas.share {
            // 나눗셈 결과가 순환소수라 정확히 1 이 되지는 않는다. 표시 단계에서 반올림되므로
            // 오차가 무시할 수준인지만 본다.
            let sum = domesticShare + overseasShare
            await check.expect(
                abs(sum - 1) < Decimal(string: "0.0000001")!,
                "두 비중의 합은 1 이다 (실제 \(sum))"
            )
        }

        await check.expect(!breakdown.domestic.isEmpty, "국내 보유가 있다")
        await check.expect(!breakdown.overseas.isEmpty, "해외 보유가 있다")
    }

    do {
        // 해외 보유가 있는데 환율을 모르면 비중을 낼 수 없다. 0 이나 국내분만으로 속여선 안 된다.
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.holdings.utf8)).result
        let breakdown = RegionBreakdown(overview: overview, usdToKrw: nil, showAfterCost: false)

        await check.expect(breakdown.overseas.marketValueInKRW == nil, "환율이 없으면 해외 원화 환산은 nil")
        await check.expect(breakdown.domestic.share == nil, "환율이 없으면 국내 비중도 낼 수 없다")
        await check.expect(breakdown.overseas.share == nil, "환율이 없으면 해외 비중도 낼 수 없다")
        // 통화 기준 금액과 권역별 수익률은 환율과 무관하므로 그대로 나와야 한다.
        await check.expectEqual(breakdown.overseas.marketValue, Decimal(1785), "달러 금액은 환율 없이도 보여준다")
        await check.expectEqual(
            breakdown.overseas.rate,
            Decimal(232) / Decimal(1553),
            "해외 수익률은 환율과 무관하다"
        )
    }

    do {
        // 국내만 보유한 계좌. usd 가 전부 null 로 온다.
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.emptyHoldings.utf8)).result
        let breakdown = RegionBreakdown(overview: overview, usdToKrw: nil, showAfterCost: false)

        await check.expect(breakdown.overseas.isEmpty, "해외 보유가 없으면 비어 있다고 표시한다")
        await check.expect(breakdown.overseas.rate == nil, "원금이 0 이면 수익률은 정의되지 않는다")
        await check.expect(breakdown.domestic.rate == nil, "국내도 원금이 0 이면 nil 이다")
        // 해외가 없으면 환율 없이도 원화 합계를 낼 수 있다.
        await check.expect(breakdown.total.marketValueInKRW != nil, "해외가 없으면 환율 없이 합계를 낸다")
    }

    do {
        // 공제 후로 전환하면 응답의 다른 필드를 골라 써야 한다.
        // 앱이 세금을 계산하는 게 아니라 토스가 준 값을 고르는 것이다.
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.holdings.utf8)).result
        let breakdown = RegionBreakdown(overview: overview, usdToKrw: Decimal(1380), showAfterCost: true)

        await check.expectEqual(breakdown.domestic.marketValue, Decimal(7_050_000), "공제 후 국내 평가금액")
        await check.expectEqual(
            breakdown.domestic.rate,
            Decimal(550_000) / Decimal(6_500_000),
            "공제 후 국내 수익률"
        )
        await check.expectEqual(
            breakdown.total.rate,
            Decimal(string: "0.0983")!,
            "공제 후 전체 수익률도 API 값을 쓴다"
        )
    }

    // MARK: 권역 선택과 종목 필터

    await check.group("HoldingsRegion — 권역 선택과 종목 필터")

    do {
        let overview = try decoder
            .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.holdings.utf8)).result
        let samsung = overview.items[0]
        let apple = overview.items[1]

        // 목록 필터는 요약 합산과 같은 잣대(거래 통화)를 써야 한다.
        // 다른 기준을 쓰면 "국내 3종목" 인데 목록에 2개만 나오는 식으로 어긋난다.
        await check.expect(HoldingsRegion.domestic.contains(samsung), "원화 종목은 국내에 포함된다")
        await check.expect(!HoldingsRegion.domestic.contains(apple), "달러 종목은 국내에서 제외된다")
        await check.expect(HoldingsRegion.overseas.contains(apple), "달러 종목은 해외에 포함된다")
        await check.expect(!HoldingsRegion.overseas.contains(samsung), "원화 종목은 해외에서 제외된다")
        await check.expect(HoldingsRegion.total.contains(samsung), "전체는 모두 포함한다")
        await check.expect(HoldingsRegion.total.contains(apple), "전체는 통화를 가리지 않는다")

        // 필터로 센 개수와 요약의 종목 수가 일치해야 한다.
        let breakdown = RegionBreakdown(overview: overview, usdToKrw: Decimal(1380), showAfterCost: false)
        for region in HoldingsRegion.displayOrder {
            await check.expectEqual(
                overview.items.count { region.contains($0) },
                breakdown.summary(for: region).itemCount,
                "\(region.label): 목록 필터 개수와 요약 종목 수가 같다"
            )
        }

        await check.expectEqual(
            HoldingsRegion.displayOrder,
            [.total, .domestic, .overseas],
            "세그먼트는 전체·국내·해외 순으로 놓는다"
        )
        await check.expectEqual(HoldingsRegion.domestic.marketCountry, MarketCountry.kr, "국내는 KR 시장의 개장 여부를 본다")
        await check.expectEqual(HoldingsRegion.overseas.marketCountry, MarketCountry.us, "해외는 US 시장의 개장 여부를 본다")
        await check.expect(HoldingsRegion.total.marketCountry == nil, "전체는 특정 시장에 매이지 않는다")

        // summary(for:) 가 올바른 권역을 돌려주는지.
        await check.expectEqual(breakdown.summary(for: .domestic).marketValue, Decimal(7_200_000), "국내 요약")
        await check.expectEqual(breakdown.summary(for: .overseas).marketValue, Decimal(1785), "해외 요약")
        await check.expectEqual(
            breakdown.summary(for: .total).rate,
            Decimal(string: "0.1179")!,
            "전체 요약"
        )
    }

    // MARK: 장 운영 시간

    await check.group("MarketHours — 폐장 중 폴링 중단 판단")

    do {
        let kr = try decoder
            .decode(ApiEnvelope<KrMarketCalendar>.self, from: Data(Fixtures.krCalendar.utf8)).result
        let us = try decoder
            .decode(ApiEnvelope<UsMarketCalendar>.self, from: Data(Fixtures.usCalendar.utf8)).result
        let hours = MarketHours(kr: kr, us: us)

        await check.expectEqual(kr.today.date, "2026-03-25", "date 는 문자열로 읽는다 (date-time 이 아니다)")
        await check.expect(kr.previousBusinessDay.integrated == nil, "휴장일은 integrated 가 null 이다")
        await check.expect(!hours.isUnknown, "캘린더를 받았으면 판단할 수 있다")

        await check.expect(hours.isAnyMarketOpen(at: kst("2026-03-25T10:00:00+09:00")), "국내 정규장 중에는 열려 있다")
        await check.expect(hours.isAnyMarketOpen(at: kst("2026-03-25T08:30:00+09:00")), "국내 프리마켓 중에도 열려 있다")
        await check.expect(!hours.isAnyMarketOpen(at: kst("2026-03-25T15:45:00+09:00")), "정규장과 애프터마켓 사이는 닫혀 있다")
        await check.expect(!hours.isAnyMarketOpen(at: kst("2026-03-25T21:00:00+09:00")), "국내 애프터마켓 종료 후 미국 개장 전은 닫혀 있다")

        // 미국 정규장은 KST 로 자정을 넘는다. 여기가 경계 판정이 틀리기 쉬운 지점이다.
        await check.expect(hours.isAnyMarketOpen(at: kst("2026-03-25T23:00:00+09:00")), "미국 정규장 중에는 열려 있다")
        await check.expect(hours.isAnyMarketOpen(at: kst("2026-03-26T03:00:00+09:00")), "자정을 넘긴 미국 정규장도 열려 있다")
        await check.expect(!hours.isAnyMarketOpen(at: kst("2026-03-26T06:00:00+09:00")), "미국 정규장 종료 후는 닫혀 있다")

        // 다음 개장은 시각뿐 아니라 어느 시장인지도 알아야 한다. 표시 타임존이 달라진다.
        let afterKrClose = hours.nextOpening(after: kst("2026-03-25T21:00:00+09:00"))
        await check.expectEqual(afterKrClose?.date, kst("2026-03-25T22:30:00+09:00"), "폐장 중이면 다음 개장은 미국 정규장이다")
        await check.expectEqual(afterKrClose?.market, MarketCountry.us, "그 개장은 미국 시장으로 표시된다")
        await check.expectEqual(afterKrClose?.displayTimeZone, MarketTimeZone.usEastern, "미국 개장은 미국 동부 시간으로 보여준다")

        let afterUsClose = hours.nextOpening(after: kst("2026-03-26T06:00:00+09:00"))
        await check.expectEqual(afterUsClose?.date, kst("2026-03-26T09:00:00+09:00"), "다음 영업일 국내 정규장을 찾아낸다")
        await check.expectEqual(afterUsClose?.market, MarketCountry.kr, "그 개장은 국내 시장이다")
        await check.expectEqual(afterUsClose?.displayTimeZone, MarketTimeZone.kst, "국내 개장은 KST 로 보여준다")

        // 어느 시장이 지금 열려 있는지 구분해야 권역별로 장중/폐장을 따로 찍을 수 있다.
        await check.expectEqual(
            hours.openMarkets(at: kst("2026-03-25T10:00:00+09:00")),
            [MarketCountry.kr],
            "국내 정규장 중에는 국내만 열려 있다"
        )
        await check.expectEqual(
            hours.openMarkets(at: kst("2026-03-25T23:00:00+09:00")),
            [MarketCountry.us],
            "미국 정규장 중에는 미국만 열려 있다"
        )
        await check.expect(
            hours.openMarkets(at: kst("2026-03-25T21:00:00+09:00")).isEmpty,
            "둘 다 닫힌 시간에는 빈 배열이다"
        )
    }

    do {
        // 캘린더를 못 받은 상태에서 폐장으로 단정하면 앱이 아무것도 갱신하지 않게 된다.
        let hours = MarketHours(kr: nil, us: nil)
        await check.expect(hours.isUnknown, "둘 다 실패하면 판단 불가로 표시한다")
        await check.expect(hours.nextOpening() == nil, "판단 불가일 때 다음 개장 시각은 없다")
    }

    // MARK: 입력 검증

    await check.group("SymbolValidator — 문서가 허용하는 문자만 통과")

    await check.expectEqual(SymbolValidator.normalize(" aapl "), "AAPL", "공백을 제거하고 대문자로 정규화한다")
    await check.expect(SymbolValidator.isValid("005930"), "국내 6자리 숫자 심볼")
    await check.expect(SymbolValidator.isValid("BRK.B"), "점이 들어간 티커")
    await check.expect(SymbolValidator.isValid("BF-B"), "하이픈이 들어간 티커")
    await check.expect(!SymbolValidator.isValid("삼성전자"), "한글 종목명은 심볼이 아니다")
    await check.expect(!SymbolValidator.isValid(""), "빈 문자열은 거부한다")
    await check.expect(!SymbolValidator.isValid("AAPL; DROP"), "구분자·공백이 섞이면 거부한다")

    await check.group("PublicIPProvider — 외부 응답 형식 검증")

    let ipProvider = PublicIPProvider()
    await check.expect(ipProvider.isIPv4("203.0.113.7"), "정상 IPv4")
    await check.expect(!ipProvider.isIPv4("203.0.113"), "옥텟이 부족하면 거부")
    await check.expect(!ipProvider.isIPv4("203.0.113.999"), "255 초과 옥텟은 거부")
    await check.expect(!ipProvider.isIPv4("<html>error</html>"), "HTML 응답을 IP 로 오인하지 않는다")

    await check.group("KeychainStore — 프롬프트에 뜨는 이름")

    // 이 문자열이 Keychain 접근 프롬프트에 그대로 표시된다.
    // Bundle Identifier 를 바꿀 때 같이 치환되면 사용자에게 역순 도메인이 노출되므로 고정한다.
    await check.expectEqual(KeychainStore.defaultService, "TossAsset-MenuBar", "사람이 읽는 이름을 쓴다")
    await check.expect(
        !KeychainStore.defaultService.contains("."),
        "역순 도메인 형식이 아니어야 한다"
    )
}

func runHoldingOrderChecks(_ check: CheckHarness) async throws {
    let decoder = TossJSON.decoder()
    let all = try decoder
        .decode(ApiEnvelope<HoldingsOverview>.self, from: Data(Fixtures.holdings.utf8))
        .result.items

    await check.group("HoldingOrder — 저장된 순서 적용")

    await check.expectEqual(
        HoldingOrder.apply(all, order: []).map(\.symbol),
        all.map(\.symbol),
        "순서가 비어 있으면 API 순서를 그대로 쓴다 — 옮긴 적 없는 사용자에게 임의 순서를 강요하지 않는다"
    )
    await check.expectEqual(
        HoldingOrder.apply(all, order: ["AAPL", "005930"]).map(\.symbol),
        ["AAPL", "005930"],
        "저장된 순서대로 정렬한다"
    )
    await check.expectEqual(
        HoldingOrder.apply(all, order: ["AAPL"]).map(\.symbol),
        ["AAPL", "005930"],
        "순서에 없는 종목은 뒤에 붙는다 — 새로 산 종목이 맨 위를 밀어내면 안 된다"
    )
    await check.expectEqual(
        HoldingOrder.apply(all, order: ["TSLA", "NVDA"]).map(\.symbol),
        all.map(\.symbol),
        "보유하지 않는 심볼만 있으면 원래 순서가 유지된다"
    )

    await check.group("HoldingOrder — 끌어 옮기기")

    let symbols = ["A", "B", "C", "D"]
    await check.expectEqual(
        HoldingOrder.moving(symbols, from: IndexSet(integer: 0), to: 2),
        ["B", "A", "C", "D"],
        "위에서 아래로 한 칸"
    )
    await check.expectEqual(
        HoldingOrder.moving(symbols, from: IndexSet(integer: 3), to: 0),
        ["D", "A", "B", "C"],
        "맨 아래를 맨 위로"
    )
    await check.expectEqual(
        HoldingOrder.moving(symbols, from: IndexSet(integer: 0), to: 4),
        ["B", "C", "D", "A"],
        "맨 위를 맨 아래로 — destination 은 삽입 지점이라 개수와 같을 수 있다"
    )
    await check.expectEqual(
        HoldingOrder.moving(symbols, from: IndexSet([0, 1]), to: 4),
        ["C", "D", "A", "B"],
        "여러 개를 한 번에 옮겨도 상대 순서를 지킨다"
    )
    await check.expectEqual(
        HoldingOrder.moving(symbols, from: IndexSet(integer: 1), to: 1),
        symbols,
        "제자리에 놓으면 그대로다"
    )
    await check.expectEqual(
        HoldingOrder.moving(symbols, from: IndexSet(integer: 9), to: 0),
        symbols,
        "범위를 벗어난 인덱스는 무시한다"
    )

    await check.group("HoldingOrder — 부분 집합만 옮겼을 때")

    do {
        // 국내 세그먼트에서 두 종목만 보이는 상태. 화면에 없던 해외 종목의 자리가 흔들리면 안 된다.
        let stored = ["005930", "AAPL", "000660", "NVDA"]
        let visible = ["005930", "000660"]
        let moved = HoldingOrder.applyingMove(
            to: stored, visible: visible, from: IndexSet(integer: 1), to: 0
        )
        await check.expectEqual(
            moved, ["000660", "AAPL", "005930", "NVDA"],
            "보이던 자리에만 새 순서를 끼워 넣는다 — AAPL·NVDA 위치는 그대로다"
        )
    }

    do {
        let moved = HoldingOrder.applyingMove(
            to: [], visible: ["A", "B", "C"], from: IndexSet(integer: 2), to: 0
        )
        await check.expectEqual(
            moved, ["C", "A", "B"],
            "저장된 순서가 없으면 보이는 목록으로 새로 만든다"
        )
    }

    do {
        // 새로 산 종목은 저장된 순서에 없다. 옮기기 전에 기준 배열에 편입돼야 한다.
        let moved = HoldingOrder.applyingMove(
            to: ["A"], visible: ["A", "NEW"], from: IndexSet(integer: 1), to: 0
        )
        await check.expectEqual(
            moved, ["NEW", "A"],
            "순서에 없던 종목도 옮길 수 있다"
        )
    }

    await check.group("HoldingOrder — 매도한 종목 정리")

    await check.expectEqual(
        HoldingOrder.pruned(["A", "B", "C"], keeping: ["A", "C"]),
        ["A", "C"],
        "보유하지 않는 종목은 순서에서 덜어낸다"
    )
    await check.expectEqual(
        HoldingOrder.pruned(["A", "B"], keeping: ["A", "B", "C"]),
        ["A", "B"],
        "순서에 없는 보유 종목을 억지로 넣지 않는다 — 적용 단계에서 뒤에 붙는다"
    )
}

func runDailyChangeChecks(_ check: CheckHarness) async throws {
    let decoder = TossJSON.decoder()

    await check.group("DailyChange — 종목 자체의 등락률")

    // 응답 순서를 믿지 않는다. 문서에 정렬 규칙이 없다.
    let body = """
    {"result":{"candles":[
    {"timestamp":"2026-07-29T00:00:00+09:00","openPrice":"1","highPrice":"1","lowPrice":"1",
     "closePrice":"240000","volume":"1","currency":"KRW"},
    {"timestamp":"2026-07-31T00:00:00+09:00","openPrice":"1","highPrice":"1","lowPrice":"1",
     "closePrice":"250000","volume":"1","currency":"KRW"},
    {"timestamp":"2026-07-30T00:00:00+09:00","openPrice":"1","highPrice":"1","lowPrice":"1",
     "closePrice":"248000","volume":"1","currency":"KRW"}
    ],"nextBefore":null}}
    """
    let candles = try decoder
        .decode(ApiEnvelope<CandleResponse>.self, from: Data(body.utf8)).result.candles

    await check.expectEqual(candles.count, 3, "일봉을 디코딩한다")

    // 오늘이 7/31 이라고 두고 판단한다. 봉은 7/29·7/30·7/31 세 개다.
    let today = kst("2026-07-31T14:00:00+09:00")
    let yesterdayOnly = candles.filter {
        $0.timestamp < kst("2026-07-31T00:00:00+09:00")
    }

    // 오늘 장이 시작된 경우 — 장중이든 폐장 후든 같다. 기준가는 오늘보다 앞선 최근 봉이다.
    await check.expectEqual(
        DailyChange.basePrice(from: candles, now: today, zone: .kst, hasSessionStartedToday: true),
        "248000",
        "오늘 봉이 있으면 그 앞(어제)이 기준가다"
    )
    // 실제로 겪은 버그 두 개를 함께 막는다.
    //   (1) 장중에 오늘 봉이 응답에 없었다 → "두 번째로 최신" 을 쓰면 그제가 잡힌다.
    //   (2) 폐장 후에도 현재가는 오늘 종가인데 "장 닫힘" 으로 보고 그제를 썼다.
    // 둘 다 상한가 종목을 +30% 대신 +26.42% 로 보이게 했다.
    await check.expectEqual(
        DailyChange.basePrice(from: yesterdayOnly, now: today, zone: .kst, hasSessionStartedToday: true),
        "248000",
        "오늘 봉이 없어도 오늘 장이 시작됐으면 어제가 기준가다 — 이게 +26.42% 버그였다"
    )

    // 오늘 장이 시작되지 않은 경우 — 개장 전·휴장일·주말. 현재가가 곧 최신 봉의 종가다.
    await check.expectEqual(
        DailyChange.basePrice(from: candles, now: today, zone: .kst, hasSessionStartedToday: false),
        "248000",
        "개장 전에는 최신 봉(오늘 마감본이 아니라 직전 거래일)의 앞이 기준가다"
    )
    await check.expectEqual(
        DailyChange.basePrice(from: yesterdayOnly, now: today, zone: .kst, hasSessionStartedToday: false),
        "240000",
        "주말이면 현재가가 금요일 종가이므로 목요일이 기준가다"
    )

    do {
        // 상한가 재현. 어제 -2.75% 후 오늘 +30%.
        let base: TossDecimal = "248000"          // 어제 종가
        let dayBefore: TossDecimal = "255000"     // 그제 종가
        let last = TossDecimal(base.value * Decimal(string: "1.30")!)
        await check.expectEqual(
            DailyChange.rate(lastPrice: last, basePrice: base).map { ValueFormatter.signedPercent($0) },
            "+30.00%",
            "어제 종가를 기준으로 하면 상한가는 +30% 다"
        )
        await check.expect(
            DailyChange.rate(lastPrice: last, basePrice: dayBefore).map {
                ValueFormatter.signedPercent($0)
            } != "+30.00%",
            "그제 종가를 기준으로 하면 +30% 가 나오지 않는다 — 기준가를 잘못 고르면 이렇게 어긋난다"
        )
    }

    await check.expect(
        DailyChange.basePrice(from: [], now: today, zone: .kst, hasSessionStartedToday: true) == nil,
        "봉이 없으면 nil 이다"
    )
    await check.expect(
        DailyChange.basePrice(
            from: Array(yesterdayOnly.prefix(1)), now: today, zone: .kst,
            hasSessionStartedToday: false
        ) == nil,
        "개장 전에 봉이 하나뿐이면 기준가를 정할 수 없다"
    )
    await check.expect(
        DailyChange.basePrice(
            from: candles.filter { $0.timestamp >= kst("2026-07-31T00:00:00+09:00") },
            now: today, zone: .kst, hasSessionStartedToday: true
        ) == nil,
        "오늘 봉만 있으면 비교할 앞 봉이 없어 nil 이다"
    )

    await check.expectEqual(
        DailyChange.rate(lastPrice: "250000", basePrice: "248000").map {
            ValueFormatter.signedPercent($0)
        },
        "+0.81%",
        "현재가와 기준가로 등락률을 낸다"
    )
    await check.expectEqual(
        DailyChange.rate(lastPrice: "240000", basePrice: "248000").map {
            ValueFormatter.signedPercent($0)
        },
        "-3.23%",
        "내렸으면 음수다"
    )
    await check.expect(
        DailyChange.rate(lastPrice: "250000", basePrice: nil) == nil,
        "기준가를 못 받았으면 등락률도 없다 — 계좌 손익률로 대신하지 않는다"
    )
    await check.expect(
        DailyChange.rate(lastPrice: "250000", basePrice: "0") == nil,
        "기준가가 0 이면 나눌 수 없다"
    )

    await check.group("DailyChange — 국내는 상/하한가로 기준가를 역산한다")

    // 국내 종목의 기준가를 일봉에서 구했더니 실제와 달랐다. 상한가 근처 종목이
    // 토스 앱의 +29.9% 대신 +24.06% 로 계산됐다. 상·하한가는 같은 시세 피드에서 오고
    // 날짜 경계·수정주가 해석이 개입하지 않아 훨씬 견고하다.
    await check.expectEqual(
        DailyChange.basePrice(
            from: PriceLimits(upperLimitPrice: "93000", lowerLimitPrice: "50400", currency: .krw)
        ),
        "71700",
        "문서 예시: 중간값이 기준가다 (71,700 × 1.3 = 93,210 → 호가 단위 93,000)"
    )
    await check.expectEqual(
        DailyChange.basePrice(
            from: PriceLimits(upperLimitPrice: "1718000", lowerLimitPrice: "926000", currency: .krw)
        ),
        "1322000",
        "실측: ×1.2996 / ×0.7004 로 대칭이라 중간값이 기준가다"
    )
    // 인버스2X ETF 는 상·하한폭이 ±30% 가 아니다. 그래도 **대칭**이므로 중간값은 성립한다.
    await check.expectEqual(
        DailyChange.basePrice(
            from: PriceLimits(upperLimitPrice: "130", lowerLimitPrice: "34", currency: .krw)
        ),
        "82",
        "ETF 는 상·하한폭이 ±60% 지만 대칭이라 중간값이 여전히 기준가다"
    )
    await check.expect(
        DailyChange.basePrice(
            from: PriceLimits(upperLimitPrice: nil, lowerLimitPrice: nil, currency: .usd)
        ) == nil,
        "해외 종목은 상/하한가가 없어 nil 이다 — 그때는 일봉으로 넘어간다"
    )
    await check.expect(
        DailyChange.basePrice(
            from: PriceLimits(upperLimitPrice: "93000", lowerLimitPrice: nil, currency: .krw)
        ) == nil,
        "한쪽만 있으면 역산할 수 없다"
    )
    await check.expect(
        DailyChange.basePrice(
            from: PriceLimits(upperLimitPrice: "0", lowerLimitPrice: "0", currency: .krw)
        ) == nil,
        "둘 다 0 이면 기준가가 0 이라 나눌 수 없다"
    )

    do {
        // 상한가 재현: 기준가 1,322,000 → 상한가 1,718,000 은 +29.95% 다.
        let base: TossDecimal = "1322000"
        await check.expectEqual(
            DailyChange.rate(lastPrice: "1718000", basePrice: base)
                .map { ValueFormatter.signedPercent($0) },
            "+29.95%",
            "상한가는 기준가 대비 약 +30% 로 나온다"
        )
    }

    await check.group("MarketHours.hasSessionStartedToday — 개장 여부와 다르다")

    do {
        // 국내 정규장 09:00~15:30 인 날.
        let hours = MarketHours(
            kr: KrMarketCalendar(
                today: KrMarketDay(
                    date: "2026-07-31",
                    integrated: KrTradingHours(
                        preMarket: nil,
                        regularMarket: MarketSession(
                            startTime: kst("2026-07-31T09:00:00+09:00"),
                            endTime: kst("2026-07-31T15:30:00+09:00")
                        ),
                        afterMarket: nil
                    )
                ),
                previousBusinessDay: KrMarketDay(date: "2026-07-30", integrated: nil),
                nextBusinessDay: KrMarketDay(date: "2026-08-03", integrated: nil)
            ),
            us: nil
        )

        await check.expect(
            !hours.hasSessionStartedToday(.kr, at: kst("2026-07-31T08:30:00+09:00")),
            "개장 전에는 시작되지 않았다"
        )
        await check.expect(
            hours.hasSessionStartedToday(.kr, at: kst("2026-07-31T14:00:00+09:00")),
            "장중에는 시작됐다"
        )
        // 이게 두 번째 버그의 핵심이다. 폐장 후에도 현재가는 오늘 종가다.
        await check.expect(
            hours.hasSessionStartedToday(.kr, at: kst("2026-07-31T16:00:00+09:00")),
            "폐장 후에도 시작된 것으로 본다 — 현재가가 오늘 종가이므로 기준가는 어제여야 한다"
        )
        await check.expect(
            !hours.isAnyMarketOpen(at: kst("2026-07-31T16:00:00+09:00")),
            "같은 시각에 '열려 있는가' 는 false 다 — 두 판단이 다르다는 것이 요점이다"
        )
        await check.expect(
            !hours.hasSessionStartedToday(.us, at: kst("2026-07-31T14:00:00+09:00")),
            "캘린더가 없는 시장은 판단하지 않는다"
        )
    }

    do {
        // 휴장일: 오늘 세션이 없다.
        let holiday = MarketHours(
            kr: KrMarketCalendar(
                today: KrMarketDay(date: "2026-08-01", integrated: nil),
                previousBusinessDay: KrMarketDay(date: "2026-07-31", integrated: nil),
                nextBusinessDay: KrMarketDay(date: "2026-08-03", integrated: nil)
            ),
            us: nil
        )
        await check.expect(
            !holiday.hasSessionStartedToday(.kr, at: kst("2026-08-01T14:00:00+09:00")),
            "휴장일에는 시작되지 않았다 — 현재가는 마지막 거래일 종가다"
        )
    }

    await check.group("candles 엔드포인트")

    let endpoint = TossEndpoint.candles(symbol: "005930", count: 3)
    await check.expectEqual(endpoint.path, "/api/v1/candles", "경로")
    await check.expectEqual(endpoint.group, .marketDataChart, "차트 전용 rate limit 그룹")
    await check.expect(!endpoint.requiresAccount, "시세라 계좌 헤더가 필요 없다")

    let query = Dictionary(
        endpoint.queryItems.compactMap { item in item.value.map { (item.name, $0) } },
        uniquingKeysWith: { first, _ in first }
    )
    await check.expectEqual(query["symbol"], "005930", "종목")
    await check.expectEqual(query["interval"], "1d", "일봉만 쓴다 — interval 은 필수 파라미터다")
    await check.expectEqual(query["count"], "3", "오늘 봉이 아직 없을 수 있어 3개를 받는다")
}
