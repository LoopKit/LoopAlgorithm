//
//  AlgorithmExperiments.swift
//  LoopAlgorithm
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Optional algorithm experiments. The empty set (the default everywhere) is standard LoopAlgorithm.
///
/// Each experiment is an on/off switch with no tunable parameters, so that people who choose the same
/// switches pool into one group whose results can be compared. Experiments combine: each acts on its own
/// part of the algorithm, and a combination is its own group.
public enum AlgorithmExperiment: String, Codable, CaseIterable, Sendable {

    /// LoopEval guard + runway (C20 + C29 + C40). A lows guard, plus a little more correction when there
    /// is room for it:
    /// - **Post-low rise-cut** (C20). For 12 h after a reading below 70 mg/dL, and while glucose is
    ///   below 180, the rising side of retrospective correction is weighted 0.3×: the rebound after a
    ///   low (rescue carbs, counter-regulation) is not treated as a lasting need for insulin.
    /// - **Volatility band** (C29). While no carbs are on board, the first two hours of the forecast are
    ///   lowered in proportion to recent glucose volatility, so the low guard sees it. Eventual glucose
    ///   is unchanged. Its depth is keyed to the person's median volatility
    ///   (`AlgorithmInput.volatilityBaseline`), and is full depth until a baseline exists.
    /// - **Runway reserve** (C40). While glucose is 150 or above and no carbs are on board: how much
    ///   extra insulin could still be taken back by suspending scheduled basal, if glucose then fell
    ///   along the forecast less one σ of recent volatility, without reaching the suspend threshold
    ///   within 3 h? 70 % of that amount (at most 60 mg/dL's worth) is added to the automatic
    ///   correction. Calm glucose leaves room; volatile glucose leaves little or none. It is applied as
    ///   an internal lowering of the correction aim for automatic dosing only: the user's target, the
    ///   manual bolus recommendation and the suspend threshold are unchanged.
    case guardAndRunway

    /// Integral retrospective correction: retrospective correction integrates the recent unexplained
    /// glucose change instead of projecting only the last 30 minutes. The same as
    /// `AlgorithmInput.useIntegralRetrospectiveCorrection`; either one enables it.
    case integralRetrospectiveCorrection

    /// Glucose-based application factor, for automatic-bolus dosing: the share of the correction given
    /// now rises with current glucose, from 0.2 at the lower correction target + 10 mg/dL to 0.8 at
    /// 200 mg/dL, instead of a constant. It replaces `AlgorithmInput.automaticBolusApplicationFactor`
    /// and, through it, the automatic-bolus cap. Temp-basal dosing is unaffected.
    case glucoseBasedApplicationFactor
}

/// Loop's glucose-based application factor (`glucoseBasedApplicationFactor`).
enum GlucoseBasedApplicationFactor {
    static let minFactor = 0.2
    static let maxFactor = 0.8
    static let lowerTargetDelta = 10.0   // mg/dL above the lower correction target where the ramp starts
    static let rampTop = 200.0           // mg/dL where the factor reaches maxFactor

    /// `glucose` and `lowerTarget` in mg/dL.
    static func factor(glucose: Double, lowerTarget: Double) -> Double {
        let rampStart = lowerTarget + lowerTargetDelta
        let slope = (maxFactor - minFactor) / (rampTop - rampStart)
        return min(minFactor + max(glucose - rampStart, 0) * slope, maxFactor)
    }
}

/// The internal configuration the experiment expands to. Not public: the experiment is fixed.
struct ExperimentParameters: Equatable {
    var postLowRiseCut: PostLowRiseCut? = nil
    var volatilityBand: VolatilityBand? = nil
    var runwayReserve: RunwayReserve? = nil

    static let none = ExperimentParameters()

    var needsVolatility: Bool { volatilityBand != nil || runwayReserve != nil }

    /// `volatilityBaseline` is the person's median σ5 (mg/dL per 5 min); only the band uses it.
    /// Integral RC and the glucose-based application factor are switched where they act, not here.
    init(experiments: Set<AlgorithmExperiment>, volatilityBaseline: Double?) {
        if experiments.contains(.guardAndRunway) {
            postLowRiseCut = PostLowRiseCut()
            runwayReserve = RunwayReserve()
            // Without a baseline (a new user, under a day of glucose) the band runs at full depth: the
            // baseline only ever lowers it, for people whose glucose is volatile. Full depth is the safer
            // side, fewer lows for a little time in range.
            if let baseline = volatilityBaseline, baseline.isFinite, baseline > 0 {
                volatilityBand = VolatilityBand(gain: Swift.min(1.0, 6.7 / baseline))
            } else {
                volatilityBand = VolatilityBand(gain: 1.0)
            }
        }
    }

    init() {}

    struct PostLowRiseCut: Equatable {
        var riseScale = 0.3
        var window: TimeInterval = .hours(12)
        var lowThreshold = 70.0          // mg/dL
        var releaseGlucose = 180.0       // mg/dL
    }

    struct VolatilityBand: Equatable {
        var gain: Double
        var horizon: TimeInterval = .minutes(60)
        var taperEnd: TimeInterval = .minutes(120)
        var exponent = 0.71
        var carbGate = true
    }

    struct RunwayReserve: Equatable {
        var fraction = 0.7               // share of the reserve that is spent
        var bandWidth = 1.0              // σ5 multiples below the forecast for the plausible fall
        var exponent = 0.71              // band growth with horizon, as the volatility band
        var horizon: TimeInterval = .minutes(180)
        var maxAimShift = 60.0           // mg/dL
        var minGlucose = 150.0           // mg/dL
        var minEffectFraction = 0.05     // horizons where less of a dose has acted are skipped
        var carbGate = true
    }
}
