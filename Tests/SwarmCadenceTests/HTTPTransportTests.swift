import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SwarmCadenceCore

final class HTTPTransportTests: XCTestCase {
    func testReturnsHTTPStatusHeadersAndBody() throws {
        let response = try perform("success")
        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.data, Data("fixture response".utf8))
        XCTAssertEqual(response.headers.first { $0.key.lowercased() == "x-fixture" }?.value, "offline")
    }

    func testRejectsNonHTTPResponse() {
        XCTAssertThrowsError(try perform("non-http")) { error in
            XCTAssertEqual(error.localizedDescription, "missing HTTP response")
        }
    }

    func testPreservesTransportFailure() {
        XCTAssertThrowsError(try perform("failure")) { error in
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    private func perform(_ scenario: String) throws -> ProbeHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionProbeHTTPTransport(session: session)
        return try transport.perform(URLRequest(url: URL(string: "https://fixture.invalid/\(scenario)")!))
    }
}

/// Scenarios are request-local: no shared mutable handlers or network access.
private final class OfflineHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        if url.lastPathComponent == "failure" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let response: URLResponse
        if url.lastPathComponent == "non-http" {
            response = URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
        } else {
            response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: ["X-Fixture": "offline"])!
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("fixture response".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

#if canImport(Darwin)
// Darwin requires restating the superclass's conformance; FoundationNetworking
// explicitly marks URLProtocol's Sendable conformance unavailable.
extension OfflineHTTPProtocol: @unchecked Sendable {}
#endif
