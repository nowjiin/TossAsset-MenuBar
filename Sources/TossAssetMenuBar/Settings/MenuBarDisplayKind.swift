import Foundation
import TossAssetMenuBarCore

/// `MenuBarDisplay` 는 연관값을 갖는 enum 이라 Picker 태그로 쓸 수 없다.
/// 종류만 떼어낸 값을 Picker 에 물리고, 종목은 별도 Picker 에서 고르게 한다.
enum MenuBarDisplayKind: Hashable {
    case totalRate, totalProfitAmount, symbolPrice, symbolRate

    init(_ display: MenuBarDisplay) {
        switch display {
        case .totalRate: self = .totalRate
        case .totalProfitAmount: self = .totalProfitAmount
        case .symbolPrice: self = .symbolPrice
        case .symbolRate: self = .symbolRate
        }
    }

    var needsSymbol: Bool {
        self == .symbolPrice || self == .symbolRate
    }

    func display(symbol: String) -> MenuBarDisplay {
        switch self {
        case .totalRate: .totalRate
        case .totalProfitAmount: .totalProfitAmount
        case .symbolPrice: .symbolPrice(symbol: symbol)
        case .symbolRate: .symbolRate(symbol: symbol)
        }
    }
}
