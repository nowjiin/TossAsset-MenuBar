import Foundation
import Security

/// `client_id` / `client_secret` 보관소.
///
/// 배포용 앱이므로 키는 사용자가 직접 입력하고, **Keychain 에만** 저장한다.
/// UserDefaults·로그·에러 메시지에는 절대 남기지 않는다.
///
/// 두 값을 **한 항목에 묶어** 저장한다. 항목을 나누면 Keychain 접근 프롬프트가 항목 수만큼 뜬다.
/// ad-hoc 서명은 빌드마다 코드 서명 해시가 달라 프롬프트가 매번 나오는데, 항목이 2개면 그게 2배가 된다.
public struct KeychainStore: Sendable {
    /// Keychain 접근 프롬프트에 그대로 표시되는 문자열이다.
    ///
    /// Bundle Identifier 와 같을 필요가 전혀 없다. 역순 도메인을 그대로 쓰면 프롬프트에
    /// `dev.tossassetmenubar.app.credentials` 같은 문자열이 떠서 무슨 앱인지 알기 어렵다.
    /// 그래서 사람이 읽는 이름을 쓴다.
    public static let defaultService = "TossAsset-MenuBar"

    /// 두 값을 합쳐 담는 항목의 account.
    private static let combinedAccount = "credentials"

    /// 예전에 쓰던 service 들. 최근 것부터 나열한다.
    ///
    /// `client_secret` 은 발급 후 다시 볼 수 없어서, 그냥 버리면 사용자가 키를 재발급해야 한다.
    /// 그래서 예전 항목이 남아 있으면 새 이름으로 한 번 옮겨온다.
    /// 모두 이전한 뒤에는 이 목록을 지워도 된다.
    ///
    /// 주의: 여기 문자열은 **과거 값이라 절대 일괄 치환의 대상이 되면 안 된다.**
    /// 새 이름으로 바꾸면 이전 경로가 끊겨 사용자가 키를 재발급해야 한다.
    private static let legacyServices = [
        "Toss-Asset-MenuBar",
        "TossAssetMenuBar",
        "com.miridih.tossstockbar.credentials",
    ]

    /// 예전 저장 형식: 두 항목으로 나뉘어 있었다.
    private static let legacyClientIDAccount = "client_id"
    private static let legacyClientSecretAccount = "client_secret"

    private let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    public func load() -> TossCredentials? {
        if let credentials = readCombined(from: service) {
            return credentials
        }
        // 예전 이름에 남은 키를 찾는다. 합친 형식이 먼저, 없으면 나뉘어 있던 형식.
        for legacy in Self.legacyServices {
            guard let credentials = readCombined(from: legacy) ?? readSplit(from: legacy) else {
                continue
            }
            AppLog.keychain.info("예전 이름의 키를 찾아 현재 이름으로 옮깁니다")
            save(credentials)
            // 옮긴 뒤에도 예전 항목은 남겨둔다. 되돌릴 수 없는 삭제는 사용자가 판단할 일이다.
            return credentials
        }
        AppLog.keychain.info("저장된 키가 없습니다")
        return nil
    }

    @discardableResult
    public func save(_ credentials: TossCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(StoredCredentials(credentials)) else {
            return false
        }
        return write(account: Self.combinedAccount, data: data)
    }

    /// 저장된 키를 지운다.
    ///
    /// 예전 이름·형식 항목까지 함께 지운다. 현재 항목만 지우면 다음 실행에서 `load()` 가 예전
    /// 항목을 다시 찾아와 키가 되살아나고, 사용자에게는 삭제가 실패한 것처럼 보인다.
    /// 사용자가 명시적으로 요청한 삭제이므로 남겨둘 이유가 없다.
    public func clear() {
        delete(service: service, account: Self.combinedAccount)
        for legacy in Self.legacyServices {
            delete(service: legacy, account: Self.combinedAccount)
            delete(service: legacy, account: Self.legacyClientIDAccount)
            delete(service: legacy, account: Self.legacyClientSecretAccount)
        }
        AppLog.keychain.info("저장된 키를 삭제했습니다")
    }

    // MARK: - 저장 형식

    /// 두 값을 한 항목에 담기 위한 표현.
    private struct StoredCredentials: Codable {
        let clientID: String
        let clientSecret: String

        init(_ credentials: TossCredentials) {
            self.clientID = credentials.clientID
            self.clientSecret = credentials.clientSecret
        }

        var credentials: TossCredentials {
            TossCredentials(clientID: clientID, clientSecret: clientSecret)
        }
    }

    // MARK: - 읽기

    private func readCombined(from service: String) -> TossCredentials? {
        guard let data = read(service: service, account: Self.combinedAccount),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else { return nil }
        let credentials = stored.credentials
        return credentials.isComplete ? credentials : nil
    }

    /// 예전 형식은 항목이 둘로 나뉘어 있어 프롬프트도 두 번 뜬다.
    private func readSplit(from service: String) -> TossCredentials? {
        guard let idData = read(service: service, account: Self.legacyClientIDAccount),
              let secretData = read(service: service, account: Self.legacyClientSecretAccount),
              let clientID = String(data: idData, encoding: .utf8),
              let clientSecret = String(data: secretData, encoding: .utf8)
        else { return nil }
        let credentials = TossCredentials(clientID: clientID, clientSecret: clientSecret)
        return credentials.isComplete ? credentials : nil
    }

    // MARK: - Security framework

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            // 항목이 없는 건 정상 상황이다. 그 외 실패만 기록한다.
            if status != errSecItemNotFound {
                AppLog.keychain.error("Keychain 읽기 실패 (status \(status))")
            }
            return nil
        }
        return item as? Data
    }

    private func write(account: String, data: Data) -> Bool {
        let query = baseQuery(service: service, account: account)

        // 이미 있으면 갱신, 없으면 추가.
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        var insert = query
        insert[kSecValueData as String] = data
        // 잠긴 상태에서 백그라운드 갱신을 시도할 이유가 없으므로 잠금 해제 상태로 한정한다.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLog.keychain.error("Keychain 저장 실패 (status \(addStatus))")
        }
        return addStatus == errSecSuccess
    }

    private func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}
