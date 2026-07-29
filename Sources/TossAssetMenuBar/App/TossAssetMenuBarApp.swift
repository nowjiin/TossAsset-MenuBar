import SwiftUI
import TossAssetMenuBarCore

@main
struct TossAssetMenuBarApp: App {
    @State private var state = AppState()

    var body: some Scene {
        // `.window` 스타일이라야 팝오버 안에 TabView 같은 임의의 SwiftUI 뷰를 넣을 수 있다.
        // 기본 `.menu` 스타일은 메뉴 항목만 받는다.
        MenuBarExtra {
            RootTabView(state: state)
                .frame(width: 380, height: 520)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}
