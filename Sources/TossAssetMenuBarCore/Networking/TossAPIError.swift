import Foundation

/// 사용자에게 보여줄 수 있는 형태로 정규화한 API 오류.
///
/// `Sendable` 을 유지하기 위해 원본 `Error` 대신 설명 문자열만 담는다.
/// **client_secret 이 섞여 들어갈 수 있는 값은 절대 담지 않는다.**
public enum TossAPIError: Error, Sendable, Equatable {
    /// 아직 API 키를 입력하지 않았다.
    case notConfigured
    /// 계좌 계열 API 인데 계좌가 선택되지 않았다.
    case accountNotSelected
    /// client_id / client_secret 이 잘못되었다.
    case invalidCredentials(message: String)
    /// 토큰이 만료·무효. 재발급 후 재시도 대상.
    case tokenRejected(code: String)
    /// 403 edge-blocked. 허용 IP 목록에 현재 IP 가 없을 때 가장 흔하다.
    case ipNotAllowed
    case forbidden(message: String)
    case accountNotFound
    case symbolNotFound(symbol: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case maintenance
    /// 그 밖의 서버 오류.
    case server(status: Int, code: String, message: String, requestId: String?)
    /// 네트워크 계층 실패.
    case transport(description: String)
    /// 응답 해석 실패.
    case decoding(description: String)

    /// 토큰을 새로 받아 한 번 재시도해볼 가치가 있는가.
    public var isTokenRecoverable: Bool {
        if case .tokenRejected = self { return true }
        return false
    }
}

extension TossAPIError {
    /// 팝오버에 그대로 띄울 한 줄 설명.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            "API 키가 등록되지 않았습니다. 설정에서 입력해 주세요."
        case .accountNotSelected:
            "계좌가 선택되지 않았습니다. 설정에서 계좌를 골라 주세요."
        case .invalidCredentials:
            "API 키가 올바르지 않습니다. client_id 와 client_secret 을 다시 확인해 주세요."
        case .tokenRejected:
            "인증이 만료되었습니다. 다시 시도해 주세요."
        case .ipNotAllowed:
            "현재 IP 가 허용 목록에 없습니다. 토스증권 설정 > Open API > 허용 IP 관리에 등록해 주세요."
        case .forbidden(let message):
            message.isEmpty ? "요청 권한이 없습니다." : message
        case .accountNotFound:
            "선택된 계좌를 찾을 수 없습니다. 설정에서 계좌를 다시 선택해 주세요."
        case .symbolNotFound(let symbol):
            if let symbol { "종목을 찾을 수 없습니다: \(symbol)" } else { "종목을 찾을 수 없습니다." }
        case .rateLimited:
            "요청이 너무 많습니다. 잠시 후 자동으로 다시 시도합니다."
        case .maintenance:
            "토스증권 시스템 점검 중입니다."
        case .server(_, _, let message, _):
            message.isEmpty ? "일시적인 서버 오류입니다." : message
        case .transport:
            "네트워크에 연결할 수 없습니다."
        case .decoding:
            "응답을 해석할 수 없습니다. API 스펙이 변경되었을 수 있습니다."
        }
    }

    /// 사용자가 직접 조치해야 하는 오류인지. 자동 재시도로 풀리지 않는다.
    public var needsUserAction: Bool {
        switch self {
        case .notConfigured, .accountNotSelected, .invalidCredentials, .ipNotAllowed, .accountNotFound:
            true
        default:
            false
        }
    }

    /// HTTP 상태와 에러 envelope 을 도메인 오류로 정규화한다.
    public static func from(status: Int, body: ApiErrorBody?, retryAfter: TimeInterval?, symbol: String? = nil) -> TossAPIError {
        let code = body?.code ?? ""
        let message = body?.message ?? ""

        switch (status, code) {
        case (401, "invalid-token"), (401, "expired-token"), (401, "login-user-not-found"):
            return .tokenRejected(code: code)
        case (401, _):
            return .invalidCredentials(message: message)
        case (403, "edge-blocked"):
            return .ipNotAllowed
        case (403, _):
            return .forbidden(message: message)
        case (404, "account-not-found"):
            return .accountNotFound
        case (404, "stock-not-found"):
            return .symbolNotFound(symbol: symbol)
        case (429, _):
            return .rateLimited(retryAfter: retryAfter)
        case (500, "maintenance"):
            return .maintenance
        default:
            return .server(status: status, code: code, message: message, requestId: body?.requestId)
        }
    }
}
