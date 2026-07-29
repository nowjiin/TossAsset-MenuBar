import SwiftUI

/// 라벨 + 값 한 줄.
struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var isProminent = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(isProminent ? .title3.weight(.semibold) : .callout)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
    }
}
