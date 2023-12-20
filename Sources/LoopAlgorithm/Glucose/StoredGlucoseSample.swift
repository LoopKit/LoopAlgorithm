//
//  StoredGlucoseSample.swift
//  LoopKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit

public struct StoredGlucoseSample: GlucoseSampleValue, Equatable {
    public let uuid: UUID?  // Note this is the UUID from HealthKit.  Nil if not (yet) stored in HealthKit.

    public static let defaultProvenanceIdentifier = "com.LoopKit.Loop"

    // MARK: - HealthKit Sync Support

    public let provenanceIdentifier: String
    public let syncIdentifier: String?
    public let syncVersion: Int?
    public let device: HKDevice?
    public let healthKitEligibleDate: Date?

    // MARK: - SampleValue

    public let startDate: Date
    public let quantity: HKQuantity

    // MARK: - GlucoseSampleValue

    public let isDisplayOnly: Bool
    public let wasUserEntered: Bool
    public let condition: GlucoseCondition?
    public let trend: GlucoseTrend?
    public let trendRate: HKQuantity?

    public init(
        uuid: UUID? = nil,
        provenanceIdentifier: String = Self.defaultProvenanceIdentifier,
        syncIdentifier: String? = nil,
        syncVersion: Int? = nil,
        startDate: Date,
        quantity: HKQuantity,
        condition: GlucoseCondition? = nil,
        trend: GlucoseTrend? = nil,
        trendRate: HKQuantity? = nil,
        isDisplayOnly: Bool = false,
        wasUserEntered: Bool = false,
        device: HKDevice? = nil,
        healthKitEligibleDate: Date? = nil) {
        self.uuid = uuid
        self.provenanceIdentifier = provenanceIdentifier
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.startDate = startDate
        self.quantity = quantity
        self.condition = condition
        self.trend = trend
        self.trendRate = trendRate
        self.isDisplayOnly = isDisplayOnly
        self.wasUserEntered = wasUserEntered
        self.device = device
        self.healthKitEligibleDate = healthKitEligibleDate
    }
}

extension StoredGlucoseSample: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid)
        let provenanceIdentifier = try container.decodeIfPresent(String.self, forKey: .provenanceIdentifier) ?? Self.defaultProvenanceIdentifier
        let wasUserEntered = try container.decodeIfPresent(Bool.self, forKey: .wasUserEntered) ?? false
        let isDisplayOnly = try container.decodeIfPresent(Bool.self, forKey: .isDisplayOnly) ?? false

        self.init(uuid: uuid,
                  provenanceIdentifier: provenanceIdentifier,
                  syncIdentifier: try container.decodeIfPresent(String.self, forKey: .syncIdentifier),
                  syncVersion: try container.decodeIfPresent(Int.self, forKey: .syncVersion),
                  startDate: try container.decode(Date.self, forKey: .startDate),
                  quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: try container.decode(Double.self, forKey: .quantity)),
                  condition: try container.decodeIfPresent(GlucoseCondition.self, forKey: .condition),
                  trend: try container.decodeIfPresent(GlucoseTrend.self, forKey: .trend),
                  trendRate: try container.decodeIfPresent(Double.self, forKey: .trendRate).map { HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: $0) },
                  isDisplayOnly: isDisplayOnly,
                  wasUserEntered: wasUserEntered,
                  healthKitEligibleDate: try container.decodeIfPresent(Date.self, forKey: .healthKitEligibleDate))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        if provenanceIdentifier != Self.defaultProvenanceIdentifier {
            try container.encode(provenanceIdentifier, forKey: .provenanceIdentifier)
        }
        try container.encodeIfPresent(syncIdentifier, forKey: .syncIdentifier)
        try container.encodeIfPresent(syncVersion, forKey: .syncVersion)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(quantity.doubleValue(for: .milligramsPerDeciliter), forKey: .quantity)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encodeIfPresent(trend, forKey: .trend)
        try container.encodeIfPresent(trendRate?.doubleValue(for: .milligramsPerDeciliterPerMinute), forKey: .trendRate)
        if isDisplayOnly {
            try container.encode(isDisplayOnly, forKey: .isDisplayOnly)
        }
        if wasUserEntered {
            try container.encode(wasUserEntered, forKey: .wasUserEntered)
        }
        try container.encodeIfPresent(healthKitEligibleDate, forKey: .healthKitEligibleDate)
    }

    private enum CodingKeys: String, CodingKey {
        case uuid
        case provenanceIdentifier
        case syncIdentifier
        case syncVersion
        case startDate
        case quantity
        case condition
        case trend
        case trendRate
        case isDisplayOnly
        case wasUserEntered
        case device
        case healthKitEligibleDate
    }
}
