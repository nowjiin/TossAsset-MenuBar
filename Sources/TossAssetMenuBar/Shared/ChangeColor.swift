import SwiftUI
import TossAssetMenuBarCore

/// 국내 시장 관례에 맞춰 상승은 빨강, 하락은 파랑으로 표시한다.
enum ChangeColor {
    static func of(_ value: TossDecimal) -> Color {
        if value.isZero { return .secondary }
        return value.isNegative ? .blue : .red
    }

    static func of(_ value: Decimal) -> Color {
        if value == 0 { return .secondary }
        return value < 0 ? .blue : .red
    }
}
