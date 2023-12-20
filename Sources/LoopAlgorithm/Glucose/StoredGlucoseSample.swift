//
//  StoredGlucoseSample.swift
//  LoopKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit

public struct FixtureGlucoseSample: GlucoseSampleValue, Equatable {

    public static let defaultProvenanceIdentifier = "com.LoopKit.Loop"

    public let provenanceIdentifier: String
    public let startDate: Date
    public let quantity: HKQuantity
    public let isDisplayOnly: Bool

    public init(
        provenanceIdentifier: String = Self.defaultProvenanceIdentifier,
        startDate: Date,
        quantity: HKQuantity,
        isDisplayOnly: Bool = false
    ) {
        self.provenanceIdentifier = provenanceIdentifier
        self.startDate = startDate
        self.quantity = quantity
        self.isDisplayOnly = isDisplayOnly
    }
}

extension FixtureGlucoseSample: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let provenanceIdentifier = try container.decodeIfPresent(String.self, forKey: .provenanceIdentifier) ?? Self.defaultProvenanceIdentifier
        let isDisplayOnly = try container.decodeIfPresent(Bool.self, forKey: .isDisplayOnly) ?? false

        self.init(provenanceIdentifier: provenanceIdentifier,
                  startDate: try container.decode(Date.self, forKey: .startDate),
                  quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: try container.decode(Double.self, forKey: .quantity)),
                  isDisplayOnly: isDisplayOnly)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if provenanceIdentifier != Self.defaultProvenanceIdentifier {
            try container.encode(provenanceIdentifier, forKey: .provenanceIdentifier)
        }
        try container.encode(startDate, forKey: .startDate)
        try container.encode(quantity.doubleValue(for: .milligramsPerDeciliter), forKey: .quantity)
        if isDisplayOnly {
            try container.encode(isDisplayOnly, forKey: .isDisplayOnly)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case provenanceIdentifier
        case startDate
        case quantity
        case isDisplayOnly
    }
}
