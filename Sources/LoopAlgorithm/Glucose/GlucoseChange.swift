//
//  GlucoseChange.swift
//  LoopAlgorithm
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


public struct GlucoseChange: SampleValue, Equatable {
    public var startDate: Date
    public var endDate: Date
    public var mgdl: Double

    public init(startDate: Date, endDate: Date, mgdl: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.mgdl = mgdl
    }

    init(startDate: Date, endDate: Date, quantity: LoopQuantity) {
        self.init(startDate: startDate, endDate: endDate, mgdl: quantity.doubleValue(for: .milligramsPerDeciliter))
    }

    var quantity: LoopQuantity {
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl)
    }
}


extension GlucoseChange {
    mutating public func append(_ effect: GlucoseEffect) {
        startDate = min(effect.startDate, startDate)
        endDate = max(effect.endDate, endDate)
        mgdl += effect.mgdl
    }
}

extension GlucoseChange: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.mgdl = try container.decode(Double.self, forKey: .mgdl)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(mgdl, forKey: .mgdl)
    }

    private enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case mgdl
    }
}
