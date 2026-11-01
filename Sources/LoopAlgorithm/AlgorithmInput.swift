//
//  AlgorithmInput.swift
//  LoopAlgorithm
//
//  Created by Pete Schwamb on 9/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation


/// The inputs to `Algorithm.run(input:)`. Glucose values are in mg/dL, carbs in grams and insulin in units.
public protocol AlgorithmInput {
    associatedtype CarbType: CarbEntry
    associatedtype GlucoseType: GlucoseSampleValue
    associatedtype InsulinDoseType: InsulinDose

    var predictionStart: Date { get }
    var glucoseHistory: [GlucoseType] { get }
    var doses: [InsulinDoseType] { get }
    var carbEntries: [CarbType] { get }
    /// Scheduled basal rate in U/h
    var basal: [AbsoluteScheduleValue<Double>] { get }
    /// Insulin sensitivity in mg/dL per unit
    var sensitivityMgdlPerUnit: [AbsoluteScheduleValue<Double>] { get }
    /// Carb ratio in grams per unit
    var carbRatio: [AbsoluteScheduleValue<Double>] { get }
    /// Correction range in mg/dL
    var targetMgdl: GlucoseRangeTimeline { get }
    /// Suspend threshold in mg/dL
    var suspendThresholdMgdl: Double? { get }
    /// Maximum bolus in units
    var maxBolus: Double { get }
    /// Limit on active insulin, as a multiple of `maxBolus`. Defaults to 2.
    var maxActiveInsulinMultiplier: Double? { get }
    /// Maximum basal rate in U/h
    var maxBasalRate: Double { get }
    var useIntegralRetrospectiveCorrection: Bool { get }
    var includePositiveVelocityAndRC: Bool { get }
    var useMidAbsorptionISF: Bool { get }
    var carbAbsorptionModel: CarbAbsorptionModel { get }
    var recommendationInsulinModel: InsulinModel { get }
    var recommendationType: DoseRecommendationType { get }
    /// Fraction of the correction given as an automatic bolus. Defaults to 0.4.
    var automaticBolusApplicationFactor: Double? { get }
    /// Largest jump in mg/dL between consecutive glucose readings for retrospective correction to apply.
    /// Defaults to 40.
    var gradualTransitionsThreshold: Double? { get }
    /// Options for reproducing earlier deployed algorithm behavior. Defaults to nil (no emulation).
    var emulation: AlgorithmEmulationOptions? { get }
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

extension AlgorithmInput {
    var sensitivityQuantities: [AbsoluteScheduleValue<LoopQuantity>] { sensitivityMgdlPerUnit.mgdlQuantities }
    var targetQuantities: QuantityRangeTimeline { targetMgdl.quantities }
    var suspendThresholdQuantity: LoopQuantity? { suspendThresholdMgdl.map(LoopQuantity.mgdl) }
}
