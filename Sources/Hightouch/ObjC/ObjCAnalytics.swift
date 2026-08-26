//
//  ObjCAnalytics.swift
//  
//
//  Created by Cody Garvin on 6/10/21.
//

#if !os(Linux)

import Foundation

// MARK: - ObjC Compatibility

@objc(HTAnalytics)
public class ObjCAnalytics: NSObject {
    /// The underlying Analytics object we're working with
    public let analytics: Analytics
    
    @objc
    public init(configuration: ObjCConfiguration) {
        self.analytics = Analytics(configuration: configuration.configuration)
    }
    
    /// Get a workable ObjC instance by wrapping a Swift instance
    /// Useful when you want additional flexibility or to share
    /// a single instance between ObjC<>Swift.
    public init(wrapping analytics: Analytics) {
        self.analytics = analytics
    }
}

// MARK: - ObjC Events

@objc
extension ObjCAnalytics {
    @objc(track:)
    public func track(name: String) {
        track(name: name, properties: nil, context: nil)
    }
    

    @objc(track:properties:)
    public func track(name: String, properties: [String: Any]?) {
        track(name: name, properties: properties, context: nil)
    }

    @objc(track:properties:context:)
    public func track(name: String, properties: [String: Any]?, context: [String: Any]?) {
        analytics.track(name: name, properties: properties, context: context)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID (or email address) for this user.
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    @objc(identify:)
    public func identify(userId: String) {
        identify(userId: userId, traits: nil)
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID (or email address) for this user.
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    @objc(identify:traits:)
    public func identify(userId: String?, traits: [String: Any]?) {
        identify(userId: userId, traits: traits, context: nil)
    }

    @objc(identify:traits:context:)
    public func identify(userId: String?, traits: [String: Any]?, context: [String: Any]?) {
        if let userId = userId {
            // at first glance this looks like recursion.  It's actually calling
            // into the swift version of this call where userId is NOT optional.
            analytics.identify(userId: userId, traits: traits, context: context)
        } else if let traits = try? JSON(traits as Any) {
            analytics.store.dispatch(action: UserInfo.SetTraitsAction(traits: traits))
            let userInfo: UserInfo? = analytics.store.currentState()
            let userId = userInfo?.userId
            let event = IdentifyEvent(userId: userId, traits: traits)
            analytics.process(incomingEvent: event, context: context)
        }
    }
    
    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - title: The title of the screen being tracked.
    @objc(screen:)
    public func screen(title: String) {
        screen(title: title, category: nil, properties: nil, context: nil)
    }
    
    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - title: The title of the screen being tracked.
    ///   - category: A category to the type of screen if it applies.
    @objc(screen:category:)
    public func screen(title: String, category: String?) {
        analytics.screen(title: title, category: category, properties: nil)
    }
    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - title: The title of the screen being tracked.
    ///   - category: A category to the type of screen if it applies.
    ///   - properties: Any extra metadata associated with the screen. e.g. method of access, size, etc.
    @objc(screen:category:properties:)
    public func screen(title: String, category: String?, properties: [String: Any]?) {
        screen(title: title, category: category, properties: properties, context: nil)
    }

    @objc(screen:category:properties:context:)
    public func screen(title: String, category: String?, properties: [String: Any]?, context: [String: Any]?) {
        analytics.screen(title: title, category: category, properties: properties, context: context)
    }

    /// Associate a user with a group such as a company, organization, project, etc.
    /// - Parameters:
    ///   - groupId: A unique identifier for the group identification in your system.
    @objc(group:)
    public func group(groupId: String) {
        group(groupId: groupId, traits: nil)
    }

    /// Associate a user with a group such as a company, organization, project, etc.
    /// - Parameters:
    ///   - groupId: A unique identifier for the group identification in your system.
    ///   - traits: Traits of the group you may be interested in such as email, phone or name.
    @objc(group:traits:)
    public func group(groupId: String, traits: [String: Any]?) {
        group(groupId: groupId, traits: traits, context: nil)
    }

    @objc(group:traits:context:)
    public func group(groupId: String, traits: [String: Any]?, context: [String: Any]?) {
        analytics.group(groupId: groupId, traits: traits, context: context)
    }
    
    @objc(alias:)
    /// The alias method is used to merge two user identities, effectively connecting two sets of user data
    /// as one. This is an advanced method, but it is required to manage user identities successfully in some of our destinations.
    /// - Parameter newId: The new id replacing the old user id.
    public func alias(newId: String) {
        alias(newId: newId, context: nil)
    }

    @objc(alias:context:)
    public func alias(newId: String, context: [String: Any]?) {
        analytics.alias(newId: newId, context: context)
    }
}


// MARK: - ObjC Peripheral Functionality

@objc
extension ObjCAnalytics {
    @objc
    public var anonymousId: String {
        return analytics.anonymousId
    }
    
    @objc
    public var userId: String? {
        return analytics.userId
    }
    
    @objc
    public func traits() -> [String: Any]? {
        return analytics.traits()
    }
    
    @objc
    public func flush() {
        analytics.flush()
    }
    
    @objc
    public func reset() {
        analytics.reset()
    }
    
    @objc
    public func settings() -> [String: Any]? {
        var result: [String: Any]? = nil
        if let system: System = analytics.store.currentState() {
            do {
                let encoder = JSONEncoder()
                let json = try encoder.encode(system.settings)
                if let r = try JSONSerialization.jsonObject(with: json) as? [String: Any] {
                    result = r
                }
            } catch {
                // not sure why this would fail, but report it.
                exceptionFailure("Failed to convert Settings to ObjC dictionary: \(error)")
            }
        }
        return result
    }
    
    @objc
    public func openURL(_ url: URL, options: [String: Any] = [:]) {
        analytics.openURL(url, options: options)
    }
    
    @objc
    public func version() -> String {
        return analytics.version()
    }
}

#endif
