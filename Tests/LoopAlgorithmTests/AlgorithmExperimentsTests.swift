//
//  AlgorithmExperimentsTests.swift
//  LoopAlgorithmTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import LoopAlgorithm

final class AlgorithmExperimentsTests: XCTestCase {

    private let unit = LoopUnit.milligramsPerDeciliter

    private func loadScenario(_ name: String) -> AlgorithmInputFixture {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = Bundle.module.url(forResource: name + "_scenario", withExtension: "json", subdirectory: "Fixtures")!
        return try! decoder.decode(AlgorithmInputFixture.self, from: try! Data(contentsOf: url))
    }

    private func glucoseSeries(_ values: [Double], endingAt end: Date, spacing: TimeInterval = .minutes(5)) -> [FixtureGlucoseSample] {
        values.enumerated().map { i, v in
            FixtureGlucoseSample(startDate: end.addingTimeInterval(-Double(values.count - 1 - i) * spacing), quantity: .glucose(v))
        }
    }

    private func assertSameOutput(_ a: AlgorithmOutput<FixtureCarbEntry>, _ b: AlgorithmOutput<FixtureCarbEntry>,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.recommendation, b.recommendation, file: file, line: line)
        XCTAssertEqual(a.predictedGlucose.map { $0.quantity.doubleValue(for: unit) },
                       b.predictedGlucose.map { $0.quantity.doubleValue(for: unit) }, file: file, line: line)
    }

    // MARK: - Default is standard LoopAlgorithm

    func testExistingFixturesDecodeWithoutExperiments() {
        XCTAssertTrue(loadScenario("suspend").experiments.isEmpty)
        XCTAssertTrue(loadScenario("carbs_with_isf_change").experiments.isEmpty)
    }

    func testGatedExperimentsAreInertWhenTheirGateIsClosed() {
        // Mock: glucose rising 100 -> 160, no low. With carbs on board the band and the runway reserve are
        // gated off, and there is no low for the post-low cut: the experiment must change nothing.
        let now = ISO8601DateFormatter().date(from: "2024-01-03T12:00:00+0000")!
        var input = AlgorithmInputFixture.mock(for: now)
        input.recommendationType = .automaticBolus
        input.carbEntries = [FixtureCarbEntry(absorptionTime: .hours(3), startDate: now.addingTimeInterval(.minutes(-30)), quantity: .carbs(30))]
        let standard = Algorithm.run(input: input)
        input.experiments = [.guardAndRunway]
        input.volatilityBaseline = 5
        let gated = Algorithm.run(input: input)
        assertSameOutput(standard, gated)
        XCTAssertNil(standard.guardAndRunway)
        let output = gated.guardAndRunway!
        XCTAssertFalse(output.bandApplied)
        XCTAssertEqual(output.bandDepth, 0)
        XCTAssertEqual(output.runwayShift, 0)
        XCTAssertFalse(output.postLowRiseCutActive)
        XCTAssertEqual(output.guarded(standard.predictedGlucose), standard.predictedGlucose)
    }

    func testWithoutABaselineTheBandIsFullDepth() {
        // No baseline and under a day of glucose (a new user): the band runs at full depth, and the
        // baseline only lowers it.
        let p = ExperimentParameters(experiments: [.guardAndRunway], volatilityBaseline: nil)
        XCTAssertEqual(p.volatilityBand?.gain, 1.0)
        XCTAssertEqual(p.volatilityBand, ExperimentParameters(experiments: [.guardAndRunway], volatilityBaseline: 5).volatilityBand)
        XCTAssertNotNil(p.postLowRiseCut)
        XCTAssertNotNil(p.runwayReserve)
        XCTAssertEqual(ExperimentParameters(experiments: [.guardAndRunway], volatilityBaseline: .nan).volatilityBand?.gain, 1.0)
        XCTAssertNil(ExperimentParameters(experiments: [], volatilityBaseline: nil).volatilityBand)
    }

    func testRunwayFillsTheGapsInASparseForecast() {
        // Loop drops forecast points once nothing changes: 0–55 min then a final point at 370. Filling the
        // gap must give the same reserve as the dense flat forecast.
        let now = Date()
        let dense = flatForecast(200, from: now)
        let sparse = Array(dense.prefix(12)) + [dense.last!]
        func reserve(_ p: [PredictedGlucoseValue], _ volatility: Double) -> Double {
            Algorithm.runwayAimShift(prediction: p, reserve: ExperimentParameters.RunwayReserve(), currentGlucose: 200,
                                         activeCarbs: 0, volatility: volatility, sensitivity: 50, basalRate: 1.0,
                                         targetMidpoint: 105, suspendThreshold: 70,
                                         insulinModel: ExponentialInsulinModelPreset.rapidActingAdult)
        }
        XCTAssertEqual(reserve(sparse, 6), reserve(dense, 6), accuracy: 1e-9)
        XCTAssertEqual(reserve(sparse, 20), 0)
    }

    func testParameters() {
        let p = ExperimentParameters(experiments: [.guardAndRunway], volatilityBaseline: 5)
        XCTAssertEqual(p.volatilityBand?.gain, 1.0)                                   // min(1, 6.7 / 5)
        XCTAssertEqual(ExperimentParameters(experiments: [.guardAndRunway], volatilityBaseline: 10).volatilityBand!.gain, 0.67, accuracy: 1e-12)
        XCTAssertEqual(p.postLowRiseCut, ExperimentParameters.PostLowRiseCut())
        XCTAssertEqual(p.runwayReserve, ExperimentParameters.RunwayReserve())
        XCTAssertEqual(p.runwayReserve?.fraction, 0.7)
        XCTAssertEqual(p.runwayReserve?.minGlucose, 150)
        XCTAssertEqual(ExperimentParameters(experiments: [], volatilityBaseline: 5), ExperimentParameters.none)
        // Integral RC and the glucose-based factor are switched where they act; they add no parameters here.
        XCTAssertEqual(ExperimentParameters(experiments: [.integralRetrospectiveCorrection, .glucoseBasedApplicationFactor],
                                            volatilityBaseline: 5), ExperimentParameters.none)
    }

    // MARK: - Retrospective correction gains

    func testStandardRCRiseScale() {
        let now = Date()
        let latest = SimpleGlucoseValue(startDate: now, quantity: .glucose(150))
        func total(_ discrepancy: Double, rise: Double) -> Double {
            let rc = StandardRetrospectiveCorrection(effectDuration: .minutes(60), riseScale: rise)
            let change = GlucoseChange(startDate: now.addingTimeInterval(.minutes(-30)), endDate: now, quantity: .glucose(discrepancy))
            _ = rc.computeEffect(startingAt: latest, retrospectiveGlucoseDiscrepanciesSummed: [change],
                                 recencyInterval: .minutes(15), retrospectiveCorrectionGroupingInterval: .minutes(30))
            return rc.totalGlucoseCorrectionEffect!.doubleValue(for: unit)
        }
        XCTAssertEqual(total(10, rise: 0.3), 3, accuracy: 1e-9)
        XCTAssertEqual(total(-10, rise: 0.3), -10, accuracy: 1e-9)    // the falling side is untouched
        XCTAssertEqual(total(10, rise: 1), 10, accuracy: 1e-9)
    }

    // MARK: - Post-low rise-cut gate

    func testPostLowRiseCutGate() {
        let now = Date()
        let cut = ExperimentParameters.PostLowRiseCut()
        XCTAssertTrue(cut.isActive(glucoseHistory: glucoseSeries([90, 65, 80, 120], endingAt: now)))
        XCTAssertFalse(cut.isActive(glucoseHistory: glucoseSeries([90, 65, 120, 190], endingAt: now)), "released above 180")
        XCTAssertFalse(cut.isActive(glucoseHistory: glucoseSeries([90, 100, 110, 120], endingAt: now)), "no low")
        let old = [FixtureGlucoseSample(startDate: now.addingTimeInterval(.hours(-13)), quantity: .glucose(60))]
            + glucoseSeries([100, 110, 120], endingAt: now)
        XCTAssertFalse(cut.isActive(glucoseHistory: old), "low outside the 12 h window")
    }

    func testPostLowRiseCutLowersTheForecastAfterALow() {
        // Rebound after a low, with insulin on board: the unexplained rise is cut, so the forecast is lower.
        let now = ISO8601DateFormatter().date(from: "2024-01-03T12:00:00+0000")!
        var input = AlgorithmInputFixture.mock(for: now)
        input.glucoseHistory = glucoseSeries([62, 66, 75, 90, 110, 130], endingAt: now.addingTimeInterval(.minutes(-1)))
        let standard = Algorithm.run(input: input)
        input.experiments = [.guardAndRunway]
        let cut = Algorithm.run(input: input)
        XCTAssertLessThan(cut.predictedGlucose.last!.quantity.doubleValue(for: unit),
                          standard.predictedGlucose.last!.quantity.doubleValue(for: unit))
        XCTAssertTrue(cut.guardAndRunway!.postLowRiseCutActive)
    }

    // MARK: - Volatility

    func testSigma5() {
        let now = Date()
        XCTAssertEqual(GlucoseVolatility.sigma5(glucoseSeries([120, 120, 120, 120], endingAt: now)), (2 * 1.4 * 1.4).squareRoot(), accuracy: 1e-9)
        // Constant 10 mg/dL steps: the EWMA of 100 is 100.
        XCTAssertEqual(GlucoseVolatility.sigma5(glucoseSeries([100, 110, 120, 130, 140], endingAt: now)), 10, accuracy: 1e-9)
        // A gap > 7 min restarts the estimate: only the steps after the gap count.
        let gapped = glucoseSeries([100, 140, 180], endingAt: now.addingTimeInterval(.minutes(-30)))
            + glucoseSeries([100, 102], endingAt: now)
        XCTAssertEqual(GlucoseVolatility.sigma5(gapped), 2.0, accuracy: 1e-9)   // one 2 mg/dL step; 4 > floor 3.92
    }

    func testSigma5OnOneMinuteCGM() {
        // The same 10 mg/dL per 5 min trend sampled every minute must read like 5-minute data, not the floor.
        let now = Date()
        let oneMinute = (0...40).map { FixtureGlucoseSample(startDate: now.addingTimeInterval(.minutes(Double($0 - 40))), quantity: .glucose(100 + 2 * Double($0))) }
        XCTAssertEqual(GlucoseVolatility.sigma5(oneMinute), 10, accuracy: 1e-9)
    }

    func testBaselineIsTheMedianOfSigma5() {
        let now = Date()
        XCTAssertNil(GlucoseVolatility.baseline(glucoseSeries(Array(repeating: 120, count: 100), endingAt: now)), "under a day")
        // A calm stretch then a longer +/-10 stretch: the median is volatile, above the floor and at most 10.
        let flat = Array(repeating: 120.0, count: 100)
        let zig = (0..<200).map { $0 % 2 == 0 ? 120.0 : 130.0 }
        let b = GlucoseVolatility.baseline(glucoseSeries(flat + zig, endingAt: now))!
        XCTAssertGreaterThan(b, (2 * 1.4 * 1.4).squareRoot())
        XCTAssertLessThanOrEqual(b, 10)
    }

    func testVolatilityBandShape() {
        let now = Date()
        let glucose = (0...48).map { PredictedGlucoseValue(startDate: now.addingTimeInterval(.minutes(5 * Double($0))), quantity: .glucose(120)) }
        let band = ExperimentParameters.VolatilityBand(gain: 1.0)
        let banded = Algorithm.volatilityBanded(glucose, band: band, volatility: 4.0)
        let offset: (Int) -> Double = { banded[$0].quantity.doubleValue(for: self.unit) - 120 }
        XCTAssertEqual(offset(0), 0, accuracy: 1e-9)
        XCTAssertEqual(offset(12), -4.0 * pow(12.0, 0.71), accuracy: 1e-9)          // 60 min: full depth
        XCTAssertEqual(offset(18), -4.0 * pow(12.0, 0.71) / 2, accuracy: 1e-9)      // 90 min: half way down the taper
        XCTAssertEqual(offset(24), 0, accuracy: 1e-9)                               // 120 min: gone
        XCTAssertEqual(offset(48), 0, accuracy: 1e-9)                               // eventual untouched
    }

    // MARK: - Runway reserve

    private func flatForecast(_ value: Double, from now: Date) -> [PredictedGlucoseValue] {
        (0...72).map { PredictedGlucoseValue(startDate: now.addingTimeInterval(.minutes(5 * Double($0))), quantity: .glucose(value)) }
    }

    private func shift(_ forecast: Double, current: Double? = nil, carbs: Double = 0, volatility: Double) -> Double {
        let now = Date()
        return Algorithm.runwayAimShift(
            prediction: flatForecast(forecast, from: now), reserve: ExperimentParameters.RunwayReserve(),
            currentGlucose: current ?? forecast, activeCarbs: carbs, volatility: volatility,
            sensitivity: 50, basalRate: 1.0, targetMidpoint: 105, suspendThreshold: 70,
            insulinModel: ExponentialInsulinModelPreset.rapidActingAdult)
    }

    func testRunwayGates() {
        XCTAssertEqual(shift(140, volatility: 2), 0, "below 150")
        XCTAssertEqual(shift(200, carbs: 20, volatility: 2), 0, "20 g of carbs on board")
        XCTAssertEqual(shift(200, carbs: 10, volatility: 2), 0.5 * shift(200, volatility: 2), accuracy: 1e-9, "fades with carbs")
        XCTAssertGreaterThan(shift(200, volatility: 2), 0)
        let now = Date()
        let short = Array(flatForecast(200, from: now).prefix(30))       // 145 min, short of 180
        XCTAssertEqual(Algorithm.runwayAimShift(
            prediction: short, reserve: ExperimentParameters.RunwayReserve(), currentGlucose: 200, activeCarbs: 0,
            volatility: 2, sensitivity: 50, basalRate: 1.0, targetMidpoint: 105, suspendThreshold: 70,
            insulinModel: ExponentialInsulinModelPreset.rapidActingAdult), 0, "forecast shorter than the horizon")
    }

    func testRunwayShrinksWithVolatilityAndIsCapped() {
        let calm = shift(200, volatility: 2), mid = shift(200, volatility: 6), volatile = shift(200, volatility: 30)
        XCTAssertGreaterThan(calm, mid)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertEqual(volatile, 0, "a plausible fall reaches the suspend threshold: no room")
        XCTAssertEqual(shift(400, volatility: 2), 60, "capped at 60 mg/dL")
        XCTAssertLessThanOrEqual(calm, 60)
    }

    func testRunwayAddsAutomaticInsulinOnACalmHighButNotToTheManualRecommendation() {
        let now = ISO8601DateFormatter().date(from: "2024-01-03T12:00:00+0000")!
        var input = AlgorithmInputFixture.mock(for: now)
        input.glucoseHistory = glucoseSeries(Array(repeating: 220, count: 12), endingAt: now.addingTimeInterval(.minutes(-1)))
        // No baseline: the band runs at full depth, and only the guard sees it, so a rise in automatic dosing
        // is the runway's. No low: no post-low cut.
        for type in [DoseRecommendationType.tempBasal, .automaticBolus] {
            input.recommendationType = type
            input.experiments = []
            let standard = Algorithm.run(input: input)
            input.experiments = [.guardAndRunway]
            let runway = Algorithm.run(input: input)
            XCTAssertEqual(runway.predictedGlucose, standard.predictedGlucose, "the forecast shown is not banded")
            let output = runway.guardAndRunway!
            let banded = output.guarded(runway.predictedGlucose).map { $0.quantity.doubleValue(for: unit) }
            let plain = standard.predictedGlucose.map { $0.quantity.doubleValue(for: unit) }
            XCTAssertEqual(banded.count, plain.count)
            XCTAssertEqual(banded.last, plain.last, "eventual glucose is unchanged")
            XCTAssertTrue(zip(banded, plain).allSatisfy { $0 <= $1 }, "the band only lowers the forecast")
            XCTAssertTrue(output.bandApplied)
            XCTAssertGreaterThan(output.runwayShift, 0)
            XCTAssertFalse(output.postLowRiseCutActive)
            let deepest = zip(plain, banded).map { $0 - $1 }.max()!
            XCTAssertEqual(output.bandDepth, deepest, accuracy: 1e-9)
            if type == .tempBasal {
                XCTAssertGreaterThan(runway.recommendation!.automatic!.basalAdjustment.unitsPerHour,
                                     standard.recommendation!.automatic!.basalAdjustment.unitsPerHour)
            } else {
                XCTAssertGreaterThan(runway.recommendation!.automatic!.bolusUnits!, standard.recommendation!.automatic!.bolusUnits!)
            }
        }
        // The runway does not add to the manual recommendation; the band can only lower it.
        input.recommendationType = .manualBolus
        input.experiments = []
        let standard = Algorithm.run(input: input)
        input.experiments = [.guardAndRunway]
        let manual = Algorithm.run(input: input)
        XCTAssertLessThanOrEqual(manual.recommendation?.manual?.amount ?? 0, standard.recommendation?.manual?.amount ?? 0)
    }

    func testGuardOnlyBand() {
        let now = Date()
        func g(_ v: Double) -> GlucoseValue { SimpleGlucoseValue(startDate: now, quantity: .glucose(v)) }
        func d(_ c: InsulinCorrection) -> String {
            let v = { (x: GlucoseValue) in Int(x.quantity.doubleValue(for: self.unit)) }
            switch c {
            case .aboveRange(min: let m, correcting: let c, minTarget: _, units: let u): return "above \(v(m)) \(v(c)) \(u)"
            case .entirelyBelowRange(min: let m, minTarget: _, units: let u): return "below \(v(m)) \(u)"
            case .suspend(min: let m): return "suspend \(v(m))"
            case .inRange: return "in range"
            }
        }
        let point = InsulinCorrection.aboveRange(min: g(120), correcting: g(200), minTarget: .glucose(100), units: 2)
        // A banded point below the suspend threshold suspends.
        XCTAssertEqual(d(Algorithm.guarded(point, by: .suspend(min: g(65)))), "suspend 65")
        // Otherwise the banded minimum is the one the guard checks; the units stay the forecast's.
        XCTAssertEqual(d(Algorithm.guarded(point, by: .aboveRange(min: g(90), correcting: g(170), minTarget: .glucose(100), units: 1))),
                       "above 90 200 2.0")
        XCTAssertEqual(d(Algorithm.guarded(point, by: .entirelyBelowRange(min: g(85), minTarget: .glucose(100), units: -1))),
                       "above 85 200 2.0")
        // A forecast that needs no correction is left as it is.
        XCTAssertEqual(d(Algorithm.guarded(.inRange, by: .entirelyBelowRange(min: g(85), minTarget: .glucose(100), units: -1))), "in range")
    }

    // MARK: - Slow retrospective correction

    private func counteraction(_ perFiveMinutes: Double, hours: Double, endingAt end: Date) -> [GlucoseEffectVelocity] {
        let n = Int(hours * 12)
        return (0..<n).map { i in
            let s = end.addingTimeInterval(-Double(n - i) * .minutes(5))
            return GlucoseEffectVelocity(startDate: s, endDate: s.addingTimeInterval(.minutes(5)),
                                         quantity: LoopQuantity(unit: GlucoseEffectVelocity.perSecondUnit, doubleValue: perFiveMinutes / 300))
        }
    }

    func testSlowRCLevelIsTheWindowedMeanResidual() {
        let now = Date(), p = ExperimentParameters.SlowRetrospectiveCorrection()
        // A constant 2 mg/dL per 5 min for 100 h, no carbs: only the last 72 h count, from zero at their start.
        let level = Algorithm.slowRetrospectiveCorrectionLevel(
            counteraction: counteraction(2, hours: 100, endingAt: now), carbEffects: [], now: now, parameters: p)
        XCTAssertEqual(level, 2 * (1 - exp(-3.0)), accuracy: 0.01)
        // Carb effect is subtracted: a carb curve rising 2 mg/dL per 5 min explains all of it.
        let steps = 100 * 12
        let carbs: [GlucoseEffect] = (0...steps).map { (i: Int) -> GlucoseEffect in
            let date = now.addingTimeInterval(-Double(steps - i) * 300)
            return GlucoseEffect(startDate: date, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 2 * Double(i)))
        }
        let explained = Algorithm.slowRetrospectiveCorrectionLevel(
            counteraction: counteraction(2, hours: 100, endingAt: now), carbEffects: carbs, now: now, parameters: p)
        XCTAssertEqual(explained, 0, accuracy: 1e-9)
    }

    func testSlowRCMultiplierClamps() {
        let p = ExperimentParameters.SlowRetrospectiveCorrection()
        XCTAssertEqual(Algorithm.slowRetrospectiveCorrectionMultiplier(level: 0, parameters: p), 1)
        XCTAssertEqual(Algorithm.slowRetrospectiveCorrectionMultiplier(level: 2, parameters: p), 0.9, accuracy: 1e-12)
        XCTAssertEqual(Algorithm.slowRetrospectiveCorrectionMultiplier(level: 20, parameters: p), 0.7)
        XCTAssertEqual(Algorithm.slowRetrospectiveCorrectionMultiplier(level: -20, parameters: p), 1.3)
    }

    func testSlowRCDosesMoreWhenGlucoseKeepsRisingUnexplained() {
        let now = ISO8601DateFormatter().date(from: "2024-01-03T12:00:00+0000")!
        var input = AlgorithmInputFixture.mock(for: now)
        input.recommendationType = .automaticBolus
        // Steady unexplained rise over 72 h, no carbs: the model keeps under-predicting.
        let values = (0..<(72 * 12)).map { 100 + 0.15 * Double($0) }
        input.glucoseHistory = glucoseSeries(values, endingAt: now.addingTimeInterval(.minutes(-1)))
        input.doses = []
        input.carbEntries = []
        input.sensitivityMgdlPerUnit = [AbsoluteScheduleValue(startDate: now.addingTimeInterval(.hours(-96)), endDate: now.addingTimeInterval(.hours(12)), value: 50)]
        input.basal = [AbsoluteScheduleValue(startDate: now.addingTimeInterval(.hours(-96)), endDate: now.addingTimeInterval(.hours(12)), value: 1.0)]
        input.carbRatio = [AbsoluteScheduleValue(startDate: now.addingTimeInterval(.hours(-96)), endDate: now.addingTimeInterval(.hours(12)), value: 10)]
        let standard = Algorithm.run(input: input)
        input.experiments = [.slowRetrospectiveCorrection]
        let slow = Algorithm.run(input: input)
        XCTAssertNil(standard.slowRetrospectiveCorrection)
        let output = slow.slowRetrospectiveCorrection!
        XCTAssertGreaterThan(output.level, 0)
        XCTAssertLessThan(output.multiplier, 1)
        XCTAssertGreaterThan(slow.recommendation!.automatic!.bolusUnits!, standard.recommendation!.automatic!.bolusUnits!)
    }

    func testTargetLoweredFloors() {
        let now = Date()
        let target: QuantityRangeTimeline = [AbsoluteScheduleValue(startDate: now, endDate: now.addingTimeInterval(.hours(1)),
                                                                  value: ClosedRange(uncheckedBounds: (lower: .glucose(100), upper: .glucose(110))))]
        let lowered = Algorithm.targetLowered(target, by: 25).first!.value
        XCTAssertEqual(lowered.lowerBound.doubleValue(for: unit), 75)
        XCTAssertEqual(lowered.upperBound.doubleValue(for: unit), 85)
        let floored = Algorithm.targetLowered(target, by: 60).first!.value
        XCTAssertEqual(floored.lowerBound.doubleValue(for: unit), 70)
        XCTAssertEqual(floored.upperBound.doubleValue(for: unit), 80)
    }

    // MARK: - Codable

    func testFixtureRoundTripCarriesTheExperiment() throws {
        var input = loadScenario("suspend")
        input.experiments = [.guardAndRunway]
        input.volatilityBaseline = 4.2
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(AlgorithmInputFixture.self, from: encoder.encode(input))
        XCTAssertEqual(back.experiments, [.guardAndRunway])
        XCTAssertEqual(back.volatilityBaseline, 4.2)
        XCTAssertEqual(ExperimentOption.allCases, [.guardAndRunway, .integralRetrospectiveCorrection, .glucoseBasedApplicationFactor,
                                                   .slowRetrospectiveCorrection])
    }

    func testFixtureRoundTripCarriesACombination() throws {
        var input = loadScenario("suspend")
        input.experiments = [.glucoseBasedApplicationFactor, .guardAndRunway, .integralRetrospectiveCorrection]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .sortedKeys
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(input)
        XCTAssertEqual(try decoder.decode(AlgorithmInputFixture.self, from: data).experiments, input.experiments)
        XCTAssertTrue(String(decoding: data, as: UTF8.self)
            .contains(#""experiments":["glucoseBasedApplicationFactor","guardAndRunway","integralRetrospectiveCorrection"]"#))
    }

    // MARK: - Integral retrospective correction

    func testIntegralRCExperimentIsTheInputFlag() {
        for name in ["suspend", "carbs_with_isf_change"] {
            var flag = loadScenario(name)
            flag.useIntegralRetrospectiveCorrection = true
            var experiment = loadScenario(name)
            experiment.experiments = [.integralRetrospectiveCorrection]
            assertSameOutput(Algorithm.run(input: flag), Algorithm.run(input: experiment))
            flag.experiments = [.integralRetrospectiveCorrection]   // both: still integral RC, once
            assertSameOutput(Algorithm.run(input: flag), Algorithm.run(input: experiment))
        }
    }

    // MARK: - Glucose-based application factor

    func testGlucoseBasedApplicationFactorRamp() {
        // Lower target 100: the ramp runs 0.2 at 110 to 0.8 at 200.
        XCTAssertEqual(GlucoseBasedApplicationFactor.factor(glucose: 90, lowerTarget: 100), 0.2, accuracy: 1e-12)
        XCTAssertEqual(GlucoseBasedApplicationFactor.factor(glucose: 110, lowerTarget: 100), 0.2, accuracy: 1e-12)
        XCTAssertEqual(GlucoseBasedApplicationFactor.factor(glucose: 155, lowerTarget: 100), 0.5, accuracy: 1e-12)
        XCTAssertEqual(GlucoseBasedApplicationFactor.factor(glucose: 200, lowerTarget: 100), 0.8, accuracy: 1e-12)
        XCTAssertEqual(GlucoseBasedApplicationFactor.factor(glucose: 260, lowerTarget: 100), 0.8, accuracy: 1e-12)
        // Lower target 90: 0.2 at 100, 0.5 at 150.
        XCTAssertEqual(GlucoseBasedApplicationFactor.factor(glucose: 150, lowerTarget: 90), 0.5, accuracy: 1e-12)
    }

    func testGlucoseBasedApplicationFactorReplacesTheConstantForAutomaticBolusOnly() {
        let now = ISO8601DateFormatter().date(from: "2024-01-03T12:00:00+0000")!
        var input = AlgorithmInputFixture.mock(for: now)
        input.glucoseHistory = glucoseSeries(Array(repeating: 155, count: 12), endingAt: now.addingTimeInterval(.minutes(-1)))
        // Mock lower target 100, glucose 155: the factor is 0.5, against the default 0.4.
        input.recommendationType = .automaticBolus
        var constant = input
        constant.automaticBolusApplicationFactor = 0.5
        input.automaticBolusApplicationFactor = 0.4
        input.experiments = [.glucoseBasedApplicationFactor]
        let gbaf = Algorithm.run(input: input)
        assertSameOutput(gbaf, Algorithm.run(input: constant))
        input.experiments = []
        XCTAssertGreaterThan(gbaf.recommendation!.automatic!.bolusUnits!, Algorithm.run(input: input).recommendation!.automatic!.bolusUnits!)
        for type in [DoseRecommendationType.tempBasal, .manualBolus] {
            input.recommendationType = type
            input.experiments = []
            let standard = Algorithm.run(input: input)
            input.experiments = [.glucoseBasedApplicationFactor]
            assertSameOutput(standard, Algorithm.run(input: input))
        }
    }
}
