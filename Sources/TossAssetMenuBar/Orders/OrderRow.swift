import SwiftUI
import TossAssetMenuBarCore

/// 매매 내역 한 줄.
@MainActor
struct OrderRow: View {
    let order: OrderRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            sideBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(order.symbol)
                        .font(.callout.weight(.medium))
                    if order.orderType == .market {
                        Text("시장가")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.callout.monospacedDigit())
                Text(quantityText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// 매수/매도를 색과 글자로 함께 구분한다. 색만으로 구분하면 색각 이상에서 읽을 수 없다.
    private var sideBadge: some View {
        Text(sideLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 26)
            .padding(.vertical, 2)
            .background(sideTint, in: RoundedRectangle(cornerRadius: 4))
            .padding(.top, 1)
    }

    private var sideLabel: String {
        switch order.side {
        case .buy: "매수"
        case .sell: "매도"
        case .other: "기타"
        }
    }

    /// 국내 관례를 따른다 — 매수는 빨강, 매도는 파랑.
    private var sideTint: Color {
        switch order.side {
        case .buy: .red
        case .sell: .blue
        case .other: .gray
        }
    }

    /// 국내 종목은 KST, 해외 종목은 미국 동부 현지 시간으로 보여준다.
    /// 거래 통화로 시장을 판단하는 것은 권역 집계와 같은 기준이다.
    private var timestamp: String {
        let zone = MarketTimeZone.forCurrency(order.currency)
        let time = ValueFormatter.timeWithDayIfNeeded(order.displayDate, in: zone)
        guard let status = statusNote else { return time }
        return "\(time) · \(status)"
    }

    /// 전량 체결은 굳이 적지 않는다. 그 외 상태만 덧붙인다.
    ///
    /// 부분 체결 여부를 상태값으로 판단하지 않는 이유는, `CANCELED` / `REJECTED` 주문에도
    /// 체결이 남아 있을 수 있다고 문서가 명시하기 때문이다. 그래서 수량으로 본다.
    private var statusNote: String? {
        switch order.status {
        case .filled: nil
        case .partialFilled: "부분 체결"
        case .canceled: order.execution.hasFill ? "일부 체결 후 취소" : "취소"
        case .rejected: "거부"
        case .replaced: "정정됨"
        case .cancelRejected: "취소 거부"
        case .replaceRejected: "정정 거부"
        case .pending: "체결 대기"
        case .pendingCancel: "취소 대기"
        case .pendingReplace: "정정 대기"
        case .other(let raw): raw
        }
    }

    /// 체결 금액. 체결이 없으면 금액이 없으므로 대시로 둔다 — 0 원으로 쓰면
    /// "0 원에 거래됨" 으로 읽힌다.
    private var amountText: String {
        guard let filled = order.execution.filledAmount else { return "—" }
        return ValueFormatter.price(filled, currency: order.currency)
    }

    /// 체결 수량과 주문 수량. 다르면 둘 다 보여준다.
    private var quantityText: String {
        let filled = order.execution.filledQuantity
        let ordered = ValueFormatter.quantity(order.quantity)
        guard filled != order.quantity else { return "\(ordered)주" }
        return "\(ValueFormatter.quantity(filled)) / \(ordered)주"
    }
}
