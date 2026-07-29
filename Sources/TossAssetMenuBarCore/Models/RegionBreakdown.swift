import Foundation

public enum HoldingsRegion: Sendable, Hashable, CaseIterable {
    case domestic
    case overseas
    case total

    public var label: String {
        switch self {
        case .domestic: "국내"
        case .overseas: "해외"
        case .total: "전체"
        }
    }

    /// 해당 권역의 거래 통화. 전체는 두 통화가 섞여 있어 하나로 정할 수 없다.
    public var currency: Currency? {
        switch self {
        case .domestic: .krw
        case .overseas: .usd
        case .total: nil
        }
    }

    /// 개장 여부를 물어볼 시장. 전체는 해당 없음.
    public var marketCountry: MarketCountry? {
        switch self {
        case .domestic: .kr
        case .overseas: .us
        case .total: nil
        }
    }

    /// 화면에 놓을 순서. 전체를 먼저 보여주고 그다음 국내·해외로 좁힌다.
    public static let displayOrder: [HoldingsRegion] = [.total, .domestic, .overseas]

    /// 이 종목이 해당 권역에 속하는가.
    ///
    /// **거래 통화**로 판단한다. `HoldingsOverview` 의 `krw`/`usd` 합산 기준과 같은 잣대를 써야
    /// 목록의 합과 요약 금액이 어긋나지 않는다.
    public func contains(_ item: HoldingsItem) -> Bool {
        switch self {
        case .total: true
        case .domestic: item.currency == .krw
        case .overseas: item.currency == .usd
        }
    }
}

/// 권역 하나의 집계.
///
/// `국내`·`해외` 금액은 **거래 통화 기준**이다 (국내는 원, 해외는 달러).
/// 서로 비교하려면 `marketValueInKRW` 처럼 환산된 값을 써야 한다.
public struct RegionSummary: Sendable {
    public let region: HoldingsRegion
    /// 투자원금 (거래 통화 기준)
    public let purchaseAmount: Decimal
    /// 평가금액 (거래 통화 기준)
    public let marketValue: Decimal
    /// 손익금액 (거래 통화 기준)
    public let profitAmount: Decimal
    /// 일간 손익금액 (거래 통화 기준)
    public let dailyProfitAmount: Decimal
    /// 수익률. 투자원금이 0 이면 계산할 수 없어 nil.
    public let rate: Decimal?
    public let itemCount: Int
    /// 원화 환산 평가금액. 해외인데 환율을 모르면 nil.
    public let marketValueInKRW: Decimal?
    /// 전체 평가금액에서 차지하는 비중 (0~1). 환산이 불가능하면 nil.
    public let share: Decimal?

    /// 이 권역에 보유 종목이 없다.
    public var isEmpty: Bool {
        itemCount == 0 && marketValue == 0
    }
}

/// 국내·해외·전체를 나란히 놓고 비교하기 위한 집계.
///
/// 전체 수익률은 API 가 주는 값(`profitLoss.rate`, 원화 환산 기준)을 그대로 쓴다.
/// 반면 **권역별 수익률은 API 가 주지 않으므로** `손익 ÷ 투자원금` 으로 직접 계산한다.
/// 같은 통화 안에서의 나눗셈이라 환율이 끼어들지 않는다.
public struct RegionBreakdown: Sendable {
    public let domestic: RegionSummary
    public let overseas: RegionSummary
    public let total: RegionSummary

    public var all: [RegionSummary] { [domestic, overseas, total] }

    public func summary(for region: HoldingsRegion) -> RegionSummary {
        switch region {
        case .domestic: domestic
        case .overseas: overseas
        case .total: total
        }
    }

    /// `showAfterCost` 는 토스가 내려준 공제 후 값으로 바꿔 볼지 여부다.
    /// 앱이 세금을 계산하는 게 아니라 응답의 다른 필드를 고르는 것이다.
    public init(overview: HoldingsOverview, usdToKrw: Decimal?, showAfterCost: Bool) {
        let marketValue = showAfterCost
            ? overview.marketValue.amountAfterCost
            : overview.marketValue.amount
        let profitLoss = showAfterCost
            ? overview.profitLoss.amountAfterCost
            : overview.profitLoss.amount
        let totalRate = showAfterCost
            ? overview.profitLoss.rateAfterCost
            : overview.profitLoss.rate
        let purchase = overview.totalPurchaseAmount
        let daily = overview.dailyProfitLoss.amount

        let domesticMarketValue = marketValue.krw.value
        // usd 가 nil 이면 해외 보유 종목이 아예 없다는 뜻이다.
        let overseasMarketValue = marketValue.usd?.value ?? 0
        let overseasMarketValueInKRW = marketValue.usd.flatMap { value in
            usdToKrw.map { value.value * $0 }
        }

        // 해외 보유가 있는데 환율을 모르면 원화 합계를 낼 수 없다. 이때는 비중을 감춘다.
        let totalMarketValueInKRW: Decimal?
        if marketValue.usd == nil {
            totalMarketValueInKRW = domesticMarketValue
        } else if let overseasMarketValueInKRW {
            totalMarketValueInKRW = domesticMarketValue + overseasMarketValueInKRW
        } else {
            totalMarketValueInKRW = nil
        }

        func share(_ valueInKRW: Decimal?) -> Decimal? {
            guard let valueInKRW,
                  let totalMarketValueInKRW,
                  totalMarketValueInKRW != 0
            else { return nil }
            return valueInKRW / totalMarketValueInKRW
        }

        self.domestic = RegionSummary(
            region: .domestic,
            purchaseAmount: purchase.krw.value,
            marketValue: domesticMarketValue,
            profitAmount: profitLoss.krw.value,
            dailyProfitAmount: daily.krw.value,
            rate: Self.rate(profit: profitLoss.krw.value, purchase: purchase.krw.value),
            itemCount: overview.items.count { $0.currency == .krw },
            marketValueInKRW: domesticMarketValue,
            share: share(domesticMarketValue)
        )

        self.overseas = RegionSummary(
            region: .overseas,
            purchaseAmount: purchase.usd?.value ?? 0,
            marketValue: overseasMarketValue,
            profitAmount: profitLoss.usd?.value ?? 0,
            dailyProfitAmount: daily.usd?.value ?? 0,
            rate: Self.rate(profit: profitLoss.usd?.value, purchase: purchase.usd?.value),
            itemCount: overview.items.count { $0.currency == .usd },
            marketValueInKRW: overseasMarketValueInKRW,
            share: share(overseasMarketValueInKRW)
        )

        self.total = RegionSummary(
            region: .total,
            purchaseAmount: purchase.totalInKRW(usdToKrw: usdToKrw),
            marketValue: totalMarketValueInKRW ?? domesticMarketValue,
            profitAmount: profitLoss.totalInKRW(usdToKrw: usdToKrw),
            dailyProfitAmount: daily.totalInKRW(usdToKrw: usdToKrw),
            // 전체는 API 가 원화 환산 기준으로 이미 계산해 준 값을 쓴다.
            rate: totalRate.value,
            itemCount: overview.items.count,
            marketValueInKRW: totalMarketValueInKRW,
            share: totalMarketValueInKRW == nil ? nil : 1
        )
    }

    private static func rate(profit: Decimal?, purchase: Decimal?) -> Decimal? {
        guard let profit, let purchase, purchase != 0 else { return nil }
        return profit / purchase
    }
}
