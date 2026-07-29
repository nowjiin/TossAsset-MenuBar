import Foundation

/// 그룹별 TPS 를 클라이언트 쪽에서 선제적으로 지키는 게이트.
///
/// 429 를 맞고 나서 백오프하는 것보다, 애초에 초당 허용량을 넘기지 않는 게 낫다.
/// 각 그룹마다 "다음 호출 가능 시각" 을 두고 최소 간격(1/TPS)을 강제한다.
/// 429 를 받으면 `Retry-After` 만큼 해당 그룹 전체를 잠근다.
public actor RateLimitGate {
    private var nextAllowed: [RateLimitGroup: ContinuousClock.Instant] = [:]
    /// 응답 헤더 `X-RateLimit-Limit` 으로 관측한 실제 허용치. 문서 기본값보다 우선한다.
    private var observedLimit: [RateLimitGroup: Double] = [:]
    private let clock = ContinuousClock()

    public init() {}

    /// 호출 직전에 await 한다. 필요하면 그만큼 잠들었다가 돌아온다.
    public func waitForSlot(_ group: RateLimitGroup) async {
        let interval = minimumInterval(for: group)
        let now = clock.now
        let scheduled = max(now, nextAllowed[group] ?? now)
        nextAllowed[group] = scheduled.advanced(by: interval)

        if scheduled > now {
            try? await clock.sleep(until: scheduled)
        }
    }

    /// 429 수신 시 그룹 전체를 지연시킨다. `Retry-After` 가 없으면 시도 횟수에 따라 지수 백오프.
    public func penalize(_ group: RateLimitGroup, retryAfter: TimeInterval?, attempt: Int) {
        let seconds = retryAfter ?? backoffSeconds(attempt: attempt)
        let until = clock.now.advanced(by: .seconds(seconds))
        nextAllowed[group] = max(nextAllowed[group] ?? until, until)
    }

    /// 정상 응답의 `X-RateLimit-Limit` 을 반영한다.
    public func observe(limit: Double, for group: RateLimitGroup) {
        guard limit > 0 else { return }
        observedLimit[group] = limit
    }

    private func minimumInterval(for group: RateLimitGroup) -> Duration {
        let tps = observedLimit[group] ?? group.defaultRequestsPerSecond
        // 경계에서 아슬아슬하게 걸리는 걸 피하려고 5% 여유를 둔다.
        let seconds = 1.0 / max(tps, 0.1) * 1.05
        return .milliseconds(Int(seconds * 1000))
    }

    /// 1s → 2s → 4s (최대 8s) + jitter. 여러 클라이언트가 동시에 재시도해 몰리는 걸 막는다.
    private func backoffSeconds(attempt: Int) -> TimeInterval {
        let base = min(pow(2.0, Double(max(attempt, 0))), 8)
        let jitter = Double.random(in: 0...0.3)
        return base + jitter
    }
}
