import Foundation

/// 업데이트 자동 확인 주기 판정.
///
/// 앱 로직에 두지 않고 여기 두는 이유는 검증 가능성이다 — 시각을 주입해 경계를 확인할 수 있다.
public enum UpdateSchedule {
    /// 하루에 한 번. 릴리스가 그보다 자주 나오지 않고, GitHub 조회 한도도 아낀다.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// 자동 확인을 할 때가 되었는가.
    ///
    /// 한 번도 확인하지 않았으면 바로 확인한다.
    /// 시스템 시계가 뒤로 돌아가 `lastCheckedAt` 이 미래가 되는 경우도 확인 대상으로 본다 —
    /// 그러지 않으면 시계를 되돌린 만큼 영구히 확인하지 않게 된다.
    public static func isDue(lastCheckedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastCheckedAt else { return true }
        let elapsed = now.timeIntervalSince(lastCheckedAt)
        if elapsed < 0 { return true }
        return elapsed >= interval
    }
}
