//
//  GlucoseVolatility.swift
//  LoopAlgorithm
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Causal short-term glucose volatility, used by the `guardAndRunway` experiment.
public enum GlucoseVolatility {

    /// EWMA weight on the previous variance.
    public static let lambda = 0.875
    /// CGM noise level; the variance is floored at 2 × noise².
    public static let noise = 1.4

    /// σ5 now: the exponentially weighted RMS of the 5-minute glucose increment, in mg/dL per 5 min,
    /// over the last ~5 h of readings.
    public static func sigma5<GlucoseType: GlucoseValue>(_ glucoseHistory: [GlucoseType]) -> Double {
        let series = sigma5Series(fiveMinute(glucoseHistory).suffix(60))
        return series.last ?? (2.0 * noise * noise).squareRoot()
    }

    /// The person's volatility baseline for the `guardAndRunway` experiment's band: the median of σ5 over a glucose
    /// history. LoopEval used each person's own median; four weeks of history gave a stable value
    /// (about 9 % drift between successive four-week windows). Returns nil with less than a day of readings.
    public static func baseline<GlucoseType: GlucoseValue>(_ glucoseHistory: [GlucoseType]) -> Double? {
        let series = sigma5Series(fiveMinute(glucoseHistory))
        guard series.count >= 288 else { return nil }
        let sorted = series.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Thin to 5-minute spacing: keep a reading only when it is at least 4 minutes after the last one
    /// kept. With 5-minute CGM every reading is kept; with 1-minute CGM the estimator would otherwise
    /// see only 1-minute increments, which it ignores, and never leave its floor.
    static func fiveMinute<GlucoseType: GlucoseValue>(_ glucoseHistory: [GlucoseType]) -> [(date: Date, value: Double)] {
        let unit = LoopUnit.milligramsPerDeciliter
        var kept: [(date: Date, value: Double)] = []
        for sample in glucoseHistory {
            if let last = kept.last, sample.startDate.timeIntervalSince(last.date) < .minutes(4) { continue }
            kept.append((sample.startDate, sample.quantity.doubleValue(for: unit)))
        }
        return kept
    }

    /// σ5 after each reading. Readings 2–7 min apart contribute (scaled to 5 min); a gap of more than
    /// 7 min restarts the estimate, which reads as the floor until the next usable pair.
    static func sigma5Series<S: Sequence>(_ samples: S) -> [Double] where S.Element == (date: Date, value: Double) {
        let floorVariance = 2.0 * noise * noise
        var variance = Double.nan
        var previous: (date: Date, value: Double)? = nil
        var out: [Double] = []
        for sample in samples {
            if let previous {
                let minutes = sample.date.timeIntervalSince(previous.date) / 60.0
                if minutes > 2.0 && minutes <= 7.0 {
                    let d5 = (sample.value - previous.value) * (5.0 / minutes)
                    variance = variance.isNaN
                        ? Swift.max(d5 * d5, floorVariance)
                        : Swift.max(lambda * variance + (1 - lambda) * d5 * d5, floorVariance)
                } else if minutes > 7.0 {
                    variance = .nan
                }
            }
            previous = sample
            out.append(variance.isNaN ? floorVariance.squareRoot() : variance.squareRoot())
        }
        return out
    }
}
