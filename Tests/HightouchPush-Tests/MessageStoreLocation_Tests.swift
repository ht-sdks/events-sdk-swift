import XCTest
@testable import HightouchPush

final class MessageStoreLocation_Tests: XCTestCase {

    // MARK: - Write key sanitization

    func testWriteKeysWithSlashAndPlusYieldOneDirectoryComponent() throws {
        let slashy = "abc/def+ghi"
        let safe = MessageStoreLocation.safeWriteKey(slashy)

        XCTAssertFalse(safe.contains("/"), "a percent-encoded write key must not reintroduce a path separator")

        let directory = try MessageStoreLocation.messagesDirectory(writeKey: slashy)
        let expectedParent = try MessageStoreLocation.messagesDirectory(writeKey: "placeholder").deletingLastPathComponent()

        XCTAssertEqual(
            directory.deletingLastPathComponent().standardizedFileURL,
            expectedParent.standardizedFileURL,
            "the sanitized write key must contribute exactly one path component, not several"
        )
        XCTAssertEqual(directory.lastPathComponent, safe)
    }

    // MARK: - Distinct keys, distinct directories

    func testDistinctWriteKeysYieldDistinctDirectories() throws {
        let first = try MessageStoreLocation.messagesDirectory(writeKey: "\(name)-key-one")
        let second = try MessageStoreLocation.messagesDirectory(writeKey: "\(name)-key-two")
        XCTAssertNotEqual(first, second)
    }

    func testSameWriteKeyYieldsTheSameDirectoryEveryTime() throws {
        let key = "\(name)-stable-key"
        let first = try MessageStoreLocation.messagesDirectory(writeKey: key)
        let second = try MessageStoreLocation.messagesDirectory(writeKey: key)

        XCTAssertEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertEqual(first.deletingLastPathComponent().path, second.deletingLastPathComponent().path)
    }

    // MARK: - Backup exclusion

    func testMessagesDirectoryIsExcludedFromBackup() throws {
        let directory = try MessageStoreLocation.messagesDirectory(writeKey: "\(name)-backup-check")
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
        let url1 = try MessageStoreLocation.storeURL(for: .appContainer, writeKey: "\(name)-v1", modelVersion: 1)
        let url2 = try MessageStoreLocation.storeURL(for: .appContainer, writeKey: "\(name)-v1", modelVersion: 2)

        XCTAssertEqual(url1?.lastPathComponent, "messages-v1.sqlite")
        XCTAssertEqual(url2?.lastPathComponent, "messages-v2.sqlite")
    }

    // MARK: - .ephemeral has no directory to create

    func testEphemeralLocationResolvesToNil() throws {
        let url = try MessageStoreLocation.storeURL(for: .ephemeral, writeKey: "\(name)-ephemeral", modelVersion: 1)
        XCTAssertNil(url)
    }

    // MARK: - .explicit creates its parent directory

    func testExplicitLocationCreatesItsParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("custom.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = try MessageStoreLocation.storeURL(for: .explicit(fileURL), writeKey: "unused", modelVersion: 1)

        XCTAssertEqual(resolved, fileURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
