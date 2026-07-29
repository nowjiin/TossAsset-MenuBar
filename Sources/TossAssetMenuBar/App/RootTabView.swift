import SwiftUI
import TossAssetMenuBarCore

/// 팝오버 본문. 탭바로 수익률 / 관심종목 / 설정을 나눈다.
@MainActor
struct RootTabView: View {
    let state: AppState

    var body: some View {
        if state.hasCredentials {
            TabView {
                PortfolioView(state: state)
                    .tabItem { Label("수익률", systemImage: "chart.line.uptrend.xyaxis") }
                WatchlistView(state: state)
                    .tabItem { Label("관심종목", systemImage: "star") }
                SettingsView(state: state)
                    // 자동 확인으로 새 버전을 찾아도 설정 탭을 열지 않으면 알 수 없다.
                    // 탭 라벨에 점을 붙여 그쪽을 보게 만든다.
                    .tabItem {
                        Label(
                            state.hasUpdateAvailable ? "설정 ●" : "설정",
                            systemImage: state.hasUpdateAvailable
                                ? "gearshape.badge.checkmark"
                                : "gearshape"
                        )
                    }
            }
            .padding(.top, 6)
            // 폐장 중에는 폴링이 멈춰 있으므로, 팝오버를 열 때 한 번 갱신한다.
            .task { await state.refreshOnAppear() }
        } else {
            OnboardingView(state: state)
        }
    }
}
