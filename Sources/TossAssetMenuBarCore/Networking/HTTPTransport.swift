import Foundation

/// HTTP 전송 계층. 검증 러너에서 가짜 응답을 넣기 위해 프로토콜로 분리한다.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        // 시세 응답이 캐시되면 안 된다.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TossAPIError.transport(description: "HTTP 응답이 아닙니다.")
        }
        return (data, http)
    }
}

/// 토스증권 응답에 맞춘 JSON 디코더.
///
/// `timestamp` 는 `2026-03-25T09:30:00.123+09:00` 처럼 소수점 초가 있을 때도 있고 없을 때도 있어
/// 두 포맷을 모두 시도한다.
public enum TossJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ISO 8601 날짜로 해석할 수 없습니다: \(raw)"
            )
        }
        return decoder
    }

    private static let fractional = SynchronizedISO8601Formatter(
        options: [.withInternetDateTime, .withFractionalSeconds]
    )
    private static let plain = SynchronizedISO8601Formatter(
        options: [.withInternetDateTime]
    )
}

/// `ISO8601DateFormatter` 는 `Sendable` 이 아니어서 static 으로 공유할 수 없다.
/// 파싱마다 새로 만드는 건 낭비이고(응답 하나에 타임스탬프가 최대 200개 온다),
/// `Date.ISO8601FormatStyle` 은 `+09:00` 같은 오프셋 표기를 그대로 받아주지 않는다.
/// 그래서 lock 으로 직접 보호한다 — `@unchecked Sendable` 의 근거가 이 lock 이다.
private final class SynchronizedISO8601Formatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter

    init(options: ISO8601DateFormatter.Options) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        self.formatter = formatter
    }

    func date(from string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: string)
    }
}
