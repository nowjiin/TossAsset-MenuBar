import SwiftUI
import TossAssetMenuBarCore

/// 보유 종목 한 줄.
@MainActor
struct HoldingRow: View {
    let item: HoldingsItem
    let showAfterCost: Bool

    var body: some View {
        let rate = showAfterCost ? item.profitLoss.rateAfterCost : item.profitLoss.rate
        let amount = showAfterCost ? item.profitLoss.amountAfterCost : item.profitLoss.amount

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(ValueFormatter.quantity(item.quantity))주 · 평균 \(ValueFormatter.price(item.averagePurchasePrice, currency: item.currency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
}
