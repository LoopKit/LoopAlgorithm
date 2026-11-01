//
//  StoredCarbEntry.swift
//
//  Created by Nathan Racklyeft on 1/22/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

public struct FixtureCarbEntry: CarbEntry {
    public var absorptionTime: TimeInterval?
    public var startDate: Date
    public var grams: Double
    public var foodType: String?

    public init(
        absorptionTime: TimeInterval? = nil,
        startDate: Date,
        grams: Double,
        foodType: String? = nil
    ) {
        self.absorptionTime = absorptionTime
        self.startDate = startDate
        self.grams = grams
        self.foodType = foodType
    }

    init(
        absorptionTime: TimeInterval? = nil,
        startDate: Date,
        quantity: LoopQuantity,
        foodType: String? = nil
    ) {
        self.init(absorptionTime: absorptionTime, startDate: startDate, grams: quantity.doubleValue(for: .gram), foodType: foodType)
    }
}

extension FixtureCarbEntry: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            absorptionTime: try container.decodeIfPresent(TimeInterval.self, forKey: .absorptionTime),
            startDate: try container.decode(Date.self, forKey: .date),
            grams: try container.decode(Double.self, forKey: .grams)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(absorptionTime, forKey: .absorptionTime)
        try container.encode(startDate, forKey: .date)
        try container.encode(grams, forKey: .grams)
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case grams
        case absorptionTime
    }
}

