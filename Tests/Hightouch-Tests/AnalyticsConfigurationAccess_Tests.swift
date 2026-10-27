import XCTest
@testable import Hightouch

final class AnalyticsConfigurationAccess_Tests: XCTestCase {

    func testWriteKeyMatchesTheConfigurationItWasBuiltWith() {
        let analytics = Analytics(configuration: Configuration(writeKey: "\(name)-write-key"))
        XCTAssertEqual(analytics.writeKey, "\(name)-write-key")
    }

    func testWriteKeyIsUnaffectedByACustomApiHost() {
        let configuration = Configuration(writeKey: "\(name)")
            .apiHost("ap-south-1.hightouch-events.com/v1")
        let analytics = Analytics(configuration: configuration)
        XCTAssertEqual(analytics.writeKey, "\(name)")
    }

    #if DEBUG
    func testIsRunningUnitTestsIsTrueUnderXCTest() {
        XCTAssertTrue(Analytics.isRunningUnitTests)
    }
    #endif
}
