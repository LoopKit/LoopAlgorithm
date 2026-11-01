//
//  GlucoseEffectVelocity.swift
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


/// The first-derivative of GlucoseEffect, blood glucose over time.
public struct GlucoseEffectVelocity: SampleValue {
    public let startDate: Date
    public let endDate: Date
    public let mgdlPerSecond: Double

    public init(startDate: Date, endDate: Date, mgdlPerSecond: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.mgdlPerSecond = mgdlPerSecond
    }

    init(startDate: Date, endDate: Date, quantity: LoopQuantity) {
        self.init(startDate: startDate, endDate: endDate, mgdlPerSecond: quantity.doubleValue(for: GlucoseEffectVelocity.perSecondUnit))
    }

    var quantity: LoopQuantity {
        LoopQuantity(unit: GlucoseEffectVelocity.perSecondUnit, doubleValue: mgdlPerSecond)
    }
}


extension GlucoseEffectVelocity {
    static let perSecondUnit = LoopUnit.milligramsPerDeciliterPerSecond

    /// The integration of the velocity span
    public var effect: GlucoseEffect {
        let duration = endDate.timeIntervalSince(startDate)
        return GlucoseEffect(startDate: endDate, mgdl: mgdlPerSecond * duration)
    }
}

extension GlucoseEffectVelocity: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.mgdlPerSecond = try container.decode(Double.self, forKey: .mgdlPerSecond)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(mgdlPerSecond, forKey: .mgdlPerSecond)
    }

    private enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case mgdlPerSecond
    }
}
