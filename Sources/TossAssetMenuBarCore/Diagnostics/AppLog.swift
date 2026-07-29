import Foundation
import os

/// 진단용 로그.
///
/// `Console.app` 이나 `log stream --predicate 'subsystem == "TossAsset-MenuBar"'` 로 볼 수 있다.
///
/// **client_id / client_secret / access token 은 절대 넣지 않는다.**
/// os_log 는 디스크에 남고 다른 프로세스가 읽을 수 있다.
public enum AppLog {
    public static let subsystem = "TossAsset-MenuBar"

    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let keychain = Logger(subsystem: subsystem, category: "keychain")
    public static let network = Logger(subsystem: subsystem, category: "network")
}
