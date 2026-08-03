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

            if !state.searchResults.isEmpty {
                searchResults
            }

            if state.settings.watchlist.isEmpty {
                EmptyStateView(
                    title: "관심종목이 없습니다",
                    message: "종목명으로 찾거나 심볼을 직접 입력하세요. 삼성전자 처럼 이름으로 치면 후보가 뜨고, 005930 · AAPL 처럼 심볼을 치면 바로 추가됩니다.",
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

    /// 이름으로 찾은 후보. 눌러서 바로 추가한다.
    ///
    /// 여기 보이는 이름은 **사전에 적힌 값**이다. 추가한 뒤 목록에 남는 이름은 토스 `/stocks`
    /// 가 준 값이라, 사전 매핑이 틀렸다면 다른 이름이 나타나 바로 눈에 띈다.
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(state.searchResults) { result in
                Button {
                    add(symbol: result.symbol)
                } label: {
                    HStack(spacing: 6) {
                        Text(result.name)
                            .font(.callout)
                            .lineLimit(1)
                        Text(result.symbol)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
                Divider()
            }
        }
        .padding(.horizontal, 2)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addField: some View {
        HStack(spacing: 6) {
            TextField("종목명 또는 심볼 (예: 삼성전자, 005930, AAPL)", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }
                .disabled(isAdding)
                // 로컬 목록을 훑을 뿐이라 글자마다 바로 반영해도 된다.
                .onChange(of: input) { _, new in state.searchStocks(new) }
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

    /// 심볼이 실제로 존재하는지 토스 API 로 확인한 뒤에만 추가한다.
    ///
    /// 이름 검색으로 고른 후보도 예외가 아니다. 검색은 심볼을 알아내는 데까지만 쓰고,
    /// 존재 여부·종목명·통화는 토스가 준 값으로 확정한다.
    private func add(symbol: String? = nil) {
        let raw = symbol ?? input
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAdding = true
        addError = nil
        Task {
            if let error = await state.addWatchlistSymbol(raw) {
                addError = error.userMessage
            } else {
                input = ""
                state.clearSearch()
            }
            isAdding = false
        }
    }
}

