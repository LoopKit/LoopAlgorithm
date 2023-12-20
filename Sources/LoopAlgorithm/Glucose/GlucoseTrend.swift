//
//  GlucoseTrend.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum GlucoseTrend: Int, CaseIterable {
    case upUpUp       = 1
    case upUp         = 2
    case up           = 3
    case flat         = 4
    case down         = 5
    case downDown     = 6
    case downDownDown = 7

    public var symbol: String {
        switch self {
        case .upUpUp:
            return "⇈"
        case .upUp:
            return "↑"
        case .up:
            return "↗︎"
        case .flat:
            return "→"
        case .down:
            return "↘︎"
        case .downDown:
            return "↓"
        case .downDownDown:
            return "⇊"
        }
    }

    public var arrows: String {
        switch self {
        case .upUpUp:
            return "↑↑"
        case .upUp:
            return "↑"
        case .up:
            return "↗︎"
        case .flat:
            return "→"
        case .down:
            return "↘︎"
        case .downDown:
            return "↓"
        case .downDownDown:
            return "↓↓"
        }
    }
}

extension GlucoseTrend {
    public init?(symbol: String) {
        switch symbol {
        case "↑↑":
            self = .upUpUp
        case "↑":
            self = .upUp
        case "↗︎":
            self = .up
        case "→":
            self = .flat
        case "↘︎":
            self = .down
        case "↓":
            self = .downDown
        case "↓↓":
            self = .downDownDown
        default:
            return nil
        }
    }
}

extension GlucoseTrend: Codable {}
