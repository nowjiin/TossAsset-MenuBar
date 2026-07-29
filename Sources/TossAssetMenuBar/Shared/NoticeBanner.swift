import SwiftUI

/// 오류·안내를 팝오버 안에서 보여주는 배너.
struct NoticeBanner: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// 데이터가 아직 없을 때의 안내.
struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
