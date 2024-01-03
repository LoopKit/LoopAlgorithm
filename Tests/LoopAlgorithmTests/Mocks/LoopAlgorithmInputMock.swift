//
//  LoopAlgorithmInput.swift
//  
//
//  Created by Pete Schwamb on 1/2/24.
//

import Foundation
import HealthKit
@testable import LoopAlgorithm

public typealias LoopAlgorithmInputFixture = LoopAlgorithmInput<FixtureCarbEntry, FixtureGlucoseSample, FixtureInsulinDose>

extension LoopAlgorithmInput {
    /// Mocks stable, in range glucose, no insulin, no carbs, with reasonable settings
    static func mock(for now: Date = Date()) -> LoopAlgorithmInputFixture {

        func d(_ interval: TimeInterval) -> Date {
            return now.addingTimeInterval(interval)
        }

        return LoopAlgorithmInputFixture(
            predictionStart: now,
            glucoseHistory: [
                FixtureGlucoseSample(startDate: d(.minutes(-18)), quantity: .glucose(value: 105)),
                FixtureGlucoseSample(startDate: d(.minutes(-13)), quantity: .glucose(value: 105)),
                FixtureGlucoseSample(startDate: d(.minutes(-8)), quantity: .glucose(value: 105)),
                FixtureGlucoseSample(startDate: d(.minutes(-3)), quantity: .glucose(value: 105)),
            ],
            doses: [],
            carbEntries: [],
            basal: [AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now, value: 1.0)],
            sensitivity: [AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now.addingTimeInterval(InsulinMath.defaultInsulinActivityDuration), value: .glucose(value: 190))],
            carbRatio: [AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now, value: 10)],
            target: [AbsoluteScheduleValue(startDate: d(.hours(-10)), endDate: now, value: ClosedRange(uncheckedBounds: (lower: .glucose(value: 100), upper: .glucose(value: 110))))],
            suspendThreshold: .glucose(value: 70),
            maxBolus: 6,
            maxBasalRate: 9,
            recommendationInsulinType: .novolog,
            recommendationType: .tempBasal
        )
    }
}

extension HKQuantity {
    static func glucose(value: Double) -> HKQuantity {
        return .init(unit: .milligramsPerDeciliter, doubleValue: value)
    }

    static func carbs(value: Double) -> HKQuantity {
        return .init(unit: .gram(), doubleValue: value)
    }

}
