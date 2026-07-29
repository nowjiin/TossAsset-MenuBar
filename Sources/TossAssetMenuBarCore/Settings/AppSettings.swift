import Foundation
import Observation

/// 메뉴바에 무엇을 띄울지.
public enum MenuBarDisplay: Sendable, Hashable, Codable {
    /// 전체 수익률 (예: `+11.79%`)
    case totalRate
    /// 전체 손익금액 (원화 환산)
    case totalProfitAmount
    /// 특정 종목의 현재가
    case symbolPrice(symbol: String)
    /// 특정 종목의 수익률 (보유 중일 때만)
    case symbolRate(symbol: String)

    public var symbol: String? {
        switch self {
        case .symbolPrice(let symbol), .symbolRate(let symbol): symbol
        case .totalRate, .totalProfitAmount: nil
        }
    }
}

/// 사용자 설정. 민감하지 않은 값만 다루므로 UserDefaults 를 쓴다.
/// 키(client_id/secret)는 여기 들어오지 않는다 — `KeychainStore` 담당이다.
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.watchlist = Self.loadWatchlist(defaults)
        self.accountSeq = defaults.object(forKey: Keys.accountSeq) as? Int64
        self.refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 30
        self.showAfterCost = defaults.bool(forKey: Keys.showAfterCost)
        self.menuBarDisplay = Self.loadMenuBarDisplay(defaults)
        self.onlyShowWatchlistInPortfolio = defaults.bool(forKey: Keys.onlyShowWatchlist)
        self.lastUpdateCheckAt = defaults.object(forKey: Keys.lastUpdateCheckAt) as? Date
    }

    /// 관심종목 심볼. 종목 이름 검색 API 가 없으므로 사용자가 심볼을 직접 넣는다.
    public var watchlist: [String] {
        didSet { defaults.set(watchlist, forKey: Keys.watchlist) }
    }

    public var accountSeq: Int64? {
        didSet {
            if let accountSeq {
                defaults.set(accountSeq, forKey: Keys.accountSeq)
            } else {
                defaults.removeObject(forKey: Keys.accountSeq)
            }
        }
    }

    /// 초 단위 폴링 주기. 선택 가능한 값은 `allowedRefreshIntervals`.
    public var refreshInterval: Int {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    /// 세금·수수료 공제 후 값을 보여줄지. 토스가 내려준 값을 고르는 것이고,
    /// 앱이 세율을 계산하지는 않는다.
    public var showAfterCost: Bool {
        didSet { defaults.set(showAfterCost, forKey: Keys.showAfterCost) }
    }

    public var menuBarDisplay: MenuBarDisplay {
        didSet {
            if let data = try? JSONEncoder().encode(menuBarDisplay) {
                defaults.set(data, forKey: Keys.menuBarDisplay)
            }
        }
    }

    /// 업데이트를 마지막으로 확인한 시각. 자동 확인 주기 판정에 쓴다.
    /// 확인이 실패한 경우에는 기록하지 않는다 — 실패했다고 하루를 기다릴 이유가 없다.
    public var lastUpdateCheckAt: Date? {
        didSet {
            if let lastUpdateCheckAt {
                defaults.set(lastUpdateCheckAt, forKey: Keys.lastUpdateCheckAt)
            } else {
                defaults.removeObject(forKey: Keys.lastUpdateCheckAt)
            }
        }
    }

    /// 수익률 탭에서 관심종목으로 등록한 종목만 보여줄지.
    /// "설정에서 특정한 주식 가격만 볼 수 있게" 하는 요구를 보유 목록에도 적용한 것.
    public var onlyShowWatchlistInPortfolio: Bool {
        didSet { defaults.set(onlyShowWatchlistInPortfolio, forKey: Keys.onlyShowWatchlist) }
    }

    public static let allowedRefreshIntervals = [15, 30, 60, 300]

    // MARK: - 관심종목 편집

    /// 이미 있으면 무시한다. 심볼 정규화는 `SymbolValidator` 가 담당한다.
    public func addToWatchlist(_ symbol: String) {
        let normalized = SymbolValidator.normalize(symbol)
        guard SymbolValidator.isValid(normalized), !watchlist.contains(normalized) else { return }
        watchlist.append(normalized)
    }

    public func removeFromWatchlist(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
    }

    // MARK: - 저장

    private enum Keys {
        static let watchlist = "watchlist"
        static let accountSeq = "accountSeq"
        static let refreshInterval = "refreshInterval"
        static let showAfterCost = "showAfterCost"
        static let menuBarDisplay = "menuBarDisplay"
        static let onlyShowWatchlist = "onlyShowWatchlistInPortfolio"
        static let lastUpdateCheckAt = "lastUpdateCheckAt"
    }

    // Bundle Identifier 가 바뀌면 UserDefaults 도메인도 함께 바뀌어 설정이 초기화된다.
    // 예전 도메인에서 옮겨오는 코드를 넣어봤지만 이 앱은 App Sandbox 를 쓰기 때문에 동작하지 않는다:
    // 설정이 `~/Library/Containers/<bundleID>/Data/Library/Preferences/` 안에 갇혀 있어서
    // 다른 Bundle Identifier 의 컨테이너를 읽을 수 없다.
    // 대신 Keychain 은 컨테이너 밖의 login keychain 을 쓰므로 `KeychainStore` 가 이전을 처리한다.
    // 설정은 계좌 자동 선택 + 관심종목 재입력으로 복구된다.

    private static func loadWatchlist(_ defaults: UserDefaults) -> [String] {
        (defaults.stringArray(forKey: Keys.watchlist) ?? [])
            .map(SymbolValidator.normalize)
            .filter(SymbolValidator.isValid)
    }

    private static func loadMenuBarDisplay(_ defaults: UserDefaults) -> MenuBarDisplay {
        guard let data = defaults.data(forKey: Keys.menuBarDisplay),
              let decoded = try? JSONDecoder().decode(MenuBarDisplay.self, from: data)
        else { return .totalRate }
        return decoded
    }
}

/// 심볼 형식 검증. 문서 기준으로 영문 대소문자·숫자·`.`·`-` 만 허용된다.
public enum SymbolValidator {
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func isValid(_ symbol: String) -> Bool {
        guard !symbol.isEmpty, symbol.count <= 20 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return symbol.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
