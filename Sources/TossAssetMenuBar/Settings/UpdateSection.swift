import SwiftUI
import TossAssetMenuBarCore

/// 설정 탭 맨 아래의 버전 표시와 업데이트 확인.
///
/// **설치는 앱이 하지 않는다.** App Sandbox 때문에 `/Applications` 에 쓸 수 없고, `Process` 로
/// 띄운 자식도 같은 샌드박스를 물려받아 설치 스크립트를 실행할 수 없다. 실행 중인 번들을 스스로
/// 덮어쓰는 것도 위험하다. 그래서 새 버전을 알려주고 설치 수단만 건네준다.
@MainActor
struct UpdateSection: View {
    let state: AppState

    @State private var didCopyCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("버전 \(state.currentVersion.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(state.isCheckingUpdate ? "확인 중" : "업데이트 확인") {
                    Task { await state.checkForUpdate() }
                }
                .controlSize(.small)
                .disabled(state.isCheckingUpdate)
            }

            if let status = state.updateStatus {
                result(for: status)
            }

            // 자동 확인은 조용히 일어난다. 언제 확인했는지 보여주지 않으면
            // 자동 확인이 도는지 사용자가 알 방법이 없다.
            if let lastChecked = state.settings.lastUpdateCheckAt {
                Text("마지막 확인 \(ValueFormatter.timeWithDayIfNeeded(lastChecked, in: .kst))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func result(for status: UpdateStatus) -> some View {
        switch status {
        case .upToDate:
            Label("이미 최신 버전입니다", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .available(let release):
            VStack(alignment: .leading, spacing: 6) {
                Text("새 버전 \(release.version.description) 이 있습니다")
                    .font(.caption.weight(.medium))

                // 설치는 터미널에서 이뤄진다. 명령을 그대로 보여주고 복사만 도와준다.
                Text(state.installCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))

                HStack(spacing: 6) {
                    Button(didCopyCommand ? "복사됨" : "설치 명령 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.installCommand, forType: .string)
                        didCopyCommand = true
                    }
                    .controlSize(.small)

                    Link("릴리스 페이지", destination: release.pageURL)
                        .font(.caption)
                }

                Text("터미널에 붙여넣어 실행하면 새 버전으로 교체됩니다. 교체 후 앱을 다시 실행해 주세요.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
