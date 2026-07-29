import SwiftUI
import TossAssetMenuBarCore

/// 각 탭 하단의 상태 줄: 마지막 갱신 시각, 폐장 표시, 다음 갱신 카운트다운, 수동 새로고침.
@MainActor
struct RefreshFooter: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 6) {
            if let lastUpdated = state.lastUpdated {
                // 앱의 기준 시간은 KST 고정이다. Mac 이 어느 타임존에 있어도 같은 값을 보여준다.
                Text("\(ValueFormatter.time(lastUpdated, in: .kst)) 기준")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                // 한 번도 성공한 조회가 없는 상태. 그냥 "조회 안 됨" 이라고만 하면
                // 사용자가 무엇을 해야 하는지 알 수 없으므로 이유를 나눠 보여준다.
                Text(neverLoadedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // 자동 갱신이 멈춰 있다는 걸 알려준다. 값이 안 변하는 게 버그로 보이지 않게.
            if !state.isMarketOpen {
                Text(closedLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            // TimelineView 는 이 뷰가 화면에 있을 때만 다시 그린다.
            // 메뉴바 팝오버가 닫히면 뷰가 사라지므로 초당 갱신이 백그라운드에서 계속되지 않는다.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    countdown(at: context.date)
                    refreshButton(at: context.date)
                }
            }
        }
    }

    /// 다음 자동 갱신까지 남은 시간. 폐장 중이거나 폴링이 멈춰 있으면 표시하지 않는다.
    @ViewBuilder
    private func countdown(at now: Date) -> some View {
        if state.isRefreshing {
            Text("갱신 중")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let remaining = remainingSeconds(at: now) {
            Text("\(ValueFormatter.countdown(seconds: remaining)) 후 갱신")
                .font(.caption2)
                .foregroundStyle(.secondary)
                // 숫자 폭이 흔들리면 옆의 버튼이 들썩인다.
                .monospacedDigit()
        }
    }

    /// 남은 시간을 링으로도 보여준다. 숫자를 안 읽어도 진행 정도가 보인다.
    private func refreshButton(at now: Date) -> some View {
        Button {
            Task { await state.refreshNow() }
        } label: {
            ZStack {
                if let progress = remainingProgress(at: now), !state.isRefreshing {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        // 12시 방향에서 시작해 시계방향으로 줄어들게 한다.
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                }
                if state.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(state.isRefreshing)
        .help("지금 갱신하고 타이머를 다시 시작합니다")
    }

    private func remainingSeconds(at now: Date) -> Int? {
        guard state.isMarketOpen, let nextRefreshAt = state.nextRefreshAt else { return nil }
        // ceil 로 올려야 "1초"에서 바로 0 으로 튀지 않고 1초를 온전히 보여준다.
        return max(0, Int(nextRefreshAt.timeIntervalSince(now).rounded(.up)))
    }

    private func remainingProgress(at now: Date) -> CGFloat? {
        guard let remaining = remainingSeconds(at: now) else { return nil }
        let interval = max(1, state.settings.refreshInterval)
        return min(1, max(0, CGFloat(remaining) / CGFloat(interval)))
    }

    /// 아직 성공한 조회가 없을 때의 문구.
    private var neverLoadedLabel: String {
        if state.isRefreshing { return "조회 중" }
        if state.lastError != nil { return "조회 실패" }
        if state.settings.accountSeq == nil { return "계좌를 선택하면 조회합니다" }
        return "조회 준비 중"
    }

    /// 폐장 중 표시. 다음 개장을 그 시장의 현지 시간으로 보여준다.
    /// 국내 장이면 KST, 미국 장이면 미국 동부 시간이다.
    private var closedLabel: String {
        guard let opening = state.nextMarketOpening else { return "· 폐장" }
        let time = ValueFormatter.timeWithDayIfNeeded(opening.date, in: opening.displayTimeZone)
        return "· 폐장 (\(opening.marketLabel) \(time) 개장)"
    }
}
