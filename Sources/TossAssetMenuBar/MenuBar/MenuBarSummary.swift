import Foundation
import TossAssetMenuBarCore

/// 메뉴바에 무엇을 어떻게 표시할지 계산한다. 뷰에서 분리해 두면 규칙을 한눈에 볼 수 있다.
@MainActor
struct MenuBarSummary {
    enum Direction { case up, down, flat }

    let text: String
    let direction: Direction

    init(state: AppState) {
        guard state.hasCredentials else {
            self.text = "키 등록"
            self.direction = .flat
            return
        }
        if state.lastError?.needsUserAction == true {
            self.text = "확인 필요"
            self.direction = .flat
            return
        }

        switch state.settings.menuBarDisplay {
        case .totalRate:
            guard let rate = state.holdings?.profitLoss.rate else {
                self.text = "—"
                self.direction = .flat
                return
            }
            self.text = ValueFormatter.signedPercent(rate)
            self.direction = Self.direction(of: rate)

        case .totalProfitAmount:
            guard let holdings = state.holdings else {
                self.text = "—"
                self.direction = .flat
                return
            }
            let total = holdings.profitLoss.amount.totalInKRW(usdToKrw: state.usdToKrw)
            self.text = ValueFormatter.krw(total, signed: true)
            self.direction = total > 0 ? .up : (total < 0 ? .down : .flat)

        case .symbolPrice(let symbol):
            guard let price = state.watchlistPrices[symbol] else {
                self.text = symbol
                self.direction = .flat
                return
            }
            self.text = ValueFormatter.price(price.lastPrice, currency: price.currency)
            self.direction = .flat

        case .symbolRate(let symbol):
            guard let item = state.holdings?.items.first(where: { $0.symbol == symbol }) else {
                self.text = symbol
                self.direction = .flat
                return
            }
            self.text = ValueFormatter.signedPercent(item.profitLoss.rate)
            self.direction = Self.direction(of: item.profitLoss.rate)
        }
    }

    private static func direction(of rate: TossDecimal) -> Direction {
        if rate.isZero { return .flat }
        return rate.isNegative ? .down : .up
    }
}
