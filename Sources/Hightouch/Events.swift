//
//  Events.swift
//  Segment
//
//  Created by Cody Garvin on 11/30/20.
//

import Foundation

// MARK: - Typed Event Signatures

extension Analytics {
    // Per-call `context` is deep-merged onto that event's context (nested maps
    // merge; per-call values win on conflict). This is not Segment Classic `options`.
    
    public func track<P: Codable>(name: String, properties: P?, context: [String: Any]? = nil) {
        do {
            if let properties = properties {
                let jsonProperties = try JSON(with: properties)
                let event = TrackEvent(event: name, properties: jsonProperties)
                process(incomingEvent: event, context: context)
            } else {
                let event = TrackEvent(event: name, properties: nil)
                process(incomingEvent: event, context: context)
            }
        } catch {
            reportInternalError(error, fatal: true)
        }
    }
    
    public func track(name: String) {
        track(name: name, properties: nil as TrackEvent?)
    }
    
    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user. If you don't have a userId
    ///     but want to record traits, just pass traits into the event and they will be associated
    ///     with the anonymousId of that user.  In the case when user logs out, make sure to
    ///     call ``reset()`` to clear the user's identity info. For more information on how we
    ///     generate the UUID and Apple's policies on IDs, see
    ///      https://segment.io/libraries/ios#ids
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    public func identify<T: Codable>(userId: String, traits: T?, context: [String: Any]? = nil) {
        do {
            if let traits = traits {
                let jsonTraits = try JSON(with: traits)
                store.dispatch(action: UserInfo.SetUserIdAndTraitsAction(userId: userId, traits: jsonTraits))
                let event = IdentifyEvent(userId: userId, traits: jsonTraits)
                process(incomingEvent: event, context: context)
            } else {
                store.dispatch(action: UserInfo.SetUserIdAndTraitsAction(userId: userId, traits: nil))
                let event = IdentifyEvent(userId: userId, traits: nil)
                process(incomingEvent: event, context: context)
            }
        } catch {
            reportInternalError(error, fatal: true)
        }
    }
    
    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    public func identify<T: Codable>(traits: T, context: [String: Any]? = nil) {
        do {
            let jsonTraits = try JSON(with: traits)
            store.dispatch(action: UserInfo.SetTraitsAction(traits: jsonTraits))
            let event = IdentifyEvent(traits: jsonTraits)
            process(incomingEvent: event, context: context)
        } catch {
            reportInternalError(error, fatal: true)
        }
    }

    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user.
    ///     For more information on how we generate the UUID and Apple's policies on IDs, see
    ///     https://segment.io/libraries/ios#ids
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    public func identify(userId: String) {
        let event = IdentifyEvent(userId: userId, traits: nil)
        store.dispatch(action: UserInfo.SetUserIdAction(userId: userId))
        process(incomingEvent: event)
    }
    
    public func screen<P: Codable>(title: String, category: String? = nil, properties: P?, context: [String: Any]? = nil) {
        do {
            if let properties = properties {
                let jsonProperties = try JSON(with: properties)
                let event = ScreenEvent(title: title, category: category, properties: jsonProperties)
                process(incomingEvent: event, context: context)
            } else {
                let event = ScreenEvent(title: title, category: category)
                process(incomingEvent: event, context: context)
            }
        } catch {
            reportInternalError(error, fatal: true)
        }
    }
    
    public func screen(title: String, category: String? = nil) {
        screen(title: title, category: category, properties: nil as ScreenEvent?)
    }

    public func group<T: Codable>(groupId: String, traits: T?, context: [String: Any]? = nil) {
        do {
            if let traits = traits {
                let jsonTraits = try JSON(with: traits)
                let event = GroupEvent(groupId: groupId, traits: jsonTraits)
                process(incomingEvent: event, context: context)
            } else {
                let event = GroupEvent(groupId: groupId)
                process(incomingEvent: event, context: context)
            }
        } catch {
            reportInternalError(error, fatal: true)
        }
    }
    
    public func group(groupId: String, context: [String: Any]? = nil) {
        group(groupId: groupId, traits: nil as GroupEvent?, context: context)
    }
    
    /// The alias method is used to merge two user identities, effectively connecting two sets of user data
    /// as one. Context is attached to this event value (not a shared plugin or queue), so overlapping
    /// alias calls cannot swap per-call context.
    /// - Parameters:
    ///   - newId: The new id replacing the old user id.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    public func alias(newId: String, context: [String: Any]? = nil) {
        let event = AliasEvent(newId: newId, previousId: self.userId)
        store.dispatch(action: UserInfo.SetUserIdAction(userId: newId))
        process(incomingEvent: event, context: context)
    }
}

// MARK: - Untyped Event Signatures

extension Analytics {
    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user. If you don't have a userId
    ///     but want to record traits, just pass traits into the event and they will be associated
    ///     with the anonymousId of that user.  In the case when user logs out, make sure to
    ///     call ``reset()`` to clear the user's identity info. For more information on how we
    ///     generate the UUID and Apple's policies on IDs, see
    ///      https://segment.io/libraries/ios#ids
    ///   - properties: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    public func track(name: String, properties: [String: Any]? = nil, context: [String: Any]? = nil) {
        var props: JSON? = nil
        if let properties = properties {
            do {
                props = try JSON(properties)
            } catch {
                reportInternalError(error, fatal: true)
            }
        }
        let event = TrackEvent(event: name, properties: props)
        process(incomingEvent: event, context: context)
    }
    
    /// Associate a user with their unique ID and record traits about them.
    /// - Parameters:
    ///   - userId: A database ID for this user. If you don't have a userId
    ///     but want to record traits, just pass traits into the event and they will be associated
    ///     with the anonymousId of that user.  In the case when user logs out, make sure to
    ///     call ``reset()`` to clear the user's identity info. For more information on how we
    ///     generate the UUID and Apple's policies on IDs, see
    ///      https://segment.io/libraries/ios#ids
    ///   - traits: A dictionary of traits you know about the user. Things like: email, name, plan, etc.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    /// In the case when user logs out, make sure to call ``reset()`` to clear user's identity info.
    public func identify(userId: String, traits: [String: Any]? = nil, context: [String: Any]? = nil) {
        do {
            if let traits = traits {
                let traits = try JSON(traits as Any)
                store.dispatch(action: UserInfo.SetUserIdAndTraitsAction(userId: userId, traits: traits))
                let event = IdentifyEvent(userId: userId, traits: traits)
                process(incomingEvent: event, context: context)
            } else {
                store.dispatch(action: UserInfo.SetUserIdAndTraitsAction(userId: userId, traits: nil))
                let event = IdentifyEvent(userId: userId, traits: nil)
                process(incomingEvent: event, context: context)
            }
        } catch {
            reportInternalError(error, fatal: true)
        }
    }
    
    /// Track a screen change with a title, category and other properties.
    /// - Parameters:
    ///   - screenTitle: The title of the screen being tracked.
    ///   - category: A category to the type of screen if it applies.
    ///   - properties: Any extra metadata associated with the screen. e.g. method of access, size, etc.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    public func screen(title: String, category: String? = nil, properties: [String: Any]? = nil, context: [String: Any]? = nil) {
        // if properties is nil, this is the event that'll get used.
        var event = ScreenEvent(title: title, category: category, properties: nil)
        // if we have properties, get a new one rolling.
        if let properties = properties {
            do {
                let jsonProperties = try JSON(properties)
                event = ScreenEvent(title: title, category: category, properties: jsonProperties)
            } catch {
                reportInternalError(error, fatal: true)
            }
        }
        process(incomingEvent: event, context: context)
    }
    
    /// Associate a user with a group such as a company, organization, project, etc.
    /// - Parameters:
    ///   - groupId: A unique identifier for the group identification in your system.
    ///   - traits: Traits of the group you may be interested in such as email, phone or name.
    ///   - context: Optional per-call context, deep-merged onto this event only.
    public func group(groupId: String, traits: [String: Any]?, context: [String: Any]? = nil) {
        var event = GroupEvent(groupId: groupId)
        if let traits = traits {
            do {
                let jsonTraits = try JSON(traits)
                event = GroupEvent(groupId: groupId, traits: jsonTraits)
            } catch {
                reportInternalError(error, fatal: true)
            }
        }
        process(incomingEvent: event, context: context)
    }
}
