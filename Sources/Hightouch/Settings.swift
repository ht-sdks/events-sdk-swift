//
//  Settings.swift
//  Segment
//
//  Created by Cody Garvin on 12/15/20.
//

import Foundation

public struct Settings: Codable {
    public var integrations: JSON? = nil
    public var plan: JSON? = nil
    public var edgeFunction: JSON? = nil
    public var middlewareSettings: JSON? = nil

    public init(writeKey: String, apiHost: String) {
        integrations = try! JSON([
            SegmentDestination.Constants.integrationName.rawValue: [
                SegmentDestination.Constants.apiKey.rawValue: writeKey,
                SegmentDestination.Constants.apiHost.rawValue: apiHost
            ]
        ])
    }
    
    public init(writeKey: String) {
        integrations = try! JSON([
            SegmentDestination.Constants.integrationName.rawValue: [
                SegmentDestination.Constants.apiKey.rawValue: writeKey,
                SegmentDestination.Constants.apiHost.rawValue: HTTPClient.getDefaultAPIHost()
            ]
        ])
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.integrations = try? values.decode(JSON.self, forKey: CodingKeys.integrations)
        self.plan = try? values.decode(JSON.self, forKey: CodingKeys.plan)
        self.edgeFunction = try? values.decode(JSON.self, forKey: CodingKeys.edgeFunction)
        self.middlewareSettings = try? values.decode(JSON.self, forKey: CodingKeys.middlewareSettings)
    }
    
    static public func load(from url: URL?) -> Settings? {
        guard let url = url else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let settings = try? JSONDecoder().decode(Settings.self, from: data)
        return settings
    }
    
    static public func load(resource: String, bundle: Bundle = Bundle.main) -> Settings? {
        let url = bundle.url(forResource: resource, withExtension: nil)
        return load(from: url)
    }
    
    enum CodingKeys: String, CodingKey {
        case integrations
        case plan
        case edgeFunction
        case middlewareSettings
    }
    
    /**
     * Easily retrieve settings for a specific integration name.
     *
     * - Parameter for: The string name of the integration
     * - Returns: The dictionary representing the settings for this integration as supplied by Segment.com
     */
    public func integrationSettings(forKey key: String) -> [String: Any]? {
        guard let settings = integrations?.dictionaryValue else { return nil }
        let result = settings[key] as? [String: Any]
        return result
    }
    
    public func integrationSettings<T: Codable>(forKey key: String) -> T? {
        var result: T? = nil
        guard let settings = integrations?.dictionaryValue else { return nil }
        if let dict = settings[key], let jsonData = try? JSONSerialization.data(withJSONObject: dict) {
            result = try? JSONDecoder().decode(T.self, from: jsonData)
        }
        return result
    }
    
    public func integrationSettings<T: Codable>(forPlugin plugin: DestinationPlugin) -> T? {
        return integrationSettings(forKey: plugin.key)
    }
    
    public func hasIntegrationSettings(forPlugin plugin: DestinationPlugin) -> Bool {
        return hasIntegrationSettings(key: plugin.key)
    }

    public func hasIntegrationSettings(key: String) -> Bool {
        guard let settings = integrations?.dictionaryValue else { return false }
        return (settings[key] != nil)
    }
}

extension Settings: Equatable {
    public static func == (lhs: Settings, rhs: Settings) -> Bool {
        let l = lhs.prettyPrint()
        let r = rhs.prettyPrint()
        return l == r
    }
}
