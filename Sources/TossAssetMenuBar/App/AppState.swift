import Foundation
import Observation
import TossAssetMenuBarCore

/// 앱 전체 상태와 갱신 루프를 담당한다.
///
/// 조회 전용 앱이므로 여기서 하는 일은 "주기적으로 읽어서 화면에 반영" 뿐이다.
@MainActor
@Observable
final class AppState {
    let settings: AppSettings
    private let keychain: KeychainStore
    private let client: TossAPIClient
    private let ipProvider = PublicIPProvider()
    /// 릴리스를 배포하는 저장소. `Scripts/install.sh` 의 기본값과 같아야 한다.
    private let updateChecker = UpdateChecker(repository: "nowjiin/TossAsset-MenuBar")

    // MARK: - 화면이 관찰하는 상태

    /// 키가 등록되어 있는지. 없으면 온보딩을 띄운다.
    var hasCredentials = false
    var accounts: [Account] = []
    var holdings: HoldingsOverview?
    /// 관심종목 현재가. 심볼 → 가격.
    var watchlistPrices: [String: StockPrice] = [:]
    /// 관심종목 종목명. 심볼 → 종목 정보.
    var watchlistInfo: [String: StockInfo] = [:]
    var lastUpdated: Date?
    var lastError: TossAPIError?
    var isRefreshing = false

    /// 매매 내역. 폴링 대상이 아니라 탭을 열 때 한 번 불러온다.
    var orderHistory: [OrderRecord] = []
    var isLoadingOrders = false
    /// 페이지 상한에 걸려 더 남았는지. 목록 끝에 안내를 띄우는 데 쓴다.
    var orderHistoryHasMore = false
    var orderHistoryLoadedAt: Date?
    /// 선택된 종목 필터. `nil` 이면 전체다.
    var orderSymbolFilter: String?
    /// 필터 선택지. **전체 조회 결과에서만** 갱신한다.
    var orderHistorySymbols: [String] = []
    /// 지금 담긴 목록이 어떤 종목으로 좁혀 받아온 것인지. `nil` 이면 전체 조회 결과다.
    private var orderHistoryScope: String?

    /// 허용 IP 안내용. 사용자가 복사해서 토스증권 설정에 넣는다.
    var publicIP: String?
    var isLookingUpIP = false

    /// 업데이트 확인 결과. 확인 전에는 nil.
    var updateStatus: UpdateStatus?
    var isCheckingUpdate = false

    /// 장 운영 시간. 폐장 중에는 폴링을 멈춘다.
    var marketHours: MarketHours?

    /// 다음 자동 갱신 예정 시각. 푸터의 카운트다운이 이 값을 기준으로 매초 다시 그린다.
    /// 폴링이 멈춰 있으면 nil.
    var nextRefreshAt: Date?

    // MARK: - 내부

    private var exchangeRate: ExchangeRate?
    private var pollingTask: Task<Void, Never>?
    /// 캘린더를 받아둔 날짜(로컬 기준). 날짜가 넘어가면 다시 받는다.
    private var marketHoursDay: Date?

    init(settings: AppSettings? = nil, keychain: KeychainStore = KeychainStore()) {
        #if DEBUG
        // 데모 모드는 별도 UserDefaults 를 써서 실제 설정을 건드리지 않는다.
        if settings == nil, DemoData.isEnabled,
           let demoDefaults = UserDefaults(suiteName: DemoData.defaultsSuiteName) {
            self.settings = AppSettings(defaults: demoDefaults)
        } else {
            self.settings = settings ?? AppSettings()
        }
        #else
        self.settings = settings ?? AppSettings()
        #endif
        self.keychain = keychain
        self.client = TossAPIClient()
    }

    /// 앱 시작 시 한 번만 호출되어야 한다.
    ///
    /// 호출 지점이 `MenuBarExtra` 의 label 에 붙은 `.task` 라서, SwiftUI 가 label 뷰를 다시 만들면
    /// 또 불릴 수 있다. 그때마다 Keychain 을 다시 읽으면 접근 프롬프트가 중복으로 뜬다.
    private var didStart = false

    /// 마지막으로 Keychain 에서 읽어온 키.
    ///
    /// 검증 실패 후 되돌릴 때 Keychain 을 다시 읽으면 접근 프롬프트가 또 뜬다.
    /// 그래서 읽은 값을 들고 있다가 되돌릴 때 재사용한다.
    private var loadedCredentials: TossCredentials?

    func start() async {
        guard !didStart else {
            AppLog.lifecycle.debug("start() 중복 호출 무시")
            return
        }
        didStart = true
        AppLog.lifecycle.info("start()")

        #if DEBUG
        // 스크린샷용 데모. API·Keychain 을 전혀 건드리지 않는다.
        if DemoData.isEnabled {
            AppLog.lifecycle.info("데모 모드 — 예시 데이터로 표시합니다")
            loadDemoData()
            return
        }
        #endif

        // 업데이트 확인을 Keychain 읽기보다 먼저 한다.
        //
        // `keychain.load()` 는 접근 프롬프트가 뜨면 그 자리에서 블록된다. 뒤에 두면 사용자가
        // 프롬프트를 방치하는 동안 업데이트 확인이 함께 멈춘다. 두 작업은 서로 무관하다.
        // 키 등록 여부와도 무관하므로 온보딩 중에도 최신 버전을 쓰게 된다.
        await checkForUpdateIfDue()

        // Keychain 읽기는 접근 프롬프트를 띄울 수 있으므로 한 번만 읽고 들고 있는다.
        let stored = keychain.load()
        loadedCredentials = stored
        hasCredentials = stored != nil
        await client.setCredentials(stored)
        await client.setAccountSeq(settings.accountSeq)

        guard hasCredentials else { return }
        await loadAccountsIfNeeded()
        await refreshMarketHoursIfNeeded()
        await refresh()
        startPolling()
    }

    /// 팝오버를 열 때 호출한다. 폐장 중에는 폴링이 멈춰 있으므로 이때 한 번 갱신해 준다.
    func refreshOnAppear() async {
        #if DEBUG
        if DemoData.isEnabled { return }
        #endif

        // 앱을 며칠 켜둔 채로도 하루가 지나면 확인되도록, 팝오버를 열 때도 주기를 따진다.
        // 별도 타이머를 두지 않는 이유는 팝오버를 열지 않으면 결과를 볼 사람도 없기 때문이다.
        await checkForUpdateIfDue()

        guard hasCredentials else { return }
        await refreshMarketHoursIfNeeded()
        // 방금 갱신했다면 또 부르지 않는다.
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 5 { return }
        await refresh()
    }

    /// 장 운영 시간은 하루 한 번만 받는다.
    private func refreshMarketHoursIfNeeded() async {
        if let marketHoursDay, Calendar.current.isDateInToday(marketHoursDay), marketHours != nil {
            return
        }
        let fetched = await client.marketHours()
        // 둘 다 실패했다면 캐시로 굳히지 않고 다음 기회에 다시 시도한다.
        guard !fetched.isUnknown else { return }
        marketHours = fetched
        marketHoursDay = Date()
    }

    /// 지금 폴링할 이유가 있는지. 캘린더를 못 받았으면 판단 근거가 없으니 그대로 폴링한다.
    var isMarketOpen: Bool {
        guard let marketHours, !marketHours.isUnknown else { return true }
        return marketHours.isAnyMarketOpen()
    }

    /// 폐장 중일 때 다음 개장. 어느 시장인지 함께 담고 있어 표시 타임존을 고를 수 있다.
    var nextMarketOpening: MarketOpening? {
        marketHours?.nextOpening()
    }

    /// 지금 열려 있는 시장들. 국내·미국이 겹치는 시간대도 있다.
    var openMarkets: [MarketCountry] {
        marketHours?.openMarkets() ?? []
    }

    // MARK: - 키 관리

    /// 온보딩·설정에서 키를 저장한다. 저장 전에 실제로 토큰이 발급되는지 확인한다.
    /// 성공하면 nil, 실패하면 사용자에게 보여줄 오류를 반환한다.
    func saveCredentials(clientID: String, clientSecret: String) async -> TossAPIError? {
        let credentials = TossCredentials(clientID: clientID, clientSecret: clientSecret)
        guard credentials.isComplete else { return .notConfigured }

        await client.setCredentials(credentials)
        do {
            try await client.verifyCredentials()
        } catch let error as TossAPIError {
            // 검증에 실패한 키는 저장하지 않는다.
            // Keychain 을 다시 읽으면 접근 프롬프트가 또 뜨므로 들고 있던 값으로 되돌린다.
            await client.setCredentials(loadedCredentials)
            if case .ipNotAllowed = error { await lookUpPublicIP() }
            return error
        } catch {
            return .transport(description: "확인에 실패했습니다.")
        }

        loadedCredentials = credentials
        guard keychain.save(credentials) else {
            return .server(status: 0, code: "keychain", message: "Keychain 에 저장할 수 없습니다.", requestId: nil)
        }
        hasCredentials = true
        lastError = nil
        await loadAccountsIfNeeded()
        await refresh()
        startPolling()
        return nil
    }

    func removeCredentials() async {
        stopPolling()
        keychain.clear()
        loadedCredentials = nil
        await client.setCredentials(nil)
        hasCredentials = false
        accounts = []
        holdings = nil
        watchlistPrices = [:]
        watchlistInfo = [:]
        lastUpdated = nil
        lastError = nil
    }

    // MARK: - 계좌

    /// `/accounts` 는 초당 1회 제한이므로 이미 목록이 있으면 다시 부르지 않는다.
    func loadAccountsIfNeeded(force: Bool = false) async {
        guard force || accounts.isEmpty else { return }
        do {
            let fetched = try await client.accounts()
            accounts = fetched
            // 계좌가 하나뿐이면 고민할 여지가 없으니 자동 선택한다.
            if settings.accountSeq == nil, let first = fetched.first {
                await selectAccount(first.accountSeq)
            } else if let selected = settings.accountSeq,
                      !fetched.contains(where: { $0.accountSeq == selected }) {
                // 저장된 계좌가 사라졌다면 선택을 비운다.
                await selectAccount(fetched.first?.accountSeq)
            }
        } catch let error as TossAPIError {
            handle(error)
        } catch {
            handle(.transport(description: "계좌 목록을 가져오지 못했습니다."))
        }
    }

    func selectAccount(_ seq: Int64?) async {
        settings.accountSeq = seq
        await client.setAccountSeq(seq)
    }

    var selectedAccount: Account? {
        accounts.first { $0.accountSeq == settings.accountSeq }
    }

    // MARK: - 갱신

    func refresh() async {
        #if DEBUG
        // 데모 모드에서는 네트워크를 타지 않는다. 새로고침 버튼도 무해하게 만든다.
        if DemoData.isEnabled {
            lastUpdated = Date()
            return
        }
        #endif

        guard hasCredentials, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var encountered: TossAPIError?

        if settings.accountSeq != nil {
            do {
                holdings = try await client.holdings()
            } catch let error as TossAPIError {
                encountered = error
            } catch {
                encountered = .transport(description: "보유 주식을 가져오지 못했습니다.")
            }
        }

        await refreshWatchlist(&encountered)
        await refreshExchangeRateIfStale()

        if let encountered {
            handle(encountered)
        } else {
            lastError = nil
            lastUpdated = Date()
        }
    }

    private func refreshWatchlist(_ encountered: inout TossAPIError?) async {
        let symbols = settings.watchlist
        guard !symbols.isEmpty else {
            watchlistPrices = [:]
            return
        }
        do {
            let prices = try await client.prices(symbols: symbols)
            watchlistPrices = Dictionary(uniqueKeysWithValues: prices.map { ($0.symbol, $0) })
        } catch let error as TossAPIError {
            encountered = encountered ?? error
        } catch {
            encountered = encountered ?? .transport(description: "현재가를 가져오지 못했습니다.")
        }

        // 종목명은 거의 바뀌지 않으므로 모르는 심볼만 채운다.
        let missing = symbols.filter { watchlistInfo[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            for info in try await client.stocks(symbols: missing) {
                watchlistInfo[info.symbol] = info
            }
        } catch {
            // 종목명은 없어도 가격 표시에 지장이 없다. 조용히 넘긴다.
        }
    }

    /// 환율은 응답의 `validUntil` 까지 유효하므로 그때까지 다시 부르지 않는다.
    ///
    /// 환율은 **부가 정보**다. 실패해도 보유 주식과 현재가는 이미 받아둔 상태이므로
    /// 전체 갱신을 실패로 처리하지 않는다. 원화 환산만 비활성되고 화면이 그 사실을 안내한다.
    private func refreshExchangeRateIfStale() async {
        if let exchangeRate, exchangeRate.validUntil > Date() { return }
        // 해외 종목이 없으면 환산할 대상이 없다.
        guard holdings?.marketValue.amount.usd != nil else { return }
        exchangeRate = try? await client.exchangeRate(base: .usd, quote: .krw)
    }

    /// USD → KRW 환산에 쓸 환율. 모르면 nil.
    var usdToKrw: Decimal? {
        guard let exchangeRate,
              exchangeRate.baseCurrency == .usd,
              exchangeRate.quoteCurrency == .krw
        else { return nil }
        return exchangeRate.midRate.value
    }

    private func handle(_ error: TossAPIError) {
        lastError = error
        // 허용 IP 문제는 사용자가 등록할 IP 를 알아야 조치할 수 있다.
        if case .ipNotAllowed = error {
            Task { await lookUpPublicIP() }
        }
    }

    // MARK: - 폴링

    /// 수동 새로고침. 자동 갱신 주기도 지금부터 다시 세도록 폴링을 재시작한다.
    /// 버튼을 눌렀는데 카운트다운이 그대로면 눌린 게 반영되지 않은 것처럼 보인다.
    func refreshNow() async {
        await refresh()
        startPolling()
    }

    func startPolling() {
        #if DEBUG
        // 데모 모드에서 폴링이 돌면 예시 데이터를 지우려 든다.
        if DemoData.isEnabled { return }
        #endif
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.settings.refreshInterval
                self.nextRefreshAt = Date().addingTimeInterval(TimeInterval(interval))
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                // 사용자 조치가 필요한 오류 상태에서는 같은 요청을 계속 던지지 않는다.
                if self.lastError?.needsUserAction == true { continue }
                // 날짜가 넘어갔으면 운영 시간을 다시 받는다.
                await self.refreshMarketHoursIfNeeded()
                // 폐장 중에는 시세가 움직이지 않으므로 부르지 않는다.
                // 팝오버를 열면 `refreshOnAppear` 가 한 번 갱신한다.
                guard self.isMarketOpen else { continue }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        nextRefreshAt = nil
    }

    // MARK: - 허용 IP 안내

    func lookUpPublicIP() async {
        guard !isLookingUpIP else { return }
        isLookingUpIP = true
        defer { isLookingUpIP = false }
        publicIP = await ipProvider.currentIPv4()
    }

    // MARK: - 업데이트

    /// `Info.plist` 의 `CFBundleShortVersionString`. 릴리스 태그와 같은 잣대로 비교한다.
    var currentVersion: AppVersion {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return raw.flatMap(AppVersion.init) ?? AppVersion(major: 0, minor: 0, patch: 0)
    }

    /// 설정 탭에 보여줄 버전 문구. 로컬 빌드면 `0.3.0 +3` 처럼 표식이 붙는다.
    var versionLabel: String {
        BuildLabel.display(
            shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            bundleVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    var installCommand: String { updateChecker.installCommand }

    /// 새 버전이 있는지. 설정 탭에 표시를 띄우는 데 쓴다.
    var hasUpdateAvailable: Bool {
        if case .available = updateStatus { return true }
        return false
    }

    /// 사용자가 버튼을 눌렀을 때. 주기와 무관하게 항상 확인한다.
    func checkForUpdate() async {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }

        let status = await updateChecker.check(current: currentVersion)
        updateStatus = status

        // 실패는 기록하지 않는다. 네트워크가 끊겼다고 하루를 기다릴 이유가 없다.
        // 다만 이유를 남긴다 — 기록이 안 된 게 실패 때문인지 버그인지 구분할 수 없으면
        // 나중에 원인을 찾기 어렵다.
        if case .failed(let message) = status {
            AppLog.network.info("업데이트 확인 실패: \(message, privacy: .public)")
            return
        }
        settings.lastUpdateCheckAt = Date()
    }

    /// 자동 확인. 마지막 확인으로부터 하루가 지났을 때만 실제로 조회한다.
    func checkForUpdateIfDue() async {
        guard UpdateSchedule.isDue(lastCheckedAt: settings.lastUpdateCheckAt) else { return }
        AppLog.lifecycle.info("업데이트 자동 확인")
        await checkForUpdate()
    }

    // MARK: - 관심종목

    /// 심볼을 실제로 조회해 보고 존재할 때만 관심종목에 넣는다.
    /// 종목 이름 검색 API 가 없으므로 이 검증이 사용자에게 유일한 피드백이다.
    func addWatchlistSymbol(_ raw: String) async -> TossAPIError? {
        let symbol = SymbolValidator.normalize(raw)
        guard SymbolValidator.isValid(symbol) else {
            return .symbolNotFound(symbol: raw)
        }
        guard !settings.watchlist.contains(symbol) else { return nil }

        do {
            let found = try await client.stocks(symbols: [symbol])
            guard let info = found.first else { return .symbolNotFound(symbol: symbol) }
            watchlistInfo[symbol] = info
            settings.addToWatchlist(symbol)
            await refresh()
            return nil
        } catch let error as TossAPIError {
            return error
        } catch {
            return .transport(description: "종목을 확인하지 못했습니다.")
        }
    }

    func removeWatchlistSymbol(_ symbol: String) {
        settings.removeFromWatchlist(symbol)
        watchlistPrices.removeValue(forKey: symbol)
        watchlistInfo.removeValue(forKey: symbol)
    }

    // MARK: - 매매 내역

    /// 매매 내역은 **폴링하지 않는다.** 거래를 해야 바뀌는 과거 데이터라 30초마다 조회하면
    /// `ORDER_HISTORY` 한도만 태운다. 탭을 열 때 한 번, 그리고 수동 새로고침으로만 가져온다.
    func loadOrderHistory(force: Bool = false) async {
        await loadOrderHistory(scope: orderHistoryScope, force: force)
    }

    /// 화면에 보여줄 매매 내역. 필터가 걸려 있으면 그 종목만 남긴다.
    ///
    /// 서버에서 이미 그 종목만 받아온 상태(`orderHistoryScope`)면 다시 걸러내지 않는다.
    var visibleOrders: [OrderRecord] {
        guard let symbol = orderSymbolFilter else { return orderHistory }
        if orderHistoryScope?.caseInsensitiveCompare(symbol) == .orderedSame { return orderHistory }
        return OrderHistoryFilter.apply(orderHistory, symbol: symbol)
    }

    /// 종목 필터를 바꾼다.
    ///
    /// 목록 전체를 이미 받아왔으면(`!orderHistoryHasMore`) **네트워크를 타지 않고 걸러낸다.**
    /// 반면 페이지 상한에 걸려 잘린 상태라면 걸러내기만 해서는 그 종목의 내역이 빠질 수 있으므로,
    /// 서버에 `symbol` 을 넘겨 다시 조회한다. 그래야 "AAPL 거래 전부" 라는 질문에 옳게 답한다.
    func setOrderSymbolFilter(_ symbol: String?) async {
        guard orderSymbolFilter != symbol else { return }
        orderSymbolFilter = symbol

        if let symbol {
            guard orderHistoryHasMore else { return }
            await loadOrderHistory(scope: symbol, force: true)
        } else if orderHistoryScope != nil {
            // 특정 종목만 받아둔 상태였으니 전체를 다시 가져와야 한다.
            await loadOrderHistory(scope: nil, force: true)
        }
    }

    private func loadOrderHistory(scope: String?, force: Bool) async {
        #if DEBUG
        if DemoData.isEnabled {
            orderHistory = DemoData.orders
            orderHistorySymbols = OrderHistoryFilter.symbols(in: DemoData.orders)
            orderHistoryLoadedAt = Date()
            return
        }
        #endif

        guard hasCredentials, settings.accountSeq != nil, !isLoadingOrders else { return }
        // 짧은 시간 안에 탭을 왕복할 때는 재조회하지 않되, 그보다 오래됐으면 다시 부른다.
        //
        // "한 번 불러왔으면 끝" 으로 두면 탭을 열어본 뒤 거래하고 다시 열었을 때 예전 목록이
        // 그대로 남는다. 그러면 새로고침 버튼을 눌러야 하는데, 사용자가 그걸 알아야 한다는
        // 것 자체가 문제다 — 방금 한 거래가 안 보이면 앱이 고장 난 것으로 읽힌다.
        guard force || isOrderHistoryStale else { return }

        isLoadingOrders = true
        defer { isLoadingOrders = false }

        do {
            // 진행 중 주문과 종료된 주문을 함께 보여준다.
            //
            // CLOSED 만 조회하면 **오늘 낸 주문이 아직 체결되지 않았을 때 목록에 없다.**
            // 지정가를 걸어두고 기다리는 중이 정확히 그 경우인데, 사용자에게는 "거래했는데
            // 안 보인다" 로 보인다. status 는 두 그룹으로 나뉘어 있어 한 번에 못 받으므로
            // 두 번 호출한다 (같은 ORDER_HISTORY 그룹, 탭 진입당 2회).
            let open = try await client.openOrders(symbol: scope)
            let closed = try await client.closedOrders(symbol: scope, days: Self.orderHistoryDays)
            orderHistory = (open + closed.orders).sorted { $0.displayDate > $1.displayDate }
            orderHistoryHasMore = closed.hasNext
            orderHistoryScope = scope
            // 선택지 목록은 **전체 조회 결과에서만** 갱신한다. 종목별 조회 결과로 덮으면
            // 선택지가 그 종목 하나로 줄어들어 다른 종목으로 옮겨갈 수 없게 된다.
            if scope == nil {
                orderHistorySymbols = OrderHistoryFilter.symbols(in: orderHistory)
            }
            orderHistoryLoadedAt = Date()
            lastError = nil
        } catch let error as TossAPIError {
            handle(error)
        } catch {
            handle(.transport(description: "매매 내역을 가져오지 못했습니다."))
        }
    }

    /// 기본 조회 범위(일). 클라이언트가 30일 구간으로 끊어 최신 구간부터 조회한다.
    private static let orderHistoryDays = 90

    /// 이 시간이 지나면 탭을 열 때 다시 불러온다. 폴링이 아니라 **탭 진입 시점**에만 본다.
    private static let orderHistoryFreshness: TimeInterval = 30

    private var isOrderHistoryStale: Bool {
        guard let loadedAt = orderHistoryLoadedAt else { return true }
        let elapsed = Date().timeIntervalSince(loadedAt)
        // 시스템 시계가 뒤로 돌아가면 음수가 된다. 그 경우도 다시 불러온다 —
        // 그러지 않으면 시계를 되돌린 만큼 영구히 갱신되지 않는다.
        return elapsed < 0 || elapsed >= Self.orderHistoryFreshness
    }

    #if DEBUG
    /// 스크린샷용. 네트워크·Keychain 을 건드리지 않고 화면만 채운다.
    private func loadDemoData() {
        settings.accountSeq = DemoData.accounts.first?.accountSeq
        settings.watchlist = DemoData.watchlist
        accounts = DemoData.accounts
        publicIP = DemoData.publicIP

        guard !DemoData.showsOnboarding else {
            // 키 등록 화면을 찍을 때는 데이터를 채우지 않는다.
            hasCredentials = false
            return
        }

        hasCredentials = true
        holdings = DemoData.holdings
        watchlistPrices = DemoData.prices
        watchlistInfo = DemoData.stockInfo
        // 원화 환산과 비중 막대가 보이도록 환율을 넣는다.
        exchangeRate = ExchangeRate(
            baseCurrency: .usd,
            quoteCurrency: .krw,
            rate: TossDecimal(DemoData.usdToKrw),
            midRate: TossDecimal(DemoData.usdToKrw),
            validFrom: Date(),
            validUntil: Date().addingTimeInterval(3600)
        )
        // 장중으로 보이게 한다 — `현재가` 표시와 카운트다운이 함께 나온다.
        marketHours = nil
        lastUpdated = Date()
        nextRefreshAt = Date().addingTimeInterval(TimeInterval(settings.refreshInterval))
    }
    #endif

    /// 수익률 탭에 보여줄 보유 종목. 설정에 따라 관심종목만 걸러내고, 사용자가 정한 순서를 적용한다.
    var visibleHoldings: [HoldingsItem] {
        guard let items = holdings?.items else { return [] }
        let filtered: [HoldingsItem]
        if settings.onlyShowWatchlistInPortfolio, !settings.watchlist.isEmpty {
            let allowed = Set(settings.watchlist)
            filtered = items.filter { allowed.contains($0.symbol) }
        } else {
            filtered = items
        }
        return HoldingOrder.apply(filtered, order: settings.holdingOrder)
    }

    /// 목록에서 끌어 옮겼을 때 순서를 저장한다.
    ///
    /// `visibleSymbols` 를 함께 받는 이유는 세그먼트나 관심종목 필터가 걸려 있으면 사용자가
    /// **부분 집합**을 옮기기 때문이다. 그 부분의 새 순서만 전체 순서에 끼워 넣어야
    /// 화면에 없던 종목의 자리가 멋대로 바뀌지 않는다.
    func moveHoldings(visibleSymbols: [String], from source: IndexSet, to destination: Int) {
        let updated = HoldingOrder.applyingMove(
            to: settings.holdingOrder,
            visible: visibleSymbols,
            from: source,
            to: destination
        )
        // 전량 매도한 종목을 덜어낸다. 남겨두면 배열이 계속 길어지고, 다시 샀을 때
        // 사용자가 기억하지 못하는 예전 자리로 튀어 올라간다.
        let owned = holdings?.items.map(\.symbol) ?? []
        settings.holdingOrder = owned.isEmpty ? updated : HoldingOrder.pruned(updated, keeping: owned)
    }
}
