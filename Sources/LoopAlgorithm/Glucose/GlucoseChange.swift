//
//  GlucoseChange.swift
//  LoopAlgorithm
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit


public struct GlucoseChange: SampleValue, Equatable {
    public var startDate: Date
    public var endDate: Date
    public var quantity: HKQuantity

    public init(startDate: Date, endDate: Date, quantity: HKQuantity) {
        self.startDate = startDate
        self.endDate = endDate
        self.quantity = quantity
    }
}


extension GlucoseChange {
    mutating public func append(_ effect: GlucoseEffect) {
        startDate = min(effect.startDate, startDate)
        endDate = max(effect.endDate, endDate)
        quantity = HKQuantity(
            unit: .milligramsPerDeciliter,
            doubleValue: quantity.doubleValue(for: .milligramsPerDeciliter) + effect.quantity.doubleValue(for: .milligramsPerDeciliter)
        )
    }
}
