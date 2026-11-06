import Foundation

/// Thin seam over URLSession so network code can be tested with canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MailProviderError.network("Unexpected response from server.")
            }
            return (data, http)
        } catch let error as MailProviderError {
            throw error
        } catch {
            throw MailProviderError.network(error.localizedDescription)
        }
    }
}
