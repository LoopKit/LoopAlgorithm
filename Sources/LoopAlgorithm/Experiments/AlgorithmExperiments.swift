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
public enum ExperimentOption: String, Codable, CaseIterable, Sendable {

    /// LoopEval guard + runway (C20 + C29 + C40). A lows guard, plus a little more correction when there
    /// is room for it:
    /// - **Post-low rise-cut** (C20). For 12 h after a reading below 70 mg/dL, and while glucose is
    ///   below 180, the rising side of retrospective correction is weighted 0.3×: the rebound after a
    ///   low (rescue carbs, counter-regulation) is not treated as a lasting need for insulin.
    /// - **Volatility band** (C29). While no carbs are on board, the low guard sees the first two hours of
    ///   the forecast lowered in proportion to recent glucose volatility: a lowered point below the suspend
    ///   threshold suspends, and the lowered minimum is the one the guard checks. The correction is sized,
    ///   and the forecast shown, from the forecast itself, so the band never lowers a correction it does not
    ///   stop. Its depth is keyed to the person's median volatility (`AlgorithmInput.volatilityBaseline`),
    ///   and is full depth until a baseline exists.
    /// - **Runway reserve** (C40). While glucose is 150 or above and carbs on board are under 20 g: how much
    ///   extra insulin could still be taken back by suspending scheduled basal, if glucose then fell
    ///   along the forecast less one σ of recent volatility, without reaching the suspend threshold
    ///   within 3 h? 70 % of that amount (at most 60 mg/dL's worth) is added to the automatic
    ///   correction, scaled down linearly from no carbs on board to none at 20 g. Calm glucose leaves room;
    ///   volatile glucose leaves little or none. It is applied as
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

    /// Slow retrospective correction: a day-scale estimate of how much more or less insulin the person needs
    /// than their settings say. Its level is the exponentially weighted mean (time constant 24 h) of the
    /// glucose change the forecast model did not explain (insulin counteraction less carb effect, per
    /// 5 minutes, at the scheduled ISF) over the glucose history passed in, up to 72 h, from zero at its start.
    /// ISF for the whole run is multiplied by `1 − 0.05 × level`, within 0.7–1.3: glucose that keeps rising
    /// more than the model expects lowers ISF, and glucose that keeps falling raises it.
    ///
    /// It is computed from the inputs on every run, with no stored state, so it needs a long history: 72 h of
    /// glucose, carb entries from 72 h plus the longest absorption time, and doses from 72 h plus the insulin
    /// activity duration. The carb ratio and ISF timelines must start at or before the oldest carb entry
    /// (otherwise `run` fails with `AlgorithmError.carbRatioOrSensitivityStartsAfterCarbEntry`). A meal whose entry is dropped while its absorption is still inside the
    /// glucose history reads as unexplained rise and pushes the level up: pass carbs for the whole history.
    /// With 12 h of history the level reaches only about 40 % of its working value.
    case slowRetrospectiveCorrection
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
    var slowRetrospectiveCorrection: SlowRetrospectiveCorrection? = nil

    static let none = ExperimentParameters()

    var needsVolatility: Bool { volatilityBand != nil || runwayReserve != nil }

    /// `volatilityBaseline` is the person's median σ5 (mg/dL per 5 min); only the band uses it.
    /// Integral RC and the glucose-based application factor are switched where they act, not here.
    init(experiments: Set<ExperimentOption>, volatilityBaseline: Double?) {
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
        if experiments.contains(.slowRetrospectiveCorrection) {
            slowRetrospectiveCorrection = SlowRetrospectiveCorrection()
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
        var carbFade = 20.0              // g of carbs on board over which the reserve fades out (0: any carbs close it)
    }

    struct SlowRetrospectiveCorrection: Equatable {
        var timeConstant: TimeInterval = .hours(24)
        var gain = 0.05                  // ISF multiplier change per mg/dL per 5 min of level
        var minMultiplier = 0.7
        var maxMultiplier = 1.3
        var window: TimeInterval = .hours(72)
    }
}
