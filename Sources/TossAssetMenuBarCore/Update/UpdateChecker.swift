import Foundation

/// GitHub Release 에서 확인한 최신 버전.
public struct ReleaseInfo: Sendable, Hashable {
    public let version: AppVersion
    public let tag: String
    public let pageURL: URL

    public init(version: AppVersion, tag: String, pageURL: URL) {
        self.version = version
        self.tag = tag
        self.pageURL = pageURL
    }
}

public enum UpdateStatus: Sendable, Hashable {
    case upToDate(current: AppVersion)
    case available(ReleaseInfo)
    /// 확인 실패. 네트워크 문제이거나 릴리스가 아직 없다.
    case failed(message: String)
}

/// GitHub Release 를 조회해 새 버전이 있는지 확인한다.
///
/// **설치는 하지 않는다.** 이 앱은 App Sandbox 를 쓰기 때문에 `/Applications` 에 쓸 수 없고,
/// `Process` 로 띄운 자식도 같은 샌드박스를 물려받아 설치 스크립트를 실행할 수 없다.
/// 실행 중인 번들을 스스로 덮어쓰는 것도 위험하다.
/// 그래서 확인만 하고, 설치는 사용자가 릴리스 페이지나 설치 명령으로 처리한다.
public struct UpdateChecker: Sendable {
    private let repository: String
    private let transport: any HTTPTransport

    public init(repository: String, transport: any HTTPTransport = URLSessionTransport(timeout: 10)) {
        self.repository = repository
        self.transport = transport
    }

    /// `Scripts/install.sh` 가 붙여넣기용으로 안내하는 것과 같은 명령.
    public var installCommand: String {
        "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/Scripts/install.sh | bash"
    }

    public var releasesPageURL: URL {
        URL(string: "https://github.com/\(repository)/releases/latest")!
    }

    /// 한도 초과인지 판별하고, `X-RateLimit-Reset` 으로 대기 시간을 계산한다.
    /// 한도 문제가 아니면 nil — 403 에는 다른 이유도 있다.
    public static func rateLimitMessage(_ response: HTTPURLResponse, now: Date = Date()) -> String? {
        guard response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" else {
            return nil
        }
        guard let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap(Double.init) else {
            return "GitHub 조회 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."
        }
        let wait = Date(timeIntervalSince1970: reset).timeIntervalSince(now)
        guard wait > 0 else {
            return "GitHub 조회 한도를 초과했습니다. 다시 시도해 주세요."
        }
        let minutes = max(1, Int((wait / 60).rounded(.up)))
        return "GitHub 조회 한도를 초과했습니다. 약 \(minutes)분 후 다시 시도해 주세요."
    }

    public func check(current: AppVersion) async -> UpdateStatus {
        // /releases/latest 는 draft 와 pre-release 를 제외한 최신 릴리스를 준다.
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .failed(message: "저장소 주소가 올바르지 않습니다.")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub API 는 User-Agent 가 없으면 403 을 준다.
        request.setValue("TossAsset-MenuBar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            AppLog.network.error("업데이트 확인 실패: 네트워크")
            return .failed(message: "네트워크에 연결할 수 없습니다.")
        }

        switch response.statusCode {
        case 200:
            break
        case 404:
            // 공개된 릴리스가 없으면 받을 새 버전도 없으므로 최신으로 본다.
            //
            // 주의: 404 는 저장소 이름이 틀렸거나 비공개일 때도 온다. 그 경우 사용자에게는
            // 계속 "최신" 으로 보이므로, 원인을 추적할 수 있게 로그는 남긴다.
            AppLog.network.info("릴리스 조회 404 — 릴리스가 없거나 저장소가 비공개/오타일 수 있습니다")
            return .upToDate(current: current)
        case 403, 429:
            // 인증 없는 GitHub API 는 IP 당 시간당 60회로 제한된다. 공용 회선이나 다른 도구와
            // IP 를 공유하면 사용자가 아무것도 안 했는데도 걸릴 수 있어서, 언제 풀리는지 알려준다.
            return .failed(message: Self.rateLimitMessage(response) ?? "GitHub 가 요청을 거부했습니다.")
        default:
            return .failed(message: "GitHub 응답을 받지 못했습니다 (\(response.statusCode)).")
        }

        struct Payload: Decodable {
            let tagName: String
            let htmlURL: String

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failed(message: "릴리스 정보를 해석할 수 없습니다.")
        }
        guard let latest = AppVersion(payload.tagName) else {
            return .failed(message: "릴리스 태그를 해석할 수 없습니다: \(payload.tagName)")
        }

        guard latest > current else {
            return .upToDate(current: current)
        }
        // html_url 이 이상해도 릴리스 목록으로는 갈 수 있게 한다.
        let page = URL(string: payload.htmlURL) ?? releasesPageURL
        return .available(ReleaseInfo(version: latest, tag: payload.tagName, pageURL: page))
    }
}
