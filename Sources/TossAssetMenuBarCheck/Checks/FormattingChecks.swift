import Foundation
import TossAssetMenuBarCore

/// 화면에 나가는 문자열. 부호·통화·타임존 규칙을 고정한다.
func runFormattingChecks(_ check: CheckHarness) async throws {
    // MARK: 손익 표시

    await check.group("ValueFormatter — 손익 표시")

    await check.expectEqual(ValueFormatter.signedPercent("0.1179"), "+11.79%", "이익은 + 를 붙인다")
    await check.expectEqual(ValueFormatter.signedPercent("-0.0846"), "-8.46%", "손실은 - 를 붙인다")
    await check.expectEqual(ValueFormatter.signedPercent("0"), "0.00%", "0 에는 부호를 붙이지 않는다")
    await check.expectEqual(ValueFormatter.krw(Decimal(700_000), signed: true), "+700,000원", "원화 손익")
    await check.expectEqual(ValueFormatter.krw(Decimal(-150_000), signed: true), "-150,000원", "원화 손실")
    await check.expectEqual(ValueFormatter.usd(Decimal(string: "232.5")!, signed: true), "+$232.50", "달러 손익은 센트까지")
    await check.expectEqual(
        ValueFormatter.price("178.5", currency: .usd),
        "$178.50",
        "해외 종목 가격은 달러로 표시한다"
    )
    await check.expectEqual(
        ValueFormatter.price("72000", currency: .krw),
        "72,000원",
        "국내 종목 가격은 원화로 표시한다"
    )

    // MARK: 비중과 카운트다운

    await check.group("ValueFormatter — 비중·카운트다운")

    await check.expectEqual(ValueFormatter.percent(Decimal(string: "0.6842")!), "68.4%", "비중은 부호 없이 표시한다")
    await check.expectEqual(ValueFormatter.percent(1), "100.0%", "전체는 100%")
    await check.expectEqual(ValueFormatter.percent(0), "0.0%", "0 비중")

    await check.expectEqual(ValueFormatter.countdown(seconds: 30), "30초", "30초 남음")
    await check.expectEqual(ValueFormatter.countdown(seconds: 9), "9초", "한 자리 초")
    await check.expectEqual(ValueFormatter.countdown(seconds: 0), "0초", "0초")
    await check.expectEqual(ValueFormatter.countdown(seconds: 60), "1:00", "1분은 분 표기로 넘어간다")
    await check.expectEqual(ValueFormatter.countdown(seconds: 65), "1:05", "분 표기의 초는 항상 두 자리")
    await check.expectEqual(ValueFormatter.countdown(seconds: 300), "5:00", "5분 주기의 시작")
    // 시각 계산이 음수로 떨어져도 "-3초" 같은 값이 화면에 나가면 안 된다.
    await check.expectEqual(ValueFormatter.countdown(seconds: -3), "0초", "음수는 0 으로 눌러 표시한다")

    // MARK: 타임존

    await check.group("MarketTimeZone — 앱은 KST 고정, 해외는 현지 시간")

    await check.expectEqual(MarketTimeZone.kst.timeZone.identifier, "Asia/Seoul", "국내 기준은 Asia/Seoul")
    await check.expectEqual(
        MarketTimeZone.usEastern.timeZone.identifier,
        "America/New_York",
        "미국 시장은 America/New_York (고정 오프셋이 아니어야 서머타임을 따른다)"
    )
    await check.expectEqual(MarketTimeZone.forMarket(.kr), MarketTimeZone.kst, "국내 시장 → KST")
    await check.expectEqual(MarketTimeZone.forMarket(.us), MarketTimeZone.usEastern, "미국 시장 → 미국 동부")
    await check.expectEqual(MarketTimeZone.forCurrency(.krw), MarketTimeZone.kst, "원화 종목 → KST")
    await check.expectEqual(MarketTimeZone.forCurrency(.usd), MarketTimeZone.usEastern, "달러 종목 → 미국 동부")
    // 모르는 시장/통화를 만나도 앱 기준시로 떨어뜨려야 한다.
    await check.expectEqual(MarketTimeZone.forMarket(.other("JP")), MarketTimeZone.kst, "모르는 시장은 앱 기준시로")

    // 서머타임 경계. 3월 하순은 EDT, 1월은 EST 다.
    await check.expectEqual(
        MarketTimeZone.usEastern.label(at: kst("2026-03-25T23:00:00+09:00")),
        "EDT",
        "서머타임 기간에는 EDT"
    )
    await check.expectEqual(
        MarketTimeZone.usEastern.label(at: kst("2026-01-15T23:00:00+09:00")),
        "EST",
        "서머타임이 아니면 EST"
    )
    await check.expectEqual(
        MarketTimeZone.kst.label(at: kst("2026-03-25T10:00:00+09:00")),
        "KST",
        "국내는 항상 KST"
    )

    await check.group("ValueFormatter.time — 같은 시점을 타임존별로 표시")

    do {
        // 같은 절대 시각. KST 로는 3/25 23:00, 미국 동부로는 3/25 10:00 (EDT, 13시간 차).
        let moment = kst("2026-03-25T23:00:00+09:00")

        await check.expectEqual(
            ValueFormatter.time(moment, in: .kst),
            "오후 11:00:00 KST",
            "KST 로는 밤 11시"
        )
        await check.expectEqual(
            ValueFormatter.time(moment, in: .usEastern),
            "오전 10:00:00 EDT",
            "같은 시점이 미국 동부로는 오전 10시다"
        )
        await check.expectEqual(
            ValueFormatter.time(moment, in: .kst, includeZoneLabel: false),
            "오후 11:00:00",
            "약어를 뺄 수도 있다"
        )

        // Mac 의 로컬 타임존과 무관하게 같은 값이 나와야 한다.
        await check.expect(
            ValueFormatter.time(moment, in: .kst).contains("11:00:00"),
            "앱 기준 시각은 로컬 타임존에 흔들리지 않는다"
        )
    }

    do {
        // 오늘이 아니면 날짜를 함께 보여줘야 한다. "오전 9:00 개장" 만 보이면 오늘인지 내일인지 모른다.
        let now = kst("2026-03-25T21:00:00+09:00")
        let tomorrowOpen = kst("2026-03-26T09:00:00+09:00")
        let todayLater = kst("2026-03-25T22:30:00+09:00")

        await check.expectEqual(
            ValueFormatter.timeWithDayIfNeeded(todayLater, in: .kst, now: now),
            "오후 10:30:00 KST",
            "같은 날이면 시각만 보여준다"
        )
        await check.expect(
            ValueFormatter.timeWithDayIfNeeded(tomorrowOpen, in: .kst, now: now).contains("3"),
            "다음 날이면 날짜를 함께 보여준다"
        )
        await check.expect(
            ValueFormatter.timeWithDayIfNeeded(tomorrowOpen, in: .kst, now: now).hasSuffix("KST"),
            "날짜가 붙어도 타임존 약어는 유지한다"
        )

        // 날짜 경계 판단은 표시 타임존 기준이어야 한다.
        // 이 시점은 KST 로 3/26 이지만 미국 동부로는 아직 3/25 다.
        let afterKstMidnight = kst("2026-03-26T01:00:00+09:00")
        await check.expectEqual(
            ValueFormatter.timeWithDayIfNeeded(
                afterKstMidnight,
                in: .usEastern,
                now: kst("2026-03-25T23:00:00+09:00")
            ),
            "오후 12:00:00 EDT",
            "미국 동부 기준으로는 같은 날이라 날짜를 붙이지 않는다"
        )
    }
}
