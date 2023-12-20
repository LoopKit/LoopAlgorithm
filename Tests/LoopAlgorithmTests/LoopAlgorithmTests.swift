//
//  LoopAlgorithmTests.swift
//  LoopKitTests
//
//  Created by Pete Schwamb on 10/18/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import LoopAlgorithm

final class LoopAlgorithmTests: XCTestCase {

    func loadScenario(_ name: String) -> (input: LoopAlgorithmInput<FixtureCarbEntry>, recommendation: LoopAlgorithmDoseRecommendation) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var url = Bundle.module.url(forResource: name + "_input", withExtension: "json", subdirectory: "Fixtures")!
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
}
