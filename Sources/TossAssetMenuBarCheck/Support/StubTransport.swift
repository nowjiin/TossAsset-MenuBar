import Foundation
import TossAssetMenuBarCore

/// 미리 정해둔 응답을 돌려주는 전송 계층. 실제 네트워크를 타지 않는다.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Stub: Sendable {
        let status: Int
        let body: String
        let headers: [String: String]

        init(status: Int = 200, body: String, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    /// 경로별 응답. 같은 경로를 여러 번 부르면 앞에서부터 하나씩 소비하고,
    /// 다 소비하면 마지막 응답을 계속 반환한다.
    private let lock = NSLock()
    private var stubs: [String: [Stub]]
    /// `method` 를 기록하는 이유는 **조회 전용이라는 약속을 검증으로 고정**하기 위해서다.
    /// 이 앱은 주문을 생성·정정·취소하지 않으므로, 클라이언트가 보내는 요청은 전부 GET 이어야 한다.
    private(set) var requestLog:
        [(path: String, method: String, headers: [String: String], query: [String: String])] = []

    init(stubs: [String: [Stub]]) {
        self.stubs = stubs
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw TossAPIError.transport(description: "URL 이 없습니다")
        }
        let path = url.path

        // async 함수 안에서는 lock()/unlock() 을 직접 부를 수 없다 (Swift 6).
        // withLock 은 스코프가 닫혀 있어 await 를 끼워 넣을 수 없으므로 허용된다.
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        let stub: Stub? = lock.withLock {
            requestLog.append((
                path: path,
                method: request.httpMethod ?? "",
                headers: request.allHTTPHeaderFields ?? [:],
                query: query
            ))
            var queue = stubs[path] ?? []
            guard queue.count > 1 else { return queue.first }
            let next = queue.removeFirst()
            stubs[path] = queue
            return next
        }

        guard let stub else {
            throw TossAPIError.transport(description: "스텁이 없는 경로: \(path)")
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        return (Data(stub.body.utf8), response)
    }

    func requestCount(path: String) -> Int {
        lock.withLock { requestLog.filter { $0.path == path }.count }
    }

    func header(_ name: String, forPath path: String) -> String? {
        lock.withLock { requestLog.last { $0.path == path }?.headers[name] }
    }

    func query(forPath path: String) -> [String: String] {
        lock.withLock { requestLog.last { $0.path == path }?.query ?? [:] }
    }

    /// 기록된 요청에서 GET 이 아닌 것들. 비어 있어야 정상이다.
    func nonGetRequests() -> [(path: String, method: String)] {
        lock.withLock {
            requestLog.filter { $0.method != "GET" }.map { ($0.path, $0.method) }
        }
    }
}

/// 오류 종류만 비교하기 위한 매처. 연관값까지 일일이 맞추지 않아도 되게 한다.
enum TossAPIErrorMatcher: Sendable {
    case notConfigured
    case accountNotSelected
    case invalidCredentials
    case ipNotAllowed
    case accountNotFound
    case rateLimited
    case decoding
    case server

    func matches(_ error: any Error) -> Bool {
        guard let error = error as? TossAPIError else { return false }
        switch (self, error) {
        case (.notConfigured, .notConfigured),
             (.accountNotSelected, .accountNotSelected),
             (.invalidCredentials, .invalidCredentials),
             (.ipNotAllowed, .ipNotAllowed),
             (.accountNotFound, .accountNotFound),
             (.rateLimited, .rateLimited),
             (.decoding, .decoding),
             (.server, .server):
            return true
        default:
            return false
        }
    }
}
