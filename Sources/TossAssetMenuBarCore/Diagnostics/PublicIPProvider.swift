import Foundation

/// 현재 공용 IP 를 알려준다.
///
/// 토스증권 Open API 는 WTS 에 등록한 허용 IP 에서만 호출할 수 있고, 등록은 사용자가 직접 해야 한다.
/// 그래서 "지금 등록해야 할 IP" 를 앱이 보여주는 게 사실상 필수 안내 기능이다.
///
/// 조회에는 토스와 무관한 외부 서비스를 쓴다. 계좌 정보는 절대 나가지 않고, 응답으로 IP 문자열만 받는다.
public struct PublicIPProvider: Sendable {
    /// 응답이 순수 텍스트 IP 하나만 돌려주는 엔드포인트를 쓴다. 첫 번째가 실패하면 다음을 시도한다.
    private static let endpoints = [
        URL(string: "https://checkip.amazonaws.com")!,
        URL(string: "https://api.ipify.org")!,
    ]

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: configuration)
    }

    public func currentIPv4() async -> String? {
        for url in Self.endpoints {
            if let ip = await fetch(url), isIPv4(ip) {
                return ip
            }
        }
        return nil
    }

    private func fetch(_ url: URL) async -> String? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 외부 응답을 그대로 화면에 띄우기 전에 형식을 확인한다.
    public func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let octet = Int(part), octet <= 255
            else { return false }
            return true
        }
    }
}
