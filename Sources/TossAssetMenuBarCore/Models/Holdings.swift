import Foundation

/// 통화별 합산 금액.
///
/// 중요: `krw` 는 KRW 로 거래되는 국내 종목의 합, `usd` 는 USD 로 거래되는 해외 종목의 합이다.
/// **환율 환산이 적용되지 않은 값이므로 두 필드를 그냥 더하면 안 된다.**
/// 해외 종목이 없으면 `usd` 는 nil 이다.
public struct CurrencyAmount: Decodable, Sendable, Hashable {
    public let krw: TossDecimal
    public let usd: TossDecimal?

    public init(krw: TossDecimal, usd: TossDecimal?) {
        self.krw = krw
        self.usd = usd
    }

    /// 주어진 USD→KRW 환율로 원화 환산 총액을 구한다. 환율을 모르면 국내분만 반환한다.
    public func totalInKRW(usdToKrw rate: Decimal?) -> Decimal {
        guard let usd, let rate else { return krw.value }
        return krw.value + usd.value * rate
    }
}

/// `GET /api/v1/holdings` 응답.
public struct HoldingsOverview: Decodable, Sendable {
    public let totalPurchaseAmount: CurrencyAmount
    public let marketValue: OverviewMarketValue
    public let profitLoss: OverviewProfitLoss
    public let dailyProfitLoss: OverviewDailyProfitLoss
    public let items: [HoldingsItem]

    public init(
        totalPurchaseAmount: CurrencyAmount,
        marketValue: OverviewMarketValue,
        profitLoss: OverviewProfitLoss,
        dailyProfitLoss: OverviewDailyProfitLoss,
        items: [HoldingsItem]
    ) {
        self.totalPurchaseAmount = totalPurchaseAmount
        self.marketValue = marketValue
        self.profitLoss = profitLoss
        self.dailyProfitLoss = dailyProfitLoss
        self.items = items
    }
}

public struct OverviewMarketValue: Decodable, Sendable {
    public let amount: CurrencyAmount
    /// 세금·수수료 공제 후 평가금액. **토스가 계산해 내려주는 값이다** — 앱이 세율을 추정하지 않는다.
    public let amountAfterCost: CurrencyAmount

    public init(amount: CurrencyAmount, amountAfterCost: CurrencyAmount) {
        self.amount = amount
        self.amountAfterCost = amountAfterCost
    }
}

/// 전체 손익. `rate` 는 이미 "전체 자산을 현재 환율로 원화 환산한 기준" 손익률이므로
/// 클라이언트에서 다시 계산하지 말고 그대로 쓴다.
public struct OverviewProfitLoss: Decodable, Sendable {
    public let amount: CurrencyAmount
    /// 세금·수수료 공제 후 손익금액. 토스가 계산해 내려준다.
    public let amountAfterCost: CurrencyAmount
    public let rate: TossDecimal
    /// 세금·수수료 공제 후 손익률. 토스가 계산해 내려준다.
    public let rateAfterCost: TossDecimal

    public init(
        amount: CurrencyAmount,
        amountAfterCost: CurrencyAmount,
        rate: TossDecimal,
        rateAfterCost: TossDecimal
    ) {
        self.amount = amount
        self.amountAfterCost = amountAfterCost
        self.rate = rate
        self.rateAfterCost = rateAfterCost
    }
}

public struct OverviewDailyProfitLoss: Decodable, Sendable {
    public let amount: CurrencyAmount
    public let rate: TossDecimal

    public init(amount: CurrencyAmount, rate: TossDecimal) {
        self.amount = amount
        self.rate = rate
    }
}

/// 보유 종목 1건. 모든 금액은 해당 종목의 거래 통화(`currency`) 기준이다.
public struct HoldingsItem: Decodable, Sendable, Identifiable, Hashable {
    public let symbol: String
    public let name: String
    public let marketCountry: MarketCountry
    public let currency: Currency
    public let quantity: TossDecimal
    public let lastPrice: TossDecimal
    public let averagePurchasePrice: TossDecimal
    public let marketValue: ItemMarketValue
    public let profitLoss: ItemProfitLoss
    public let dailyProfitLoss: ItemDailyProfitLoss
    public let cost: ItemCost

    public var id: String { symbol }

    public init(
        symbol: String,
        name: String,
        marketCountry: MarketCountry,
        currency: Currency,
        quantity: TossDecimal,
        lastPrice: TossDecimal,
        averagePurchasePrice: TossDecimal,
        marketValue: ItemMarketValue,
        profitLoss: ItemProfitLoss,
        dailyProfitLoss: ItemDailyProfitLoss,
        cost: ItemCost
    ) {
        self.symbol = symbol
        self.name = name
        self.marketCountry = marketCountry
        self.currency = currency
        self.quantity = quantity
        self.lastPrice = lastPrice
        self.averagePurchasePrice = averagePurchasePrice
        self.marketValue = marketValue
        self.profitLoss = profitLoss
        self.dailyProfitLoss = dailyProfitLoss
        self.cost = cost
    }
}

public struct ItemMarketValue: Decodable, Sendable, Hashable {
    public let purchaseAmount: TossDecimal
    public let amount: TossDecimal
    /// 세금·수수료 공제 후 평가금액. 토스가 계산해 내려준다.
    public let amountAfterCost: TossDecimal

    public init(purchaseAmount: TossDecimal, amount: TossDecimal, amountAfterCost: TossDecimal) {
        self.purchaseAmount = purchaseAmount
        self.amount = amount
        self.amountAfterCost = amountAfterCost
    }
}

public struct ItemProfitLoss: Decodable, Sendable, Hashable {
    public let amount: TossDecimal
    /// 세금·수수료 공제 후 손익금액. 토스가 계산해 내려준다.
    public let amountAfterCost: TossDecimal
    public let rate: TossDecimal
    /// 세금·수수료 공제 후 손익률. 토스가 계산해 내려준다.
    public let rateAfterCost: TossDecimal

    public init(
        amount: TossDecimal,
        amountAfterCost: TossDecimal,
        rate: TossDecimal,
        rateAfterCost: TossDecimal
    ) {
        self.amount = amount
        self.amountAfterCost = amountAfterCost
        self.rate = rate
        self.rateAfterCost = rateAfterCost
    }
}

public struct ItemDailyProfitLoss: Decodable, Sendable, Hashable {
    public let amount: TossDecimal
    public let rate: TossDecimal

    public init(amount: TossDecimal, rate: TossDecimal) {
        self.amount = amount
        self.rate = rate
    }
}

/// 종목별 비용. **토스가 계산해 내려주는 값이다.**
/// 앱이 세율·거래세를 추정하지 않으므로 토스 앱에서 보는 값과 일치한다.
public struct ItemCost: Decodable, Sendable, Hashable {
    public let commission: TossDecimal
    /// 세금이 없는 경우 nil.
    public let tax: TossDecimal?

    public init(commission: TossDecimal, tax: TossDecimal?) {
        self.commission = commission
        self.tax = tax
    }
}
