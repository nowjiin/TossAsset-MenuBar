import SwiftUI
import TossAssetMenuBarCore

@MainActor
struct WatchlistRow: View {
    let symbol: String
    let info: StockInfo?
    let price: StockPrice?
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(info?.displayName ?? symbol)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            if let price {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ValueFormatter.price(price.lastPrice, currency: price.currency))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    // 체결 시각은 그 종목이 거래되는 시장의 현지 시간으로 보여준다.
                    // 미국 종목을 KST 로 보여주면 장중인지 감이 오지 않는다.
                    if let timestamp = price.timestamp {
                        Text(ValueFormatter.time(timestamp, in: displayTimeZone(for: price)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 7)
        .onHover { isHovering = $0 }
    }

    /// 상장 시장을 알면 그걸 쓰고, 모르면 거래 통화로 유추한다.
    private func displayTimeZone(for price: StockPrice) -> MarketTimeZone {
        if let market = info?.market.country {
            return MarketTimeZone.forMarket(market)
        }
        return MarketTimeZone.forCurrency(price.currency)
    }
}
