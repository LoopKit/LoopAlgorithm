//
//  AlgorithmInput.swift
//  LoopAlgorithm
//
//  Created by Pete Schwamb on 9/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation


public protocol AlgorithmInput {
    associatedtype CarbType: CarbEntry
    associatedtype GlucoseType: GlucoseSampleValue
    associatedtype InsulinDoseType: InsulinDose

    var predictionStart: Date { get }
    var glucoseHistory: [GlucoseType] { get }
    var doses: [InsulinDoseType] { get }
    var carbEntries: [CarbType] { get }
    var basal: [AbsoluteScheduleValue<Double>] { get }
    var sensitivity: [AbsoluteScheduleValue<LoopQuantity>] { get }
    var carbRatio: [AbsoluteScheduleValue<Double>] { get }
    var target: GlucoseRangeTimeline { get }
    var suspendThreshold: LoopQuantity? { get }
    var maxBolus: Double { get }
    var maxActiveInsulinMultiplier: Double? { get }  // Defaults to 2 (2x maxBolus)
    var maxBasalRate: Double { get }
    var useIntegralRetrospectiveCorrection: Bool { get }
    var includePositiveVelocityAndRC: Bool { get }
    var useMidAbsorptionISF: Bool { get }
    var carbAbsorptionModel: CarbAbsorptionModel { get }
    var recommendationInsulinModel: InsulinModel { get }
    var recommendationType: DoseRecommendationType { get }
    var automaticBolusApplicationFactor: Double? { get } // Defaults to 0.4
    var gradualTransitionsThreshold: Double? { get }
    var emulation: AlgorithmEmulationOptions? { get } // Defaults to nil (no emulation)
    /// Optional algorithm experiments; the empty set is standard LoopAlgorithm. Conforming types that do
    /// not provide it get the empty set.
    var experiments: Set<ExperimentOption> { get }
    /// The person's volatility baseline for the `guardAndRunway` experiment's volatility band: the median
    /// σ5 (mg/dL per 5 min) over their last four weeks of glucose, from `GlucoseVolatility.baseline(_:)`.
    /// When nil it is computed from `glucoseHistory` if that holds at least a day of readings; otherwise
    /// the band runs at full depth.
    var volatilityBaseline: Double? { get }
}

public extension AlgorithmInput {
    var emulation: AlgorithmEmulationOptions? { nil }
    var experiments: Set<ExperimentOption> { [] }
    var volatilityBaseline: Double? { nil }
}
