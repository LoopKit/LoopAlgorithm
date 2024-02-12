//
//  LoopAlgorithmTests.swift
//  LoopAlgorithmTests
//
//  Created by Pete Schwamb on 10/18/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import LoopAlgorithm

final class LoopAlgorithmTests: XCTestCase {

    func loadScenario(_ name: String) -> (input: LoopAlgorithmInput<FixtureCarbEntry, FixtureGlucoseSample, FixtureInsulinDose>, recommendation: LoopAlgorithmDoseRecommendation) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var url = Bundle.module.url(forResource: name + "_scenario", withExtension: "json", subdirectory: "Fixtures")!
        let input = try! decoder.decode(LoopAlgorithmInput.self, from: try! Data(contentsOf: url))

        url = Bundle.module.url(forResource: name + "_recommendation", withExtension: "json", subdirectory: "Fixtures")!
        let recommendation = try! decoder.decode(LoopAlgorithmDoseRecommendation.self, from: try! Data(contentsOf: url))

        return (input: input, recommendation: recommendation)
    }

    func testSuspend() throws {

        let (input, recommendation) = loadScenario("suspend")

        let output = LoopAlgorithm.run(input: input)

        XCTAssertEqual(output.recommendation, recommendation)
    }

    func testCarbsWithSensitivityChange() throws {

        // This test computes a dose with a future carb entry
        // Between the time of dose and the startTime of the carb
        // There is a significant ISF change (from 35 mg/dL/U to 60 mg/dL/U)

        let (input, recommendation) = loadScenario("carbs_with_isf_change")

        let output = LoopAlgorithm.run(input: input)

        XCTAssertEqual(output.recommendation, recommendation)
    }

    func testAlgorithmShouldBeDateIndependent() throws {
        let now = Date()
        var a = LoopAlgorithmInputFixture.mock(for: now)
        var b = LoopAlgorithmInputFixture.mock(for: now.addingTimeInterval(.minutes(-2.5)))

        a.carbEntries.append(
            FixtureCarbEntry(
                startDate: a.predictionStart.addingTimeInterval(-.minutes(30)),
                quantity: .carbs(value: 10)
            )
        )

        b.carbEntries.append(
            FixtureCarbEntry(
                startDate: b.predictionStart.addingTimeInterval(-.minutes(30)),
                quantity: .carbs(value: 10)
            )
        )


        let outputA = LoopAlgorithm.run(input: a)
        let outputB = LoopAlgorithm.run(input: b)

        XCTAssertEqual(outputA.activeCarbs, outputB.activeCarbs)
        XCTAssertEqual(outputA.activeInsulin, outputB.activeInsulin)

        XCTAssertEqual(outputA.effects.carbs.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 190.0)
        XCTAssertEqual(outputB.effects.carbs.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 190.0)

        XCTAssertEqual(outputA.effects.insulin.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 0.0)
        XCTAssertEqual(outputB.effects.insulin.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 0.0)

        XCTAssertEqual(outputA.effects.momentum.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 0.0)
        XCTAssertEqual(outputB.effects.momentum.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 0.0)

        // TODO:
//        XCTAssertEqual(outputA.effects.retrospectiveCorrection.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 0)
//        XCTAssertEqual(outputB.effects.retrospectiveCorrection.last?.quantity.doubleValue(for: .milligramsPerDeciliter), 0)
//
//        XCTAssertEqual(outputA.predictedGlucose.last!.quantity.doubleValue(for: .milligramsPerDeciliter), 283.7, accuracy: 0.01)
//        XCTAssertEqual(outputB.predictedGlucose.last!.quantity.doubleValue(for: .milligramsPerDeciliter), 283.7, accuracy: 0.01)
    }


    func testObservedProgressForCarbStatus() throws {
        let date = ISO8601DateFormatter().date(from: "2024-01-03T12:00:00+0000")!
        var input = LoopAlgorithmInputFixture.mock(for: date)

        let now = input.predictionStart

        // Add carbs (20g should be 2U at 10g/U)
        input.carbEntries.append(
            FixtureCarbEntry(
                startDate: now.addingTimeInterval(-.minutes(30)),
                quantity: .carbs(value: 20)
            )
        )

        // Rising BG from carb absorption
        input.glucoseHistory = [
            FixtureGlucoseSample(startDate: now.addingTimeInterval(.minutes(-18)), quantity: .glucose(value: 105)),
            FixtureGlucoseSample(startDate: now.addingTimeInterval(.minutes(-13)), quantity: .glucose(value: 115)),
            FixtureGlucoseSample(startDate: now.addingTimeInterval(.minutes(-8)), quantity: .glucose(value: 120)),
            FixtureGlucoseSample(startDate: now.addingTimeInterval(.minutes(-3)), quantity: .glucose(value: 145)),
        ]

        let output = LoopAlgorithm.run(input: input)

        let carbStatus = output.effects.carbStatus.first!
        XCTAssertEqual(carbStatus.absorption!.observedProgress.doubleValue(for: .percent()), 0.11, accuracy: 0.01)

        XCTAssert(carbStatus.absorption!.isActive)

        let basalAdjustment = output.recommendation!.automatic!.basalAdjustment

        XCTAssertEqual(basalAdjustment!.unitsPerHour, 5.06, accuracy: 0.01)
    }

}
