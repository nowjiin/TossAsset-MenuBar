import SwiftUI
import TossAssetMenuBarCore

/// 메뉴바에 항상 보이는 한 줄.
@MainActor
struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        // 메뉴바 폭은 한정적이라 아이콘 + 짧은 숫자만 둔다.
        HStack(spacing: 3) {
            Image(systemName: symbolName)
            Text(text)
                .monospacedDigit()
        }
        // 앱 시작 지점이 여기다. SwiftUI 가 label 뷰를 다시 만들면 또 불릴 수 있으므로
        // `AppState.start()` 자체가 중복 호출을 막는다.
        .task { await state.start() }
    }

    private var summary: MenuBarSummary {
        MenuBarSummary(state: state)
    }

    private var text: String { summary.text }

    private var symbolName: String {
        guard state.hasCredentials else { return "key.slash" }
        if state.lastError?.needsUserAction == true { return "exclamationmark.triangle" }
        switch summary.direction {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .flat: return "minus"
        }
    }
}
