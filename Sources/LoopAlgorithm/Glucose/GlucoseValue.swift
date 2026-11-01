//
//  GlucoseValue.swift
//
//  Created by Nathan Racklyeft on 3/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

public protocol GlucoseValue: SampleValue {
    /// The glucose value in mg/dL
    var mgdl: Double { get }
}

extension GlucoseValue {
    var quantity: LoopQuantity {
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl)
    }
}

public struct SimpleGlucoseValue: Equatable, GlucoseValue {
    public let startDate: Date
    public let endDate: Date
    public let mgdl: Double

    public init(startDate: Date, endDate: Date? = nil, mgdl: Double) {
        self.startDate = startDate
        self.endDate = endDate ?? startDate
        self.mgdl = mgdl
    }

    init(startDate: Date, endDate: Date? = nil, quantity: LoopQuantity) {
        self.init(startDate: startDate, endDate: endDate, mgdl: quantity.doubleValue(for: .milligramsPerDeciliter))
    }

    public init(_ glucoseValue: GlucoseValue) {
        self.startDate = glucoseValue.startDate
        self.endDate = glucoseValue.endDate
        self.mgdl = glucoseValue.mgdl
    }
}

extension SimpleGlucoseValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? self.startDate
        self.mgdl = LoopQuantity(unit: LoopUnit(from: try container.decode(String.self, forKey: .quantityUnit)),
                                 doubleValue: try container.decode(Double.self, forKey: .quantity)).doubleValue(for: .milligramsPerDeciliter)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        if endDate != startDate {
            try container.encode(endDate, forKey: .endDate)
        }
        try container.encode(mgdl, forKey: .quantity)
        try container.encode(LoopUnit.milligramsPerDeciliter.unitString, forKey: .quantityUnit)
    }

    private enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case quantity
        case quantityUnit
    }
}

public struct PredictedGlucoseValue: Equatable, GlucoseValue {
    public let startDate: Date
    public let mgdl: Double

    public init(startDate: Date, mgdl: Double) {
        self.startDate = startDate
        self.mgdl = mgdl
    }

    init(startDate: Date, quantity: LoopQuantity) {
        self.init(startDate: startDate, mgdl: quantity.doubleValue(for: .milligramsPerDeciliter))
    }
}

extension PredictedGlucoseValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.mgdl = LoopQuantity(unit: LoopUnit(from: try container.decode(String.self, forKey: .quantityUnit)),
                                 doubleValue: try container.decode(Double.self, forKey: .quantity)).doubleValue(for: .milligramsPerDeciliter)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(mgdl, forKey: .quantity)
        try container.encode(LoopUnit.milligramsPerDeciliter.unitString, forKey: .quantityUnit)
    }

    private enum CodingKeys: String, CodingKey {
        case startDate
        case quantity
        case quantityUnit
    }
}
