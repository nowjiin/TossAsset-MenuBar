import SwiftUI
import TossAssetMenuBarCore

/// 보유 종목 한 줄.
@MainActor
struct HoldingRow: View {
    let item: HoldingsItem
    let showAfterCost: Bool
    /// 이 종목이 상장된 시장이 열려 있는지. 가격 라벨을 `현재`/`종가` 로 구분하는 데 쓴다.
    let isMarketOpen: Bool
    /// **종목 자체의** 오늘 등락률. 기준가를 아직 못 받았으면 nil 이다.
    let dailyChange: TossDecimal?

    var body: some View {
        let rate = showAfterCost ? item.profitLoss.rateAfterCost : item.profitLoss.rate
        let amount = showAfterCost ? item.profitLoss.amountAfterCost : item.profitLoss.amount

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // 종목명은 **자기 줄을 통째로 쓴다.**
                //
                // 가격과 같은 줄에 두었더니 `KODEX 200선물인버스2X` 같은 이름이 잘렸다.
                // 가격 쪽에 `fixedSize` 를 주어 이름이 먼저 줄어들게 한 결과인데,
                // 정작 사람이 먼저 읽는 것은 이름이라 순서가 거꾸로였다.
                //
                // 두 줄까지 허용해 긴 ETF 이름도 끝까지 보이게 한다. 한 줄로 묶어두면
                // 줄 하나를 통째로 줘도 여전히 잘리는 이름이 남는다.
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // 가격과 **종목 자체의** 등락률. 나란히 두어 "이 가격이 오늘 이만큼
                // 움직였다" 로 읽힌다. 아래 줄의 `오늘 손익` 은 내 포지션 기준이라 다른 값이다.
                HStack(spacing: 4) {
                    Text(priceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let dailyChange {
                        Text(ValueFormatter.signedPercent(dailyChange))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ChangeColor.of(dailyChange))
                            .monospacedDigit()
                    }
                }
                .fixedSize()
                // 오늘 등락률은 색을 입혀야 한눈에 읽히므로 별도 `Text` 로 둔다.
                // 여기서도 수량 쪽이 먼저 줄어들게 `fixedSize` 를 준다.
                HStack(spacing: 4) {
                    Text(quantityText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("· \(ValueFormatter.holdingDailyProfit(item.dailyProfitLoss.rate))")
                        .font(.caption2)
                        .foregroundStyle(ChangeColor.of(item.dailyProfitLoss.rate))
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ValueFormatter.signedPercent(rate))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ChangeColor.of(rate))
                    .monospacedDigit()
                Text(ValueFormatter.price(amount, currency: item.currency, signed: true))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 7)
    }

    /// 문구 조립은 `ValueFormatter` 에 있다 — 검증 러너가 확인할 수 있게 두었다.
    private var priceText: String {
        ValueFormatter.holdingPrice(
            item.lastPrice,
            currency: item.currency,
            isMarketOpen: isMarketOpen
        )
    }

    private var quantityText: String {
        ValueFormatter.holdingQuantity(
            item.quantity,
            averagePrice: item.averagePurchasePrice,
            currency: item.currency
        )
    }
}
