//
//  GuardAndRunwayOutput.swift
//  LoopAlgorithm
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// What Guard + Runway did on one run, for display.
public struct GuardAndRunwayOutput: Equatable {
    /// Recent glucose volatility (σ5), mg/dL.
    public var volatility: Double
    /// False when active carbs kept the volatility band off.
    public var bandApplied: Bool
    /// How far the target for automatic dosing was lowered, mg/dL. Manual recommendations keep the target.
    public var runwayShift: Double
    /// True while the post-low cut scales down the rising side of retrospective correction.
    public var postLowRiseCutActive: Bool

    let band: ExperimentParameters.VolatilityBand

    /// The band's depth multiplier, from the volatility baseline.
    public var bandGain: Double { band.gain }

    /// How far the band lowers the forecast at its deepest point (60 min), mg/dL; 0 when it was off.
    public var bandDepth: Double {
        bandApplied ? band.gain * volatility * pow(band.horizon.minutes / 5.0, band.exponent) : 0
    }

    /// `glucose` lowered by the band as this run applied it; unchanged when the band was off.
    public func guarded(_ glucose: [PredictedGlucoseValue]) -> [PredictedGlucoseValue] {
        bandApplied ? LoopAlgorithm.volatilityBanded(glucose, band: band, volatility: volatility) : glucose
    }
}
