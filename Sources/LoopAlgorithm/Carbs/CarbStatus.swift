//
//  CarbStatus.swift
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


public struct CarbStatus {
    /// The last-computed absorption of the carbs
    public let absorption: AbsorbedCarbValue?

    /// The timeline of observed carb absorption. Nil if observed absorption is less than the modeled minimum
    public let observedTimeline: [CarbValue]?

    public var quantity: HKQuantity

    public var startDate: Date

    public var originalAbsorptionTime: TimeInterval?
}


// Masquerade as a carb entry, substituting AbsorbedCarbValue's interpretation of absorption time
extension CarbStatus: CarbEntry {
    public var absorptionTime: TimeInterval? {
        return absorption?.estimatedDate.duration ?? originalAbsorptionTime
    }
}


extension CarbStatus {

    func dynamicCarbsOnBoard(at date: Date, defaultAbsorptionTime: TimeInterval, delay: TimeInterval, delta: TimeInterval, absorptionModel: CarbAbsorptionComputable) -> Double {
        guard date >= startDate - delta,
            let absorption = absorption
        else {
            // We have to have absorption info for dynamic calculation
            return carbsOnBoard(at: date, defaultAbsorptionTime: defaultAbsorptionTime, delay: delay, absorptionModel: absorptionModel)
        }

        let unit = HKUnit.gram()

        guard let observedTimeline = observedTimeline, let observationEnd = observedTimeline.last?.endDate else {
            // Less than minimum observed or observation not yet started; calc based on modeled absorption rate
            let total = absorption.total.doubleValue(for: unit)
            let time = date.timeIntervalSince(startDate) - delay
            let absorptionTime = absorption.estimatedDate.duration
            return absorptionModel.unabsorbedCarbs(of: total, atTime: time, absorptionTime: absorptionTime)
        }

        guard date <= observationEnd else {
            // Predicted absorption for remaining carbs, post-observation
            let effectiveTime = date.timeIntervalSince(observationEnd) + absorption.timeToAbsorbObservedCarbs
            let effectiveAbsorptionTime = absorption.timeToAbsorbObservedCarbs + absorption.estimatedTimeRemaining
            let total = absorption.total.doubleValue(for: unit)
            let unabsorbedAtEffectiveTime = absorptionModel.unabsorbedCarbs(of: total, atTime: effectiveTime, absorptionTime: effectiveAbsorptionTime)
            let unabsorbedCarbs = max(unabsorbedAtEffectiveTime, 0.0)
            return unabsorbedCarbs
        }

        // Observed absorption
        // TODO: This creates an O(n^2) situation for COB timelines
        let total = quantity.doubleValue(for: unit)
        return max(observedTimeline.filter({ $0.endDate <= date }).reduce(total) { (total, value) -> Double in
            return total - value.quantity.doubleValue(for: unit)
        }, 0)
    }

    func dynamicAbsorbedCarbs(at date: Date, absorptionTime: TimeInterval, delay: TimeInterval, delta: TimeInterval, absorptionModel: CarbAbsorptionComputable) -> Double {
        guard date >= startDate,
            let absorption = absorption
        else {
            // We have to have absorption info for dynamic calculation
            return absorbedCarbs(at: date, absorptionTime: absorptionTime, delay: delay, absorptionModel: absorptionModel)
        }

        let unit = HKUnit.gram()

        guard let observedTimeline = observedTimeline, let observationEnd = observedTimeline.last?.endDate else {
            // Less than minimum observed or observation not yet started; calc based on modeled absorption rate
            let total = absorption.total.doubleValue(for: unit)
            let time = date.timeIntervalSince(startDate) - delay
            let absorptionTime = absorption.estimatedDate.duration
            return absorptionModel.absorbedCarbs(of: total, atTime: time, absorptionTime: absorptionTime)
        }

        guard date <= observationEnd else {
            // Predicted absorption for remaining carbs, post-observation
            let effectiveTime = date.timeIntervalSince(observationEnd) + absorption.timeToAbsorbObservedCarbs
            let effectiveAbsorptionTime = absorption.timeToAbsorbObservedCarbs + absorption.estimatedTimeRemaining
            let total = absorption.total.doubleValue(for: unit)
            let absorbedAtEffectiveTime = absorptionModel.absorbedCarbs(of: total, atTime: effectiveTime, absorptionTime: effectiveAbsorptionTime)
            let absorbedCarbs = min(absorbedAtEffectiveTime, total)
            return absorbedCarbs
        }

        // Observed absorption
        // TODO: This creates an O(n^2) situation for carb effect timelines
        var sum: Double = 0
        var beforeDate = observedTimeline.filter { (value) -> Bool in
            value.startDate.addingTimeInterval(delta) <= date
        }

        // Apply only a portion of the value if it extends past the final value
        if let last = beforeDate.popLast() {
            let observationInterval = DateInterval(start: last.startDate, end: last.endDate)
            if  observationInterval.duration > 0,
                let calculationInterval = DateInterval(start: last.startDate, end: date).intersection(with: observationInterval)
            {
                sum += calculationInterval.duration / observationInterval.duration * last.quantity.doubleValue(for: unit)
            }
        }

        return min(beforeDate.reduce(sum) { (sum, value) -> Double in
            return sum + value.quantity.doubleValue(for: unit)
        }, quantity.doubleValue(for: unit))
    }
}
