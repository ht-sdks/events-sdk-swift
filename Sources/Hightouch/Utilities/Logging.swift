//
//  Logging.swift
//  
//
//  Created by Brandon Sneed on 3/9/23.
//

import Foundation

extension Analytics {
    internal enum LogKind: CustomStringConvertible, CustomDebugStringConvertible {
        case error
        case warning
        case debug
        case none
        
        var description: String { return string }
        var debugDescription: String { return string }

        var string: String {
            switch self {
            case .error:
                return "HT_ERROR: "
            case .warning:
                return "HT_WARNING: "
            case .debug:
                return "HT_DEBUG: "
            case .none:
                return "HT_INFO: "
            }
        }
    }
    
    public func log(message: String) {
        Self.segmentLog(message: message, kind: .none)
    }
    
    static internal func segmentLog(message: String, kind: LogKind) {
        #if DEBUG
        if Self.debugLogsEnabled {
            print("\(kind)\(message)")
        }
        #endif
    }
}
