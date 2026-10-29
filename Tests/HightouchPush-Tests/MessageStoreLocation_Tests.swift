import XCTest
@testable import HightouchPush

final class MessageStoreLocation_Tests: XCTestCase {

    // MARK: - One directory per app

    func testMessagesDirectoryIsTheSameEveryTimeAndScopedToTheApp() throws {
        let first = try MessageStoreLocation.messagesDirectory()
        let second = try MessageStoreLocation.messagesDirectory()
        XCTAssertEqual(first.standardizedFileURL, second.standardizedFileURL)

        let components = Array(first.standardizedFileURL.pathComponents.suffix(3))
        XCTAssertEqual(Array(components.suffix(2)), ["Hightouch", "Messages"])
        #if os(macOS) || targetEnvironment(macCatalyst)
        XCTAssertEqual(
            components.first, Bundle.main.bundleIdentifier ?? "com.hightouch.sdk",
            "an unsandboxed Mac app shares Application Support, so the bundle id must scope the store"
        )
        #endif
    }

    // MARK: - Backup exclusion

    func testMessagesDirectoryIsExcludedFromBackup() throws {
        let directory = try MessageStoreLocation.messagesDirectory()
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - Model version in the filename

    func testBumpingModelVersionChangesTheFilename() {
        XCTAssertNotEqual(
            MessageStoreLocation.fileName(modelVersion: 1),
            MessageStoreLocation.fileName(modelVersion: 2)
        )
        XCTAssertEqual(MessageStoreLocation.fileName(modelVersion: 1), "messages-v1.sqlite")
        XCTAssertEqual(MessageStoreLocation.fileName(modelVersion: 2), "messages-v2.sqlite")
    }

    func testAppContainerStoreURLEndsWithVersionedFilename() throws {
        let url1 = try MessageStoreLocation.storeURL(for: .appContainer, modelVersion: 1)
        let url2 = try MessageStoreLocation.storeURL(for: .appContainer, modelVersion: 2)

        XCTAssertEqual(url1?.lastPathComponent, "messages-v1.sqlite")
        XCTAssertEqual(url2?.lastPathComponent, "messages-v2.sqlite")
    }

    // MARK: - .ephemeral has no directory to create

    func testEphemeralLocationResolvesToNil() throws {
        let url = try MessageStoreLocation.storeURL(for: .ephemeral, modelVersion: 1)
        XCTAssertNil(url)
    }

    // MARK: - .explicit creates its parent directory

    func testExplicitLocationCreatesItsParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("custom.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = try MessageStoreLocation.storeURL(for: .explicit(fileURL), modelVersion: 1)

        XCTAssertEqual(resolved, fileURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
