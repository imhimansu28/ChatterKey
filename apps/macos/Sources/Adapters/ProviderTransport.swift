import ChatterKeyCore
import Foundation

nonisolated enum ProviderTransport {
    static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: RejectRedirectsDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            return try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .timedOut { throw ProviderError.timedOut }
            throw error
        }
    }
}

private final class RejectRedirectsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
