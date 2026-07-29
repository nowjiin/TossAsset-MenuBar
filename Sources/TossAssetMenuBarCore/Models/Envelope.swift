import Foundation

/// 성공 응답 envelope. `{"result": ...}` 형태이며 `error` 와 동시에 오지 않는다.
public struct ApiEnvelope<Result: Decodable & Sendable>: Decodable, Sendable {
    public let result: Result
}

/// 실패 응답 envelope. `{"error": {...}}` 형태로 4xx/5xx 에 사용된다.
public struct ApiErrorEnvelope: Decodable, Sendable {
    public let error: ApiErrorBody
}

public struct ApiErrorBody: Decodable, Sendable {
    public let requestId: String?
    public let code: String
    public let message: String

    public init(requestId: String?, code: String, message: String) {
        self.requestId = requestId
        self.code = code
        self.message = message
    }
}

/// OAuth2 토큰 응답만 공통 envelope 을 쓰지 않고 OAuth2 표준 형식을 따른다.
public struct OAuthTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

public struct OAuthErrorResponse: Decodable, Sendable {
    public let error: String
    public let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
