import SwiftUI
import ServiceManagement
import TossAssetMenuBarCore

/// 설정 탭. 계좌 선택, 표시 항목, 관심종목 필터, 허용 IP 안내, 키 삭제.
@MainActor
struct SettingsView: View {
    let state: AppState

    @State private var isConfirmingRemoval = false

    var body: some View {
        @Bindable var settings = state.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("버전") {
                    UpdateSection(state: state)
                }

                section("계좌") {
                    if state.accounts.isEmpty {
                        HStack {
                            Text("계좌를 불러오지 못했습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("다시 조회") {
                                Task { await state.loadAccountsIfNeeded(force: true) }
                            }
                            .controlSize(.small)
                        }
                    } else {
                        Picker("조회 계좌", selection: accountBinding) {
                            ForEach(state.accounts) { account in
                                Text(account.maskedAccountNo).tag(Optional(account.accountSeq))
                            }
                        }
                        .labelsHidden()
                    }
                }

                section("메뉴바 표시") {
                    Picker("표시 항목", selection: menuBarBinding) {
                        Text("전체 수익률").tag(MenuBarDisplayKind.totalRate)
                        Text("전체 손익금액").tag(MenuBarDisplayKind.totalProfitAmount)
                        Text("특정 종목 가격").tag(MenuBarDisplayKind.symbolPrice)
                        Text("특정 종목 수익률").tag(MenuBarDisplayKind.symbolRate)
                    }
                    .labelsHidden()

                    // 종목 기준 표시를 골랐으면 어떤 종목인지 정해야 한다.
                    if menuBarBinding.wrappedValue.needsSymbol {
                        if state.settings.watchlist.isEmpty {
                            Text("관심종목 탭에서 종목을 먼저 추가해 주세요.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("종목", selection: menuBarSymbolBinding) {
                                ForEach(state.settings.watchlist, id: \.self) { symbol in
                                    Text(state.watchlistInfo[symbol]?.displayName ?? symbol).tag(symbol)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                section("표시 방식") {
                    Toggle("세금·수수료 공제 후 금액으로 보기", isOn: $settings.showAfterCost)
                    Toggle("수익률 탭에 관심종목만 표시", isOn: $settings.onlyShowWatchlistInPortfolio)
                    Picker("새로고침 주기", selection: refreshBinding) {
                        ForEach(AppSettings.allowedRefreshIntervals, id: \.self) { seconds in
                            Text(Self.intervalLabel(seconds)).tag(seconds)
                        }
                    }
                }

                section("허용 IP") {
                    Text("토스증권 Open API 는 WTS 설정에 등록한 IP 에서만 호출할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        // 아직 확인하지 않았으면 아무것도 두지 않는다.
                        // 오른쪽 `현재 IP 확인` 버튼이 이미 그 상태를 말해준다.
                        if let ip = state.publicIP {
                            Text(ip).font(.callout.monospaced())
                            Button("복사") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ip, forType: .string)
                            }
                            .controlSize(.small)
                        }
                        Spacer()
                        Button(state.isLookingUpIP ? "확인 중" : "현재 IP 확인") {
                            Task { await state.lookUpPublicIP() }
                        }
                        .controlSize(.small)
                        .disabled(state.isLookingUpIP)
                    }

                    HStack(spacing: 3) {
                        Link("토스증권 열기", destination: URL(string: "https://www.tossinvest.com")!)
                            .font(.caption)
                        Text("→")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("설정")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                        Text("Open API")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                        Text("허용 IP 관리")
                            .font(.caption.weight(.medium))
                    }
                }

                section("실행") {
                    Toggle("로그인 시 자동 실행", isOn: launchAtLoginBinding)
                }

                section("API 키") {
                    if isConfirmingRemoval {
                        HStack {
                            Text("Keychain 에서 키를 삭제할까요?").font(.caption)
                            Spacer()
                            Button("취소") { isConfirmingRemoval = false }
                                .controlSize(.small)
                            Button("삭제") {
                                isConfirmingRemoval = false
                                Task { await state.removeCredentials() }
                            }
                            .controlSize(.small)
                        }
                    } else {
                        Button("API 키 삭제") { isConfirmingRemoval = true }
                            .controlSize(.small)
                    }
                }

                Divider()

                HStack {
                    Text("조회 전용 앱입니다. 주문 기능은 포함하지 않습니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("종료") { NSApplication.shared.terminate(nil) }
                        .controlSize(.small)
                }
            }
            .padding(14)
        }
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private static func intervalLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)초" : "\(seconds / 60)분"
    }

    // MARK: - 바인딩
    //
    // 계좌 변경은 API 클라이언트에도 반영해야 하고, 메뉴바 표시 항목은 연관값이 있는 enum 이라
    // Picker 에 바로 물릴 수 없다. 그래서 수동 Binding 을 만든다.

    private var accountBinding: Binding<Int64?> {
        Binding(
            get: { state.settings.accountSeq },
            set: { newValue in
                Task {
                    await state.selectAccount(newValue)
                    await state.refresh()
                }
            }
        )
    }

    private var refreshBinding: Binding<Int> {
        Binding(
            get: { state.settings.refreshInterval },
            set: { newValue in
                state.settings.refreshInterval = newValue
                // 주기가 바뀌면 루프를 다시 시작해야 즉시 반영된다.
                state.startPolling()
            }
        )
    }

    private var menuBarBinding: Binding<MenuBarDisplayKind> {
        Binding(
            get: { MenuBarDisplayKind(state.settings.menuBarDisplay) },
            set: { kind in
                let symbol = state.settings.menuBarDisplay.symbol
                    ?? state.settings.watchlist.first
                    ?? ""
                state.settings.menuBarDisplay = kind.display(symbol: symbol)
            }
        )
    }

    private var menuBarSymbolBinding: Binding<String> {
        Binding(
            get: { state.settings.menuBarDisplay.symbol ?? state.settings.watchlist.first ?? "" },
            set: { symbol in
                let kind = MenuBarDisplayKind(state.settings.menuBarDisplay)
                state.settings.menuBarDisplay = kind.display(symbol: symbol)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { shouldEnable in
                // 서명되지 않은 개발 빌드에서는 실패할 수 있다. 실패해도 앱 동작에는 영향이 없다.
                try? shouldEnable
                    ? SMAppService.mainApp.register()
                    : SMAppService.mainApp.unregister()
            }
        )
    }
}

