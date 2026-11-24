import XCTest
@testable import Hightouch
@testable import HightouchPush

final class HightouchPushDeviceId_Tests: XCTestCase {

    // MARK: - Storage

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("device-id")
    }

    private func makeStore(at url: URL) throws -> DeviceIdStore {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return DeviceIdStore(fileURL: { url })
    }

    func testDeviceIdIsTheSameAfterARestart() throws {
        let url = temporaryFileURL()

        let first = try makeStore(at: url).getOrCreate()
        let afterRestart = try makeStore(at: url).getOrCreate()

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, afterRestart)
    }

    func testANewDeviceIdIsMintedOnceTheStoredOneIsGone() throws {
        let url = temporaryFileURL()
        let first = try makeStore(at: url).getOrCreate()

        try FileManager.default.removeItem(at: url)
        let afterUninstall = try makeStore(at: url).getOrCreate()

        XCTAssertFalse(afterUninstall.isEmpty)
        XCTAssertNotEqual(first, afterUninstall)
    }

    func testDeviceIdStaysStableForTheProcessWhenItCannotBeStored() {
        struct NoDirectory: Error {}
        let store = DeviceIdStore(fileURL: { throw NoDirectory() })

        XCTAssertEqual(store.getOrCreate(), store.getOrCreate())
    }

    func testDefaultFileIsInTheHightouchDirectory() throws {
        let url = try DeviceIdStore.defaultFileURL()

        XCTAssertEqual(Array(url.pathComponents.suffix(2)), ["Hightouch", "device-id"])
    }

    // MARK: - Events

    func testDeviceIdIsSentOnTokenEventsAndSurvivesLogoutAndUserSwitch() {
        let apnsKey = "com.hightouch.push.apnsToken"
        let lastUploadKey = "com.hightouch.push.lastTokenUploadAt"
        UserDefaults.standard.removeObject(forKey: apnsKey)
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-device-id"),
            config: HightouchPushConfig(appId: "device-id-app")
        )
        let output = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: output)
        waitUntilStarted(analytics: HightouchPush.analytics)
        defer {
            HightouchPush.analytics.storage.hardReset(doYouKnowHowToUseThis: true)
            UserDefaults.standard.removeObject(forKey: apnsKey)
            UserDefaults.standard.removeObject(forKey: lastUploadKey)
        }

        HightouchPush.register(token: Data([0x01, 0x02, 0x03, 0x04]))
        HightouchPush.identify(userId: "user-1")
        HightouchPush.logout()
        HightouchPush.identify(userId: "user-2")

        let deviceIds = output.events
            .compactMap { $0 as? TrackEvent }
            .filter { $0.event == "CEP Push Token Events" }
            .map { $0.properties?.dictionaryValue?["device_id"] as? String }
        XCTAssertGreaterThanOrEqual(deviceIds.count, 3)
        XCTAssertEqual(Set(deviceIds).count, 1)
        XCTAssertEqual(deviceIds.first, HightouchPush.deviceId)
    }
}
