import Foundation

/// 시각을 어느 타임존으로 보여줄지.
///
/// 이 앱의 기준 시간은 **KST 고정**이다. Mac 의 로컬 타임존을 따르지 않는다 —
/// 해외에서 켜도 "오전 9시 개장" 이 한국 장 기준으로 읽혀야 하기 때문이다.
/// 반면 해외 종목·해외 장 시간은 **그 시장의 현지 시간**으로 보여준다.
public enum MarketTimeZone: Sendable, Hashable {
    /// 한국 표준시. 앱의 기본 기준.
    case kst
    /// 미국 동부. NYSE·NASDAQ 의 현지 시간이다.
    /// 서머타임에 따라 EDT/EST 가 바뀌므로 고정 오프셋이 아닌 타임존 식별자를 쓴다.
    case usEastern

    public static func forMarket(_ country: MarketCountry) -> MarketTimeZone {
        switch country {
        case .kr: .kst
        case .us: .usEastern
        // 모르는 시장은 앱 기준시로 보여준다.
        case .other: .kst
        }
    }

    public static func forCurrency(_ currency: Currency) -> MarketTimeZone {
        switch currency {
        case .krw: .kst
        case .usd: .usEastern
        case .other: .kst
        }
    }

    public var timeZone: TimeZone {
        switch self {
        case .kst:
            TimeZone(identifier: "Asia/Seoul") ?? TimeZone(secondsFromGMT: 9 * 3600)!
        case .usEastern:
            TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600)!
        }
    }

    /// 화면에 붙일 약어. 미국은 시점에 따라 EDT/EST 가 달라지므로 날짜를 받는다.
    ///
    /// `TimeZone.abbreviation(for:)` 는 이 플랫폼에서 `"GMT-4"` 같은 오프셋 표기를 돌려주므로
    /// 쓰지 않는다. 지원하는 타임존이 둘뿐이라 서머타임 여부로 직접 정하는 게 정확하다.
    public func label(at date: Date) -> String {
        switch self {
        case .kst:
            // 한국은 서머타임이 없다.
            return "KST"
        case .usEastern:
            return timeZone.isDaylightSavingTime(for: date) ? "EDT" : "EST"
        }
    }
}
