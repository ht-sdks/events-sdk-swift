//
//  StorageTests.swift
//  Hightouch-Tests
//
//  Created by Brandon Sneed on 1/7/21.
//

import XCTest
import Sovran
@testable import Hightouch

class StorageTests: XCTestCase {

    func testEncodingFailureDoesNotCorruptBatch() throws {
        let storage = Storage(store: Store(), writeKey: UUID().uuidString)
        defer { storage.hardReset(doYouKnowHowToUseThis: true) }
        storage.write(.events, value: UnencodableEvent())
        let emptyFiles: [URL] = try XCTUnwrap(storage.read(.events))
        XCTAssertTrue(emptyFiles.isEmpty)
        storage.write(.events, value: IdentifyEvent(userId: "before"))
        storage.write(.events, value: UnencodableEvent())
        storage.write(.events, value: IdentifyEvent(userId: "after"))
        let files: [URL] = try XCTUnwrap(storage.read(.events))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(files.first))) as? [String: Any])
        let batch = try XCTUnwrap(json["batch"] as? [[String: Any]])
        XCTAssertEqual(batch.compactMap { $0["userId"] as? String }, ["before", "after"])
    }

    func testReopensUnfinishedBatch() throws {
        for contents in ["{ \"batch\": [", "{ \"batch\": [{\"userId\":\"previous\"}"] {
            let storage = Storage(store: Store(), writeKey: UUID().uuidString)
            defer { storage.hardReset(doYouKnowHowToUseThis: true) }
            storage.write(.events, value: IdentifyEvent(userId: "seed"))
            let seedFiles: [URL] = try XCTUnwrap(storage.read(.events))
            let directory = try XCTUnwrap(seedFiles.first).deletingLastPathComponent()
            storage.hardReset(doYouKnowHowToUseThis: true)
            let file = directory.appendingPathComponent("0-hightouch-events")
            try Data(contents.utf8).write(to: file)

            storage.write(.events, value: IdentifyEvent(userId: "next"))
            let files: [URL] = try XCTUnwrap(storage.read(.events))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(files.first))) as? [String: Any])
            let batch = try XCTUnwrap(json["batch"] as? [[String: Any]])
            XCTAssertEqual(batch.compactMap { $0["userId"] as? String }, contents.hasSuffix("[") ? ["next"] : ["previous", "next"])
        }
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testSettingsWrite() throws {
        let dummySettings = """
        {
            "integrations": {
              "Segment.io": {
                "apiKey": "1234",
                "unbundledIntegrations": [],
                "addBundledMetadata": true
              }
            },
            "middlewareSettings": {
              "routingRules": [
                {
                  "transformers": [
                    [
                      {
                        "type": "allow_properties",
                        "config": {
                          "allow": {
                            "traits": null,
                            "context": null,
                            "_metadata": null,
                            "integrations": null,
                          }
                        }
                      }
                    ]
                  ]
                }
              ]
            },
          }
        """
        let jsonData = dummySettings.data(using: .utf8)!
        let jsonSettings = try! JSONSerialization.jsonObject(with: jsonData)
        
        let analytics = Analytics(configuration: Configuration(writeKey: "test"))
        analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        
        // this will crash if it fails.
        let j = try! JSON(jsonSettings)
        analytics.storage.write(.settings, value: j)
        
        RunLoop.main.run(until: Date.distantPast)
        
        let result: JSON? = analytics.storage.read(.settings)

        XCTAssertNotNil(result)
    }

    func testBasicWriting() throws {
        let analytics = Analytics(configuration: Configuration(writeKey: "test"))
        
        analytics.identify(userId: "brandon", traits: MyTraits(email: "blah@blah.com"))
        
        let userInfo: UserInfo? = analytics.store.currentState()
        XCTAssertNotNil(userInfo)
        XCTAssertTrue(userInfo!.userId == "brandon")
        
        // This is a hack that needs to be dealt with
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        
        if let userId = analytics.storage.userDefaults?.string(forKey: Storage.Constants.userId.rawValue) {
            XCTAssertTrue(userId == "brandon")
        } else {
            XCTFail("Could not read from storage the userId")
        }
    }
    
    func testEventWriting() throws {
        let analytics = Analytics(configuration: Configuration(writeKey: "test"))
        analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        
        var event = IdentifyEvent(userId: "brandon1", traits: try! JSON(with: MyTraits(email: "blah@blah.com")))
        analytics.storage.write(.events, value: event)
        
        event = IdentifyEvent(userId: "brandon2", traits: try! JSON(with: MyTraits(email: "blah@blah.com")))
        analytics.storage.write(.events, value: event)
        
        event = IdentifyEvent(userId: "brandon3", traits: try! JSON(with: MyTraits(email: "blah@blah.com")))
        analytics.storage.write(.events, value: event)
        
        let results: [URL]? = analytics.storage.read(.events)

        XCTAssertNotNil(results)
        
        let fileURL = results![0]
        
        XCTAssertTrue(fileURL.isFileURL)
        XCTAssertTrue(fileURL.lastPathComponent == "0-hightouch-events.temp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: fileURL), options: []) as! [String: Any]
        
        let batch = json["batch"] as! [[String: Any]]
        let item1 = batch[0]["userId"] as! String
        let item2 = batch[1]["userId"] as! String
        let item3 = batch[2]["userId"] as! String

        XCTAssertTrue(item1 == "brandon1")
        XCTAssertTrue(item2 == "brandon2")
        XCTAssertTrue(item3 == "brandon3")

        analytics.storage.remove(file: fileURL)

        // make sure our original and temp files are named correctly, and gone.
        let originalFile = fileURL.deletingPathExtension()
        let tempFile = fileURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
    }
    
    func testFilePrepAndFinish() {
        let analytics = Analytics(configuration: Configuration(writeKey: "test"))
        analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        
        var event = IdentifyEvent(userId: "brandon1", traits: try! JSON(with: MyTraits(email: "blah@blah.com")))
        analytics.storage.write(.events, value: event)
        
        var results: [URL]? = analytics.storage.read(.events)

        XCTAssertNotNil(results)
        
        var fileURL = results![0]
        
        XCTAssertTrue(fileURL.isFileURL)
        XCTAssertTrue(fileURL.lastPathComponent == "0-hightouch-events.temp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        event = IdentifyEvent(userId: "brandon2", traits: try! JSON(with: MyTraits(email: "blah@blah.com")))
        analytics.storage.write(.events, value: event)
        
        results = analytics.storage.read(.events)
        
        XCTAssertNotNil(results)
        
        fileURL = results![0]
        
        XCTAssertTrue(fileURL.isFileURL)
        XCTAssertTrue(fileURL.lastPathComponent == "1-hightouch-events.temp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
}

private struct UnencodableEvent: RawEvent {
    @Noncodable var enrichments: [EnrichmentClosure]?
    var type: String?
    var anonymousId: String?
    var messageId: String?
    var userId: String?
    var timestamp: String?
    var context: JSON?
    var integrations: JSON?
    var metrics: [JSON]?
    var _metadata: DestinationMetadata?

    func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue("event", .init(codingPath: [], debugDescription: "Cannot encode event"))
    }
}
