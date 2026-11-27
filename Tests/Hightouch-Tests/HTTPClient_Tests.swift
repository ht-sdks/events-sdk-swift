//
//  HTTPClientTests.swift
//  Hightouch-Tests
//
//  Created by Brandon Sneed on 1/21/21.
//

import XCTest
@testable import Hightouch

class HTTPClientTests: XCTestCase {

    #if !os(Linux) && !os(watchOS)
    func testFlushDiscardsPermanentFailuresAndRetainsRetryableBatches() throws {
        for status in [0, 200, 302, 400, 401, 403, 404, 408, 413, 422, 429, 500, 503] {
            let analytics = Analytics(configuration: Configuration(writeKey: UUID().uuidString)
                .autoAddSegmentDestination(false).flushPolicies([]))
            defer { analytics.storage.hardReset(doYouKnowHowToUseThis: true) }
            let destination = SegmentDestination()
            destination.analytics = analytics
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [BatchResponse.self]
            configuration.httpAdditionalHeaders = ["Test-Status": String(status)]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let finished = expectation(description: "Handled HTTP \(status)")
            let client = ObservedHTTPClient(analytics: analytics)
            client.session = session
            client.didHandleResponse = { finished.fulfill() }
            destination.httpClient = client
            analytics.storage.write(.events, value: IdentifyEvent(userId: "test"))
            let files: [URL] = try XCTUnwrap(analytics.storage.read(.events))
            let file = try XCTUnwrap(files.first)

            destination.flush()
            wait(for: [finished], timeout: 30)

            let retryable = [0, 302, 408, 429, 500, 503].contains(status)
            XCTAssertEqual(FileManager.default.fileExists(atPath: file.path), retryable, "HTTP \(status)")
        }
    }
    #endif

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /*func testExample() throws {
        
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }*/

}

#if !os(Linux) && !os(watchOS)
private class ObservedHTTPClient: HTTPClient {
    var didHandleResponse: (() -> Void)?

    override func startBatchUpload(writeKey: String, batch: URL, completion: @escaping (Result<Bool, Error>) -> Void) -> URLSessionDataTask? {
        return super.startBatchUpload(writeKey: writeKey, batch: batch) { result in
            completion(result)
            self.didHandleResponse?()
        }
    }
}

private class BatchResponse: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = Int(request.value(forHTTPHeaderField: "Test-Status")!)!
        if status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
