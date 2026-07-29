import Foundation

public struct TossCredentials: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public var isComplete: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// 액세스 토큰 발급·캐시를 담당한다.
///
/// 문서상 **client 당 유효한 access token 은 1 개**이며, 재발급하면 이전 토큰이 즉시 무효화된다.
/// 따라서 동시에 여러 요청이 몰려도 발급은 한 번만 일어나야 한다.
/// 진행 중인 발급 `Task` 를 공유해 이를 보장한다.
public actor TokenStore {
    /// 만료 직전 토큰을 쓰다가 401 을 맞는 걸 피하려고 이만큼 미리 갱신한다.
    static let refreshMargin: TimeInterval = 60

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let gate: RateLimitGate

    private var credentials: TossCredentials?
    private var cachedToken: String?
    private var expiresAt: Date?
    private var inFlight: Task<OAuthTokenResponse, any Error>?

    /// 발급 횟수. 동시 요청이 중복 발급하지 않는지 검증할 때 쓴다.
    private(set) var issueCount = 0

    public init(baseURL: URL, transport: any HTTPTransport, gate: RateLimitGate) {
        self.baseURL = baseURL
        self.transport = transport
        self.gate = gate
    }

    public func setCredentials(_ newValue: TossCredentials?) {
        guard newValue != credentials else { return }
        credentials = newValue
        invalidate()
    }

    public var hasCredentials: Bool { credentials?.isComplete == true }

    /// 캐시된 토큰을 버린다. 401 을 받았을 때 호출한다.
    public func invalidate() {
        cachedToken = nil
        expiresAt = nil
        inFlight = nil
    }

    public func currentIssueCount() -> Int { issueCount }

    public func token() async throws -> String {
        if let cachedToken, let expiresAt, expiresAt.timeIntervalSinceNow > Self.refreshMargin {
            return cachedToken
        }
        // 이미 누군가 발급 중이면 그 결과를 함께 기다린다.
        if let inFlight {
            return try await inFlight.value.accessToken
        }
        guard let credentials, credentials.isComplete else {
            throw TossAPIError.notConfigured
        }

        let task = Task { [baseURL, transport, gate] () async throws -> OAuthTokenResponse in
            await gate.waitForSlot(.auth)
            return try await Self.issue(credentials: credentials, baseURL: baseURL, transport: transport)
        }
        inFlight = task
        issueCount += 1

        do {
            let issued = try await task.value
            cachedToken = issued.accessToken
            expiresAt = Date().addingTimeInterval(TimeInterval(issued.expiresIn))
            inFlight = nil
            return issued.accessToken
        } catch {
            inFlight = nil
            cachedToken = nil
            expiresAt = nil
            throw error
        }
    }

    private static func issue(
        credentials: TossCredentials,
        baseURL: URL,
        transport: any HTTPTransport
    ) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: baseURL.appending(path: "oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // client_secret 이 URL 이나 로그에 남지 않도록 반드시 본문으로만 보낸다.
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as TossAPIError {
            throw error
        } catch {
            throw TossAPIError.transport(description: (error as NSError).localizedDescription)
        }

        guard response.statusCode == 200 else {
            throw tokenError(status: response.statusCode, data: data)
        }
        do {
            return try TossJSON.decoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw TossAPIError.decoding(description: "토큰 응답을 해석할 수 없습니다.")
        }
    }

    /// 토큰 엔드포인트만 공통 envelope 이 아닌 OAuth2 표준 오류 형식을 쓴다.
    static func tokenError(status: Int, data: Data) -> TossAPIError {
        if status == 403 { return .ipNotAllowed }
        if let oauth = try? TossJSON.decoder().decode(OAuthErrorResponse.self, from: data) {
            if oauth.error == "invalid_client" || oauth.error == "invalid_request" {
                return .invalidCredentials(message: oauth.errorDescription ?? "")
            }
            return .server(
                status: status,
                code: oauth.error,
                message: oauth.errorDescription ?? "",
                requestId: nil
            )
        }
        if let envelope = try? TossJSON.decoder().decode(ApiErrorEnvelope.self, from: data) {
            return .from(status: status, body: envelope.error, retryAfter: nil)
        }
        return .server(status: status, code: "", message: "", requestId: nil)
    }
}
