import Foundation
import Hightouch

#if os(Linux)
import FoundationNetworking
#endif

enum MessagesHTTPClientError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case statusCode(Int)
}

/// Client for the in-app gateway (`cep-inapp-gateway`). Separate from `Hightouch`'s `HTTPClient`,
/// which is internal to that module; exposing it would add to its library-evolution ABI.
final class MessagesHTTPClient {

    private weak var analytics: Analytics?
    private let host: String
    private let path: String
    private let writeKey: String
    private let session: URLSession

    private let requestFactory: ((URLRequest) -> URLRequest)?

    private static let unknownSDKVersion = "unknown"

    /// Production routes `/v1/inapp/*` on this host to the gateway. Not the events `apiHost`, and
    /// not regional.
    static let defaultHost = "api.hightouch.com"

    /// `protocolClasses` is a test seam for stubbing this session's traffic.
    init(
        analytics: Analytics,
        config: HightouchMessagesConfig,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.analytics = analytics
        self.host = config.messagesHost ?? MessagesHTTPClient.defaultHost
        self.path = config.messagesPath
        self.writeKey = analytics.writeKey
        self.requestFactory = config.requestFactory
        self.session = MessagesHTTPClient.configuredSession(protocolClasses: protocolClasses)
    }

    /// `deviceToken` is lowercase hex. `completion` runs on a background thread.
    func fetchMessages(
        owner: MessageOwner,
        deviceToken: String,
        completion: @escaping (Result<MessagesFetchResponse, Error>) -> Void
    ) {
        guard let url = url() else {
            completion(.failure(MessagesHTTPClientError.invalidURL))
            return
        }

        let request = configuredRequest(for: url, owner: owner, deviceToken: deviceToken)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(MessagesHTTPClientError.invalidResponse))
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                completion(.failure(MessagesHTTPClientError.statusCode(httpResponse.statusCode)))
                return
            }
            guard let data = data else {
                completion(.failure(MessagesHTTPClientError.invalidResponse))
                return
            }
            do {
                completion(.success(try MessagesFetchResponse.parse(data)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    private func url() -> URL? {
        let scheme = host.hasPrefix("localhost") ? "http" : "https"
        return URL(string: "\(scheme)://\(host)\(path)")
    }

    /// Gateway contract: Basic auth selects the workspace; the device token must be registered to
    /// the user id or the inbox comes back empty (anonymous ids always do). Identity stays out of
    /// the URL so it never reaches access logs.
    private func configuredRequest(for url: URL, owner: MessageOwner, deviceToken: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.addValue("analytics-ios/\(analytics?.version() ?? MessagesHTTPClient.unknownSDKVersion)", forHTTPHeaderField: "User-Agent")
        request.addValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let credentials = Data("\(writeKey):".utf8).base64EncodedString()
        request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.addValue(owner.id, forHTTPHeaderField: "x-hightouch-user-id")
        request.addValue(deviceToken, forHTTPHeaderField: "x-hightouch-device-token")

        if let requestFactory = requestFactory {
            request = requestFactory(request)
        }
        return request
    }

    private static func configuredSession(protocolClasses: [AnyClass]?) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 2
        if let protocolClasses = protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }
}
