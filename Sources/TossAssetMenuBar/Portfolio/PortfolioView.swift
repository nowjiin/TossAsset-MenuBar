import SwiftUI
import TossAssetMenuBarCore

/// 수익률 탭. 전체·국내·해외를 세그먼트로 골라 본다.
///
/// 국내와 해외는 거래 통화가 달라서(원/달러) 요약 금액의 단위도 함께 바뀐다.
/// 해외를 골랐을 때만 원화 환산값을 한 줄 더 붙인다.
@MainActor
struct PortfolioView: View {
    let state: AppState

    @State private var region: HoldingsRegion = .total

    var body: some View {
        VStack(spacing: 8) {
            // 조치가 필요한 오류든 일시적인 오류든 일단 보여준다.
            // 조용히 삼키면 값이 갱신되지 않는 이유를 사용자가 알 방법이 없다.
            if let error = state.lastError {
                NoticeBanner(
                    message: error.userMessage,
                    tint: error.needsUserAction ? .orange : .secondary,
                    action: bannerAction(for: error)
                )
            }

            if let holdings = state.holdings {
                let breakdown = RegionBreakdown(
                    overview: holdings,
                    usdToKrw: state.usdToKrw,
                    showAfterCost: state.settings.showAfterCost
                )

                regionPicker
                summary(breakdown)
                Divider()
                itemList
            } else if state.settings.accountSeq == nil {
                EmptyStateView(
                    title: "계좌를 선택해 주세요",
                    message: "설정 탭에서 조회할 계좌를 고르면 보유 주식이 표시됩니다.",
                    systemImage: "creditcard"
                )
            } else {
                EmptyStateView(
                    title: "불러오는 중",
                    message: "보유 주식을 조회하고 있습니다.",
                    systemImage: "clock"
                )
            }

            RefreshFooter(state: state)
        }
        .padding(12)
    }

    private var regionPicker: some View {
        Picker("", selection: $region) {
            ForEach(HoldingsRegion.displayOrder, id: \.self) { candidate in
                Text(candidate.label).tag(candidate)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - 요약

    @ViewBuilder
    private func summary(_ breakdown: RegionBreakdown) -> some View {
        let selected = breakdown.summary(for: region)

        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let rate = selected.rate {
                    Text(ValueFormatter.signedPercent(TossDecimal(rate)))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(ChangeColor.of(rate))
                        .monospacedDigit()
                } else {
                    // 투자원금이 0 이면 수익률을 정의할 수 없다.
                    Text("—")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // 국내와 미국은 개장 시간이 달라서, 지금 이 숫자가 움직이는지 알려준다.
                //
                // "장중/폐장" 은 시장의 상태를 말한다. 정작 알고 싶은 건 "이 숫자가 살아 있는지"
                // 라서 한 단계 더 추론해야 한다. 값의 성격을 직접 말해주는 쪽이 낫다.
                // 프리·애프터마켓도 개장으로 판정하므로, 닫혔다고 표시할 때는 실제로 종가다.
                if let market = region.marketCountry {
                    let isOpen = state.openMarkets.contains(market)
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isOpen ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 5, height: 5)
                        Text(isOpen ? "현재가" : "종가")
                    }
                    .font(.caption2)
                    .foregroundStyle(isOpen ? .green : .secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(amount(selected.profitAmount, signed: true))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(ChangeColor.of(selected.profitAmount))
                        .monospacedDigit()
                    Text("\(selected.itemCount)종목 손익")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if selected.isEmpty {
                Text(emptyRegionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                StatRow(label: "평가금액", value: amount(selected.marketValue))
                StatRow(label: "투자원금", value: amount(selected.purchaseAmount))
                StatRow(
                    label: "일간 손익",
                    value: amount(selected.dailyProfitAmount, signed: true),
                    valueColor: ChangeColor.of(selected.dailyProfitAmount)
                )

                // 해외 금액은 달러라 국내와 견주기 어렵다. 환산값을 한 줄 더 준다.
                if region == .overseas, let inKRW = selected.marketValueInKRW {
                    StatRow(label: "평가금액 (원화 환산)", value: ValueFormatter.krw(inKRW))
                }

                // 전체를 볼 때만 국내 대 해외 비중을 보여준다.
                if region == .total {
                    shareBar(breakdown)
                }
            }

            if breakdown.overseas.isEmpty == false, state.usdToKrw == nil {
                Text("환율을 아직 받지 못해 원화 환산과 비중을 계산할 수 없습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 국내 대 해외 비중. 환율을 모르면 그릴 수 없다.
    @ViewBuilder
    private func shareBar(_ breakdown: RegionBreakdown) -> some View {
        if let domesticShare = breakdown.domestic.share,
           let overseasShare = breakdown.overseas.share,
           !breakdown.overseas.isEmpty {
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: width(domesticShare, in: geometry.size.width))
                        Rectangle()
                            .fill(Color.orange)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 8)

                HStack(spacing: 8) {
                    legend(color: .accentColor, label: "국내", share: domesticShare)
                    legend(color: .orange, label: "해외", share: overseasShare)
                    Spacer()
                }
            }
            .padding(.top, 2)
        }
    }

    /// 비중이 아주 작아도 막대가 보이도록 최소 폭을 준다.
    private func width(_ share: Decimal, in total: CGFloat) -> CGFloat {
        let ratio = CGFloat(truncating: share as NSDecimalNumber)
        return max(2, min(total - 2, total * ratio))
    }

    private func legend(color: Color, label: String, share: Decimal) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(ValueFormatter.percent(share))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// 선택한 권역의 통화로 금액을 표시한다. 전체는 원화 환산 기준이다.
    private func amount(_ value: Decimal, signed: Bool = false) -> String {
        switch region {
        case .domestic, .total: ValueFormatter.krw(value, signed: signed)
        case .overseas: ValueFormatter.usd(value, signed: signed)
        }
    }

    private var emptyRegionMessage: String {
        switch region {
        case .domestic: "국내 보유 종목이 없습니다."
        case .overseas: "해외 보유 종목이 없습니다."
        case .total: "보유 중인 주식이 없습니다."
        }
    }

    // MARK: - 보유 종목

    /// 권역 필터와 설정의 관심종목 필터를 함께 적용한다.
    private var visibleItems: [HoldingsItem] {
        state.visibleHoldings.filter { region.contains($0) }
    }

    private var itemList: some View {
        let items = visibleItems
        return Group {
            if items.isEmpty {
                EmptyStateView(
                    title: "표시할 종목이 없습니다",
                    message: state.settings.onlyShowWatchlistInPortfolio
                        ? "설정에서 관심종목만 보기가 켜져 있습니다."
                        : emptyRegionMessage,
                    systemImage: "list.bullet"
                )
            } else {
                // `LazyVStack` 대신 `List` 를 쓰는 이유는 **끌어서 순서 바꾸기** 때문이다.
                // macOS 의 `List` 는 `onMove` 가 붙어 있으면 편집 모드 없이 바로 끌 수 있다.
                // 기본 배경·여백은 팝오버와 어울리지 않아 걷어내고 행 여백을 직접 맞춘다.
                List {
                    ForEach(items) { item in
                        // 개장 여부는 종목이 상장된 시장으로 판단한다. 세그먼트로 판단하면
                        // `전체` 에서 국내·해외가 섞였을 때 한쪽이 틀린 라벨을 달게 된다.
                        HoldingRow(
                            item: item,
                            showAfterCost: state.settings.showAfterCost,
                            isMarketOpen: state.openMarkets.contains(item.marketCountry),
                            dailyChange: state.dailyChangeRate(for: item)
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        // 보이는 목록의 심볼을 함께 넘긴다. 세그먼트나 관심종목 필터가 걸려 있으면
                        // 이건 전체가 아니라 부분 집합이고, 그 사실을 상태 쪽이 알아야 한다.
                        state.moveHoldings(
                            visibleSymbols: items.map(\.symbol),
                            from: source,
                            to: destination
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func bannerAction(for error: TossAPIError) -> (title: String, run: () -> Void)? {
        guard case .ipNotAllowed = error else { return nil }
        return ("현재 IP 확인하기", { Task { await state.lookUpPublicIP() } })
    }
}

