import Foundation

/// 매매 내역 — `GET /api/v1/orders` 응답.
///
/// **이 앱은 주문을 생성·정정·취소하지 않는다.** 여기 있는 것은 전부 조회 결과를 담는 타입이며,
/// 요청을 만드는 타입(`OrderCreateRequest` 등)은 의도적으로 넣지 않는다.
/// 토스도 rate limit 그룹을 `ORDER`(쓰기 3개)와 `ORDER_HISTORY`(읽기 2개)로 나눠 두었고,
/// 이 앱은 후자만 쓴다.

/// `status` 쿼리 파라미터. 주문의 세부 상태(`OrderStatus`)를 그룹화한 **요청용 라벨**이라
/// 값 체계가 다르다. 서버가 정의한 닫힌 집합이므로 `OpenEnum` 이 아니다.
public enum OrderStatusFilter: String, Sendable, CaseIterable {
    /// PENDING, PARTIAL_FILLED, PENDING_CANCEL, PENDING_REPLACE
    case open = "OPEN"
    /// FILLED, CANCELED, REJECTED, REPLACED 등 종료 상태
    case closed = "CLOSED"
}

public enum OrderSide: OpenEnum {
    case buy
    case sell
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "BUY": self = .buy
        case "SELL": self = .sell
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .buy: "BUY"
        case .sell: "SELL"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> OrderSide { .other(raw) }
}

public enum OrderType: OpenEnum {
    case limit
    case market
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "LIMIT": self = .limit
        case "MARKET": self = .market
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .limit: "LIMIT"
        case .market: "MARKET"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> OrderType { .other(raw) }
}

public enum TimeInForce: OpenEnum {
    case day
    case close
    case open
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "DAY": self = .day
        case "CLS": self = .close
        case "OPG": self = .open
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .day: "DAY"
        case .close: "CLS"
        case .open: "OPG"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> TimeInForce { .other(raw) }
}

public enum OrderStatus: OpenEnum {
    case pending, pendingCancel, pendingReplace
    case partialFilled, filled
    case canceled, rejected, cancelRejected, replaceRejected, replaced
    case other(String)

    public init?(rawValue: String) {
        switch rawValue {
        case "PENDING": self = .pending
        case "PENDING_CANCEL": self = .pendingCancel
        case "PENDING_REPLACE": self = .pendingReplace
        case "PARTIAL_FILLED": self = .partialFilled
        case "FILLED": self = .filled
        case "CANCELED": self = .canceled
        case "REJECTED": self = .rejected
        case "CANCEL_REJECTED": self = .cancelRejected
        case "REPLACE_REJECTED": self = .replaceRejected
        case "REPLACED": self = .replaced
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .pending: "PENDING"
        case .pendingCancel: "PENDING_CANCEL"
        case .pendingReplace: "PENDING_REPLACE"
        case .partialFilled: "PARTIAL_FILLED"
        case .filled: "FILLED"
        case .canceled: "CANCELED"
        case .rejected: "REJECTED"
        case .cancelRejected: "CANCEL_REJECTED"
        case .replaceRejected: "REPLACE_REJECTED"
        case .replaced: "REPLACED"
        case .other(let raw): raw
        }
    }

    public static func unknown(_ raw: String) -> OrderStatus { .other(raw) }

    /// 체결이 하나도 없는 주문. 목록에서 "체결 없음" 으로 구분해 보여주기 위한 판단이 아니라,
    /// `execution.filledQuantity` 를 봐야 한다 — `CANCELED`/`REJECTED` 도 부분 체결이 있을 수 있다.
    /// 문서가 명시적으로 그렇게 안내한다. 그래서 이 프로퍼티는 상태만으로 단정하지 않는다.
    public var isTerminal: Bool {
        switch self {
        case .filled, .canceled, .rejected, .cancelRejected, .replaceRejected, .replaced: true
        case .pending, .pendingCancel, .pendingReplace, .partialFilled: false
        case .other: false
        }
    }
}

/// 체결 정보. 미체결 주문에서는 `filledQuantity` 를 뺀 전부가 `null` 이다.
public struct OrderExecution: Sendable, Hashable, Codable {
    public let filledQuantity: TossDecimal
    public let averageFilledPrice: TossDecimal?
    public let filledAmount: TossDecimal?
    /// 수수료·세금은 **토스가 계산해 내려주는 값**이다. 앱이 세율을 추정하지 않는다.
    public let commission: TossDecimal?
    public let tax: TossDecimal?
    public let filledAt: Date?
    /// 결제일은 `2026-03-30` 형태의 **날짜 문자열**이다. 타임스탬프가 아니므로
    /// ISO8601 날짜·시각 파서로 다루지 않고 그대로 보관한다.
    public let settlementDate: String?

    public init(
        filledQuantity: TossDecimal,
        averageFilledPrice: TossDecimal? = nil,
        filledAmount: TossDecimal? = nil,
        commission: TossDecimal? = nil,
        tax: TossDecimal? = nil,
        filledAt: Date? = nil,
        settlementDate: String? = nil
    ) {
        self.filledQuantity = filledQuantity
        self.averageFilledPrice = averageFilledPrice
        self.filledAmount = filledAmount
        self.commission = commission
        self.tax = tax
        self.filledAt = filledAt
        self.settlementDate = settlementDate
    }

    /// 한 주라도 체결됐는지. 상태가 아니라 수량으로 판단한다 —
    /// `CANCELED` / `REJECTED` 주문도 부분 체결이 남아 있을 수 있다.
    public var hasFill: Bool { !filledQuantity.isZero }

    /// 수수료 + 세금. 둘 다 없으면 `nil` 이다. 없는 값을 0 으로 바꿔 더하면
    /// "비용 0원" 과 "아직 정산 안 됨" 이 구분되지 않는다.
    public var totalCost: TossDecimal? {
        switch (commission, tax) {
        case (nil, nil): nil
        case (let c?, nil): c
        case (nil, let t?): t
        case (let c?, let t?): TossDecimal(c.value + t.value)
        }
    }
}

public struct OrderRecord: Sendable, Hashable, Codable, Identifiable {
    public let orderId: String
    public let symbol: String
    public let side: OrderSide
    public let orderType: OrderType
    public let timeInForce: TimeInForce
    public let status: OrderStatus
    /// 시장가 주문에서는 `null` 이다.
    public let price: TossDecimal?
    public let quantity: TossDecimal
    public let orderAmount: TossDecimal?
    public let currency: Currency
    public let orderedAt: Date
    public let canceledAt: Date?
    public let execution: OrderExecution

    public var id: String { orderId }

    public init(
        orderId: String,
        symbol: String,
        side: OrderSide,
        orderType: OrderType,
        timeInForce: TimeInForce,
        status: OrderStatus,
        price: TossDecimal? = nil,
        quantity: TossDecimal,
        orderAmount: TossDecimal? = nil,
        currency: Currency,
        orderedAt: Date,
        canceledAt: Date? = nil,
        execution: OrderExecution
    ) {
        self.orderId = orderId
        self.symbol = symbol
        self.side = side
        self.orderType = orderType
        self.timeInForce = timeInForce
        self.status = status
        self.price = price
        self.quantity = quantity
        self.orderAmount = orderAmount
        self.currency = currency
        self.orderedAt = orderedAt
        self.canceledAt = canceledAt
        self.execution = execution
    }

    /// 목록 정렬·표시에 쓰는 기준 시각. 체결된 주문은 체결 시각이 더 의미 있고,
    /// 미체결이면 주문 시각밖에 없다.
    public var displayDate: Date { execution.filledAt ?? orderedAt }
}

/// 종목별 필터.
///
/// 로직을 `Core` 에 두는 이유는 검증 러너가 앱을 실행하지 않고 호출할 수 있어야 하기 때문이다.
/// 뷰 안에 넣으면 정렬·중복 제거·대소문자 규칙을 확인할 방법이 없어진다.
public enum OrderHistoryFilter {
    /// 심볼 비교는 대소문자를 무시한다. 서버는 `AAPL` 로 내려주지만 앱 안에서 소문자로
    /// 흘러 들어올 여지가 있고, 그 경우 필터가 조용히 빈 목록을 만든다.
    public static func apply(_ orders: [OrderRecord], symbol: String?) -> [OrderRecord] {
        guard let symbol, !symbol.isEmpty else { return orders }
        return orders.filter { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
    }

    /// 목록에 등장한 심볼. **최근 거래 순**으로 중복 없이 돌려준다.
    ///
    /// 알파벳순으로 정렬하지 않는 이유는, 방금 거래한 종목을 고르려는 경우가 대부분이라
    /// 그게 목록 맨 앞에 있는 편이 낫기 때문이다.
    public static func symbols(in orders: [OrderRecord]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for order in orders.sorted(by: { $0.displayDate > $1.displayDate }) {
            let key = order.symbol.uppercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(order.symbol)
        }
        return result
    }
}

public struct OrderHistoryPage: Sendable, Hashable, Codable {
    public let orders: [OrderRecord]
    /// 다음 페이지 커서. `status=OPEN` 에서는 항상 `null` 이다 (전량 반환).
    public let nextCursor: String?
    public let hasNext: Bool

    public init(orders: [OrderRecord], nextCursor: String? = nil, hasNext: Bool = false) {
        self.orders = orders
        self.nextCursor = nextCursor
        self.hasNext = hasNext
    }
}
