//
//  FixtureInsulinDose.swift
//  
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

public struct FixtureInsulinDose: InsulinDose, Equatable {
    public var type: InsulinDoseType

    public var startDate: Date

    public var endDate: Date

    public var volume: Double

    public var insulinType: InsulinType?
}

extension FixtureInsulinDose: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(InsulinDoseType.self, forKey: .type)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.volume = try container.decode(Double.self, forKey: .volume)
        self.insulinType = try container.decodeIfPresent(InsulinType.self, forKey: .insulinType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(volume, forKey: .volume)
        try container.encodeIfPresent(insulinType, forKey: .insulinType)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case startDate
        case endDate
        case volume
        case insulinType
    }
}
