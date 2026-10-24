//
//  ExperimentalForecastAdjustments.swift
//  LoopAlgorithm
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

extension ExperimentParameters.PostLowRiseCut {
    /// True when current glucose is below `releaseGlucose` and some reading within `window` before it
    /// was below `lowThreshold`.
    func isActive<GlucoseType: GlucoseValue>(glucoseHistory: [GlucoseType]) -> Bool {
        let unit = LoopUnit.milligramsPerDeciliter
        guard let latest = glucoseHistory.last,
              latest.quantity.doubleValue(for: unit) < releaseGlucose else { return false }
        for sample in glucoseHistory.reversed() {
            if latest.startDate.timeIntervalSince(sample.startDate) > window { break }
            if sample.quantity.doubleValue(for: unit) < lowThreshold { return true }
        }
        return false
    }
}

extension LoopAlgorithm {

    /// The volatility band: each predicted point τ minutes ahead is lowered by
    /// `gain × σ5 × (τ/5)^exponent` up to `horizon`, tapering to zero by `taperEnd`.
    static func volatilityBanded(_ glucose: [PredictedGlucoseValue], band: ExperimentParameters.VolatilityBand,
                                 volatility: Double) -> [PredictedGlucoseValue] {
        guard band.gain > 0, let t0 = glucose.first?.startDate else { return glucose }
        let unit = LoopUnit.milligramsPerDeciliter
        let horizon = band.horizon.minutes
        let taperEnd = Swift.max(band.taperEnd.minutes, horizon + 1)
        let atHorizon = pow(Swift.max(horizon, 5.0) / 5.0, band.exponent)
        return glucose.map { point in
            let tau = point.startDate.timeIntervalSince(t0).minutes
            var shape = 0.0
            if tau <= 0 { shape = 0 }
            else if tau <= horizon { shape = pow(Swift.max(tau, 5.0) / 5.0, band.exponent) }
            else if tau < taperEnd { shape = atHorizon * (taperEnd - tau) / (taperEnd - horizon) }
            let offset = -band.gain * volatility * shape
            return PredictedGlucoseValue(startDate: point.startDate,
                                         quantity: LoopQuantity(unit: unit, doubleValue: point.quantity.doubleValue(for: unit) + offset))
        }
    }
    /// The runway reserve's aim shift, mg/dL (0 when the gate is closed or there is no room).
    ///
    /// Suppose Loop makes the correction it already plans (the excess of eventual glucose over the target
    /// midpoint) plus an extra E units. The plausible path τ minutes ahead is the forecast, less that
    /// planned correction's effect so far, less `bandWidth × σ5 × (τ/5)^exponent`. If glucose then followed
    /// it, suspending scheduled basal from now would take back `basal × ∫ acted` of insulin. E_max is the
    /// largest E for which that path, with the basal taken back, stays above the suspend threshold at every
    /// horizon out to `horizon` (a forecast shorter than `horizon` gives no runway). The shift spends `fraction` of it, expressed in mg/dL through the ISF and
    /// capped at `maxAimShift`.
    static func runwayAimShift(prediction: [PredictedGlucoseValue], reserve: ExperimentParameters.RunwayReserve,
                               currentGlucose: Double, activeCarbs: Double, volatility: Double,
                               sensitivity: Double, basalRate: Double, targetMidpoint: Double,
                               suspendThreshold: Double, insulinModel: InsulinModel) -> Double {
        let unit = LoopUnit.milligramsPerDeciliter
        guard volatility.isFinite, sensitivity > 0, currentGlucose >= reserve.minGlucose,
              !(reserve.carbGate && activeCarbs > 0),
              let t0 = prediction.first?.startDate, let last = prediction.last,
              // A forecast that stops short of the horizon cannot show a fall beyond its end: no runway.
              last.startDate.timeIntervalSince(t0) >= reserve.horizon else { return 0 }
        let eventual = last.quantity.doubleValue(for: unit)
        // (τ, glucose) on the forecast's own points, with any gap longer than 5 min (Loop drops points
        // once nothing is changing) filled every 5 min by linear interpolation.
        var samples: [(tau: Double, value: Double)] = []
        for point in prediction {
            let tau = point.startDate.timeIntervalSince(t0).minutes
            let value = point.quantity.doubleValue(for: unit)
            if let previous = samples.last, tau - previous.tau > 5.0 + 1e-9 {
                var fill = previous.tau + 5.0
                while fill < tau - 1e-9 {
                    samples.append((fill, previous.value + (value - previous.value) * (fill - previous.tau) / (tau - previous.tau)))
                    fill += 5.0
                }
            }
            samples.append((tau, value))
        }
        let excess = Swift.max(0, eventual - targetMidpoint)
        let horizon = reserve.horizon.minutes
        func acted(_ minutes: Double) -> Double {
            minutes <= 0 ? 0 : Swift.max(0, Swift.min(1, 1 - insulinModel.percentEffectRemaining(at: .minutes(minutes))))
        }
        var eMax = Double.infinity      // units of extra insulin
        var withheld = 0.0              // units of withheld basal that have acted by τ
        var lastTau = 0.0
        for (tau, value) in samples {
            if tau <= 0 { continue }
            if tau > horizon { break }
            withheld += basalRate / 60.0 * acted(0.5 * (tau + lastTau)) * (tau - lastTau)    // midpoint rule
            lastTau = tau
            let d = acted(tau)
            guard d > reserve.minEffectFraction else { continue }
            let path = value - excess * d
                - reserve.bandWidth * volatility * pow(Swift.max(tau, 5) / 5, reserve.exponent)
            eMax = Swift.min(eMax, (path + sensitivity * withheld - suspendThreshold) / (sensitivity * d))
        }
        guard eMax.isFinite else { return 0 }
        return Swift.min(reserve.maxAimShift, reserve.fraction * sensitivity * Swift.max(0, eMax))
    }

    /// The target range lowered by `shift` mg/dL, floored at 70–80.
    static func targetLowered(_ target: GlucoseRangeTimeline, by shift: Double) -> GlucoseRangeTimeline {
        let unit = LoopUnit.milligramsPerDeciliter
        return target.map {
            AbsoluteScheduleValue(
                startDate: $0.startDate, endDate: $0.endDate,
                value: ClosedRange(uncheckedBounds: (
                    lower: LoopQuantity(unit: unit, doubleValue: Swift.max(70.0, $0.value.lowerBound.doubleValue(for: unit) - shift)),
                    upper: LoopQuantity(unit: unit, doubleValue: Swift.max(80.0, $0.value.upperBound.doubleValue(for: unit) - shift)))))
        }
    }
}
