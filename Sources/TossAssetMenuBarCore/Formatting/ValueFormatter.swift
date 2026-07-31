import Foundation

/// 금액·수익률 표시 규칙을 한곳에 모은다.
/// 손익은 부호가 정보의 핵심이므로 0 이 아닐 때는 항상 `+`/`-` 를 붙인다.
public enum ValueFormatter {
    /// `"0.1179"` → `"+11.79%"`
    public static func signedPercent(_ rate: TossDecimal, fractionDigits: Int = 2) -> String {
        let percent = rate.value * 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let magnitude = formatter.string(from: abs(percent) as NSDecimalNumber) ?? "0"
        return "\(sign(for: percent))\(magnitude)%"
    }

    /// 시각. 지정한 타임존으로 표시하고 약어를 붙인다. `"오전 10:23:10 KST"`
    ///
    /// `DateFormatter` 는 `Sendable` 이 아니어서 공유할 수 없다. `Date.FormatStyle` 은 struct 라
    /// 락 없이 매번 만들어 써도 안전하다.
    public static func time(
        _ date: Date,
        in zone: MarketTimeZone,
        includeZoneLabel: Bool = true
    ) -> String {
        let text = date.formatted(style(date: .omitted, time: .standard, zone: zone))
        return includeZoneLabel ? "\(text) \(zone.label(at: date))" : text
    }

    /// 시각. 해당 타임존 기준으로 오늘이 아니면 날짜도 함께 보여준다.
    /// 국내 장이 끝난 뒤 "다음 개장 오전 9:00" 만 보이면 오늘인지 내일인지 알 수 없다.
    public static func timeWithDayIfNeeded(
        _ date: Date,
        in zone: MarketTimeZone,
        now: Date = Date(),
        includeZoneLabel: Bool = true
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone.timeZone
        let isSameDay = calendar.isDate(date, inSameDayAs: now)

        let text = date.formatted(
            style(date: isSameDay ? .omitted : .abbreviated, time: .standard, zone: zone)
        )
        return includeZoneLabel ? "\(text) \(zone.label(at: date))" : text
    }

    private static func style(
        date: Date.FormatStyle.DateStyle,
        time: Date.FormatStyle.TimeStyle,
        zone: MarketTimeZone
    ) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: date, time: time)
        style.timeZone = zone.timeZone
        style.locale = Locale(identifier: "ko_KR")
        return style
    }

    /// 다음 갱신까지 남은 시간. 1분 미만은 `"12초"`, 그 이상은 `"4:05"`.
    /// 초 단위로 다시 그려지므로 자릿수가 흔들리지 않게 분 표기는 항상 두 자리로 맞춘다.
    public static func countdown(seconds: Int) -> String {
        let clamped = max(0, seconds)
        guard clamped >= 60 else { return "\(clamped)초" }
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// 비중처럼 부호가 의미 없는 비율. `0.6842` → `"68.4%"`
    public static func percent(_ ratio: Decimal, fractionDigits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let value = formatter.string(from: (ratio * 100) as NSDecimalNumber) ?? "0"
        return "\(value)%"
    }

    /// 원화. 소수점을 버리고 천단위 구분만 넣는다.
    public static func krw(_ amount: Decimal, signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let magnitude = formatter.string(from: abs(amount) as NSDecimalNumber) ?? "0"
        let prefix = signed ? sign(for: amount) : (amount < 0 ? "-" : "")
        return "\(prefix)\(magnitude)원"
    }

    /// 달러. 센트까지 보여준다.
    public static func usd(_ amount: Decimal, signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let magnitude = formatter.string(from: abs(amount) as NSDecimalNumber) ?? "0.00"
        let prefix = signed ? sign(for: amount) : (amount < 0 ? "-" : "")
        return "\(prefix)$\(magnitude)"
    }

    /// 종목의 거래 통화에 맞춰 가격을 표시한다.
    public static func price(_ value: TossDecimal, currency: Currency, signed: Bool = false) -> String {
        switch currency {
        case .krw: krw(value.value, signed: signed)
        case .usd: usd(value.value, signed: signed)
        case .other: plain(value.value, signed: signed)
        }
    }

    /// 통화를 모를 때의 최소 표현.
    public static func plain(_ amount: Decimal, signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        let magnitude = formatter.string(from: abs(amount) as NSDecimalNumber) ?? "0"
        let prefix = signed ? sign(for: amount) : (amount < 0 ? "-" : "")
        return "\(prefix)\(magnitude)"
    }

    /// 보유 종목의 지금 가격 — 종목명 옆에 붙는다.
    ///
    /// 라벨을 `현재`/`종가` 로 구분하는 이유는 세그먼트 표시기와 같다 — 이 숫자가 지금
    /// 움직이는 값인지 마지막 종가인지 알려준다. 종목마다 시장이 다르므로 호출하는 쪽이
    /// **그 종목의 시장** 기준으로 판단해 넘겨야 한다. `전체` 세그먼트에서는 국내가 열려 있고
    /// 해외는 닫혀 있을 수 있다.
    ///
    /// 종목명과 합쳐 한 문자열로 돌려주지 않는다. 그러면 이름이 긴 종목에서 한 줄 제한에 걸려
    /// **가격이 잘려 사라진다.** 뷰에서 별도 `Text` 로 두어 이름이 먼저 줄어들게 한다.
    public static func holdingPrice(
        _ lastPrice: TossDecimal,
        currency: Currency,
        isMarketOpen: Bool
    ) -> String {
        "\(isMarketOpen ? "현재" : "종가") \(price(lastPrice, currency: currency))"
    }

    /// 보유 종목의 수량과 평균단가 — 종목명 아래 줄.
    ///
    /// 총 수익률·손익은 다른 자리에 두고 여기에는 **주당** 값만 둔다.
    public static func holdingQuantity(
        _ quantityValue: TossDecimal,
        averagePrice: TossDecimal,
        currency: Currency
    ) -> String {
        "\(quantity(quantityValue))주 · 평균 \(price(averagePrice, currency: currency))"
    }

    /// 오늘 등락률.
    ///
    /// `오늘` 을 붙이는 이유는 같은 행에 **총 수익률**이 함께 있기 때문이다. 라벨이 없으면
    /// 두 퍼센트 중 어느 것이 오늘 것인지 알 수 없다.
    public static func holdingDailyChange(_ rate: TossDecimal) -> String {
        "오늘 \(signedPercent(rate))"
    }

    /// 보유 수량. 소수 수량(해외 소수점 매수)도 있으므로 필요할 때만 소수를 보여준다.
    public static func quantity(_ value: TossDecimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter.string(from: value.value as NSDecimalNumber) ?? "0"
    }

    private static func sign(for value: Decimal) -> String {
        if value > 0 { return "+" }
        if value < 0 { return "-" }
        return ""
    }
}
