//
//  File.swift
//  
//
//  Created by Pete Schwamb on 12/20/23.
//

import Foundation
@testable import LoopAlgorithm

extension LoopAlgorithmInput {
    static func mock(for date: Date) -> LoopAlgorithmInput {

        return LoopAlgorithmInput(
            predictionStart: date,
            glucoseHistory: [],
            doses: [],
            carbEntries: [],
            basal: [],
            sensitivity: [],
            carbRatio: [],
            target: [],
            suspendThreshold: .init(unit: .milligramsPerDeciliter, doubleValue: 65),
            maxBolus: 6,
            maxBasalRate: 8,
            useIntegralRetrospectiveCorrection: false,
            includePositiveVelocityAndRC: false,
            carbAbsorptionModel: .piecewiseLinear,
            recommendationInsulinType: .novolog,
            recommendationType: .manualBolus
        )
    }
}
