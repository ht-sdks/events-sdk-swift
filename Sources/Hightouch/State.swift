//
//  State.swift
//  Segment
//
//  Created by Brandon Sneed on 12/1/20.
//

import Foundation
import Sovran

// MARK: - System (Overall)

struct System: State {
    let configuration: Configuration
    let settings: Settings?
    let running: Bool
    let enabled: Bool
    let initializedPlugins: [Plugin]
    
    struct UpdateSettingsAction: Action {
        let settings: Settings
        
        func reduce(state: System) -> System {
            let result = System(configuration: state.configuration,
                                settings: settings,
                                running: state.running,
                                enabled: state.enabled,
                                initializedPlugins: state.initializedPlugins)
            return result
        }
    }
        
    struct ToggleRunningAction: Action {
        let running: Bool
        
        func reduce(state: System) -> System {
            return System(configuration: state.configuration,
                          settings: state.settings,
                          running: running,
                          enabled: state.enabled,
                          initializedPlugins: state.initializedPlugins)
        }
    }
    
    struct ToggleEnabledAction: Action {
        let enabled: Bool
        
        func reduce(state: System) -> System {
            return System(configuration: state.configuration,
                          settings: state.settings,
                          running: state.running,
                          enabled: enabled,
                          initializedPlugins: state.initializedPlugins)
        }
    }
    
    struct UpdateConfigurationAction: Action {
        let configuration: Configuration
        
        func reduce(state: System) -> System {
            return System(configuration: configuration,
                          settings: state.settings,
                          running: state.running,
                          enabled: state.enabled,
                          initializedPlugins: state.initializedPlugins)
        }
    }
    
    struct AddDestinationToSettingsAction: Action {
        let key: String
        
        func reduce(state: System) -> System {
            var settings = state.settings
            if var integrations = settings?.integrations?.dictionaryValue {
                integrations[key] = true
                settings?.integrations = try? JSON(integrations)
            }
            return System(configuration: state.configuration,
                          settings: settings,
                          running: state.running,
                          enabled: state.enabled,
                          initializedPlugins: state.initializedPlugins)
        }
    }

    struct AddPluginToInitialized: Action {
        let plugin: Plugin

        func reduce(state: System) -> System {
            var initializedPlugins = state.initializedPlugins
            if !initializedPlugins.contains(where: { p in
                return plugin === p
            }) {
                initializedPlugins.append(plugin)
            }
            return System(configuration: state.configuration,
                          settings: state.settings,
                          running: state.running,
                          enabled: state.enabled,
                          initializedPlugins: initializedPlugins)
        }
    }
}


// MARK: - User information

struct UserInfo: Codable, State {
    let anonymousId: String
    let userId: String?
    let traits: JSON?
    let referrer: URL?
    
    struct ResetAction: Action {
        func reduce(state: UserInfo) -> UserInfo {
            return UserInfo(anonymousId: UUID().uuidString, userId: nil, traits: nil, referrer: nil)
        }
    }
    
    struct SetUserIdAction: Action {
        let userId: String
        
        func reduce(state: UserInfo) -> UserInfo {
            return UserInfo(anonymousId: state.anonymousId, userId: userId, traits: state.traits, referrer: state.referrer)
        }
    }
    
    struct SetTraitsAction: Action {
        let traits: JSON?
        
        func reduce(state: UserInfo) -> UserInfo {
            return UserInfo(anonymousId: state.anonymousId, userId: state.userId, traits: traits, referrer: state.referrer)
        }
    }
    
    struct SetUserIdAndTraitsAction: Action {
        let userId: String?
        let traits: JSON?
        
        func reduce(state: UserInfo) -> UserInfo {
            return UserInfo(anonymousId: state.anonymousId, userId: userId, traits: traits, referrer: state.referrer)
        }
    }
    
    struct SetAnonymousIdAction: Action {
        let anonymousId: String
        
        func reduce(state: UserInfo) -> UserInfo {
            return UserInfo(anonymousId: anonymousId, userId: state.userId, traits: state.traits, referrer: state.referrer)
        }
    }
    
    struct SetReferrerAction: Action {
        let url: URL
        
        func reduce(state: UserInfo) -> UserInfo {
            return UserInfo(anonymousId: state.anonymousId, userId: state.userId, traits: state.traits, referrer: url)
        }
    }
}

// MARK: - Default State Setup

extension System {
    static func defaultState(configuration: Configuration, from storage: Storage) -> System {
        var settings: Settings? = storage.read(.settings)
        if settings == nil {
            if let defaults = configuration.values.defaultSettings {
                settings = defaults
            } else {
                settings = Settings(writeKey: configuration.values.writeKey, apiHost: HTTPClient.getDefaultAPIHost())
            }
        }
        return System(configuration: configuration, settings: settings, running: false, enabled: true, initializedPlugins: [Plugin]())
    }
}

extension UserInfo {
    static func defaultState(from storage: Storage) -> UserInfo {
        let userId: String? = storage.read(.userId)
        let traits: JSON? = storage.read(.traits)

        // migrate external anonymous ids to hightouch
        var anonymousId: String = UUID().uuidString
        if let existingAnonId: String = storage.read(.anonymousId) {
            anonymousId = existingAnonId
        } else if let segmentAnonId: String = storage.read(.anonymousIdSegment) {
            anonymousId = segmentAnonId
        } else if let rudderAnonId: String = storage.read(.anonymousIdRudder) {
            anonymousId = rudderAnonId
        }

        return UserInfo(anonymousId: anonymousId, userId: userId, traits: traits, referrer: nil)
    }
}
