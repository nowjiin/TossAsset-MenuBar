import SwiftUI
import TossAssetMenuBarCore

/// 관심종목 탭. 보유 여부와 무관하게 설정에 등록한 종목의 현재가만 본다.
@MainActor
struct WatchlistView: View {
    let state: AppState

    @State private var input = ""
    @State private var isAdding = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 8) {
            addField

            if let addError {
                NoticeBanner(message: addError, tint: .red)
            }

            if state.settings.watchlist.isEmpty {
                EmptyStateView(
                    title: "관심종목이 없습니다",
                    message: "종목 심볼을 입력해 추가하세요. 국내는 005930 처럼 6자리 숫자, 해외는 AAPL 처럼 티커를 씁니다.",
                    systemImage: "star"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.settings.watchlist, id: \.self) { symbol in
                            WatchlistRow(
                                symbol: symbol,
                                info: state.watchlistInfo[symbol],
                                price: state.watchlistPrices[symbol],
                                onRemove: { state.removeWatchlistSymbol(symbol) }
                            )
                            Divider()
                        }
                    }
                }
            }

            RefreshFooter(state: state)
        }
        .padding(12)
    }

    private var addField: some View {
        HStack(spacing: 6) {
            TextField("종목 심볼 (예: 005930, AAPL)", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }
                .disabled(isAdding)
            Button {
                add()
            } label: {
                if isAdding {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                }
            }
            .disabled(isAdding || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// 심볼이 실제로 존재하는지 API 로 확인한 뒤에만 추가한다.
    /// 종목명 검색 API 가 없어서 오타를 걸러줄 다른 방법이 없다.
    private func add() {
        let raw = input
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAdding = true
        addError = nil
        Task {
            if let error = await state.addWatchlistSymbol(raw) {
                addError = error.userMessage
            } else {
                input = ""
            }
            isAdding = false
        }
    }
}

