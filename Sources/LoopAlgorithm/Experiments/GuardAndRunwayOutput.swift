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
    /// The most the band lowered any point of the forecast, mg/dL; 0 when it was off. A forecast with no
    /// points near 60 min, where the band is deepest, is lowered less.
    public var bandDepth: Double
    /// How far the target for automatic dosing was lowered, mg/dL. Manual recommendations keep the target.
    public var runwayShift: Double
    /// True while the post-low cut scales down the rising side of retrospective correction.
    public var postLowRiseCutActive: Bool

    let band: ExperimentParameters.VolatilityBand

    /// The band's depth multiplier, from the volatility baseline.
    public var bandGain: Double { band.gain }

    /// `glucose` lowered by the band as this run applied it; unchanged when the band was off.
    public func guarded(_ glucose: [PredictedGlucoseValue]) -> [PredictedGlucoseValue] {
        bandApplied ? LoopAlgorithm.volatilityBanded(glucose, band: band, volatility: volatility) : glucose
    }
}
