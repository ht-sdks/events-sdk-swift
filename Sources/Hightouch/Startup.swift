//
//  Startup.swift
//  Segment
//
//  Created by Cody Garvin on 1/5/21.
//

import Foundation
import Sovran

extension Analytics: Subscriber {
        
    internal func platformStartup() {
        add(plugin: StartupQueue())
        
        // add segment destination plugin unless
        // asked not to via configuration.
        if configuration.values.autoAddSegmentDestination {
            let segmentDestination = SegmentDestination()
            segmentDestination.analytics = self
            add(plugin: segmentDestination)
        }
        
        // Setup platform specific plugins
        if let platformPlugins = platformPlugins() {
            for plugin in platformPlugins {
                add(plugin: plugin)
            }
        }
        
        for policy in configuration.values.flushPolicies {
            policy.configure(analytics: self)
        }
        
        // Plugins receive local settings as they are added, before queued events are released.
        store.dispatch(action: System.ToggleRunningAction(running: true))
    }
    
    internal func platformPlugins() -> [PlatformPlugin]? {
        var plugins = [PlatformPlugin]()
        
        // add context plugin as well as it's platform specific internally.
        // this must come first.
        plugins.append(Context())
        
        plugins += VendorSystem.current.requiredPlugins

        if SessionPluginHelper.isEnabled(configuration.values) {
            plugins.append(SessionPlugin())
        }

        // setup lifecycle if desired
        if configuration.values.trackApplicationLifecycleEvents {
            #if os(iOS) || os(tvOS)
            plugins.append(iOSLifecycleEvents())
            #endif
            #if os(watchOS)
            plugins.append(watchOSLifecycleEvents())
            #endif
            #if os(macOS)
            plugins.append(macOSLifecycleEvents())
            #endif
            #if os(Linux)
            // placeholder - not sure what this is yet
            //plugins.append(LinuxLifecycleMonitor())
            #endif
        }
        
        if plugins.isEmpty {
            return nil
        } else {
            return plugins
        }
    }
}
