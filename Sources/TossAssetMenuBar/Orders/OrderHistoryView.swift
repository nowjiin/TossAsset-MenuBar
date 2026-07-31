import SwiftUI
import TossAssetMenuBarCore

/// 매매 내역 탭. 종료된 주문(체결·취소·거부)을 최근 것부터 보여준다.
///
/// **조회 전용이다.** 주문을 내거나 취소하는 동작은 이 화면에도, 이 앱 어디에도 없다.
@MainActor
struct OrderHistoryView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 8) {
            header

            if state.settings.accountSeq == nil {
                EmptyStateView(
                    title: "계좌를 선택해 주세요",
                    message: "설정 탭에서 조회할 계좌를 고르면 매매 내역을 볼 수 있습니다.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            } else if state.isLoadingOrders, state.orderHistory.isEmpty {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if state.orderHistory.isEmpty {
                EmptyStateView(
                    title: "매매 내역이 없습니다",
                    message: "최근 90일 동안 종료된 주문이 없습니다.",
                    systemImage: "clock.arrow.circlepath"
                )
            } else if state.visibleOrders.isEmpty {
                // 필터를 걸었더니 아무것도 없는 경우. 내역 자체가 없는 것과 구분해야 한다.
                EmptyStateView(
                    title: "해당 종목 내역이 없습니다",
                    message: "최근 90일 동안 \(state.orderSymbolFilter ?? "") 거래가 없습니다.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } else {
                list
            }
        }
        .padding(12)
        // 탭을 열 때 한 번만 불러온다. 이미 불러왔으면 다시 호출하지 않는다.
        .task { await state.loadOrderHistory() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("최근 90일")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let count = countLabel {
                Text(count)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            symbolFilter

            Button {
                Task { await state.loadOrderHistory(force: true) }
            } label: {
                if state.isLoadingOrders {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(state.isLoadingOrders || state.settings.accountSeq == nil)
        }
    }

    private var countLabel: String? {
        guard !state.orderHistory.isEmpty else { return nil }
        return "\(state.visibleOrders.count)건"
    }

    /// 종목 필터. 선택지는 실제로 거래한 종목에서만 만든다 —
    /// 보유 종목이나 관심종목으로 만들면 지금은 보유하지 않는 과거 거래를 고를 수 없다.
    @ViewBuilder
    private var symbolFilter: some View {
        if state.orderHistorySymbols.count > 1 {
            Picker("종목", selection: filterSelection) {
                Text("전체").tag("")
                Divider()
                ForEach(state.orderHistorySymbols, id: \.self) { symbol in
                    Text(symbol).tag(symbol)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 110)
            .disabled(state.isLoadingOrders)
        }
    }

    /// `Picker` 는 `nil` 태그를 다루기 번거로우므로 빈 문자열을 "전체" 로 쓴다.
    private var filterSelection: Binding<String> {
        Binding(
            get: { state.orderSymbolFilter ?? "" },
            set: { new in
                Task { await state.setOrderSymbolFilter(new.isEmpty ? nil : new) }
            }
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(state.visibleOrders) { order in
                    OrderRow(order: order)
                    Divider()
                }

                // 페이지 상한에 걸려 잘렸다는 것을 알려야 한다. 조용히 자르면
                // 사용자는 이게 전체 내역이라고 믿는다.
                if state.orderHistoryHasMore {
                    Text("표시할 수 있는 범위를 넘었습니다. 더 오래된 내역은 토스증권에서 확인해 주세요.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
        }
    }
}
