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

        XCTAssertNotNil(first)
        XCTAssertEqual(first, afterRestart)
    }

    func testANewDeviceIdIsMintedOnceTheStoredOneIsGone() throws {
        let url = temporaryFileURL()
        let first = try makeStore(at: url).getOrCreate()

        try FileManager.default.removeItem(at: url)
        let afterUninstall = try makeStore(at: url).getOrCreate()

        XCTAssertNotNil(afterUninstall)
        XCTAssertNotEqual(first, afterUninstall)
    }

    func testNoDeviceIdIsMintedWhileTheStoredOneCannotBeRead() throws {
        let url = temporaryFileURL()
        let stored = try makeStore(at: url).getOrCreate()
        let readableCopy = url.appendingPathExtension("copy")
        try FileManager.default.moveItem(at: url, to: readableCopy)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let store = try makeStore(at: url)

        XCTAssertNil(store.getOrCreate())

        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: readableCopy, to: url)
        XCTAssertEqual(store.getOrCreate(), stored)
    }

    func testNoDeviceIdIsMintedWhenStorageReturnsPermissionError() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let stored = try makeStore(at: url).getOrCreate()

        final class Flag: @unchecked Sendable {
            var locked = true
        }
        let flag = Flag()
        let store = DeviceIdStore(fileURL: {
            if flag.locked {
                throw CocoaError(.fileReadNoPermission)
            }
            return url
        })

        XCTAssertNil(store.getOrCreate())

        flag.locked = false
        XCTAssertEqual(store.getOrCreate(), stored)
    }

    func testStoredDeviceIdTrimsSurroundingWhitespace() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let expected = UUID().uuidString
        try "  \(expected)\n".write(to: url, atomically: true, encoding: .utf8)

        let store = DeviceIdStore(fileURL: { url })
        XCTAssertEqual(store.getOrCreate(), expected)
    }

    #if !os(Linux)
    func testDeviceIdFileIsExcludedFromBackup() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try makeStore(at: url).getOrCreate()
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
    #endif

    func testDeviceIdStaysStableForTheProcessWhenItCannotBeStored() {
        struct NoDirectory: Error {}
        let store = DeviceIdStore(fileURL: { throw NoDirectory() })

        XCTAssertNotNil(store.getOrCreate())
        XCTAssertEqual(store.getOrCreate(), store.getOrCreate())
    }

    func testDefaultFileIsInTheHightouchDirectory() throws {
        let url = try DeviceIdStore.defaultFileURL()

        XCTAssertEqual(Array(url.pathComponents.suffix(2)), ["Hightouch", "device-id"])
    }

    // MARK: - Events

    func testDeviceIdIsSentOnTokenEventsAndSurvivesLogoutAndUserSwitch() throws {
        let apnsKey = "com.hightouch.push.apnsToken"
        let lastUploadKey = "com.hightouch.push.lastTokenUploadAt"
        let url = temporaryFileURL()
        UserDefaults.standard.removeObject(forKey: apnsKey)
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        HightouchPush.deviceIdStore = try makeStore(at: url)
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-device-id"),
            config: HightouchPushConfig(appId: "device-id-app")
        )
        let output = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: output)
        waitUntilStarted(analytics: HightouchPush.analytics)
        defer {
            HightouchPush.deviceIdStore = .shared
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            HightouchPush.analytics.storage.hardReset(doYouKnowHowToUseThis: true)
            UserDefaults.standard.removeObject(forKey: apnsKey)
            UserDefaults.standard.removeObject(forKey: lastUploadKey)
        }

        HightouchPush.register(token: Data([0x01, 0x02, 0x03, 0x04]))
        HightouchPush.identify(userId: "user-1")
        HightouchPush.logout()
        HightouchPush.identify(userId: "user-2")
        HightouchPush.identify(userId: "user-3")
        HightouchPush.register(token: Data([0x05, 0x06, 0x07, 0x08]))

        let expectedDeviceId = try XCTUnwrap(HightouchPush.deviceId)
        let deviceIds = output.events
            .compactMap { $0 as? TrackEvent }
            .filter { $0.event == "CEP Push Token Events" }
            .map { $0.properties?.dictionaryValue?["device_id"] as? String }
        XCTAssertEqual(deviceIds.count, 4)
        XCTAssertTrue(deviceIds.allSatisfy { $0 == expectedDeviceId })
    }

    func testDeviceIdIsIncludedInBasePropertiesForPushAndInAppChannels() throws {
        let url = temporaryFileURL()
        HightouchPush.deviceIdStore = try makeStore(at: url)
        defer {
            HightouchPush.deviceIdStore = .shared
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let expectedDeviceId = try XCTUnwrap(HightouchPush.deviceId)
        XCTAssertEqual(CepEventTracking.baseProperties(channel: .push)["device_id"] as? String, expectedDeviceId)
        XCTAssertEqual(CepEventTracking.baseProperties(channel: .inApp)["device_id"] as? String, expectedDeviceId)
    }

    func testBasePropertiesOmitsDeviceIdWhenStoredIdCannotBeRead() {
        HightouchPush.deviceIdStore = DeviceIdStore(fileURL: { throw CocoaError(.fileReadNoPermission) })
        defer { HightouchPush.deviceIdStore = .shared }

        let properties = CepEventTracking.baseProperties(channel: .push)
        XCTAssertFalse(properties.keys.contains("device_id"))
    }
}
