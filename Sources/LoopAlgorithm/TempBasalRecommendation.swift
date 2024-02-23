//
//  TempBasalRecommendation.swift
//  LoopAlgorithm
//
//  Created by Darin Krauss on 5/21/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

public struct TempBasalRecommendation: Equatable {
    public var unitsPerHour: Double
    public let duration: TimeInterval

    public init(unitsPerHour: Double, duration: TimeInterval) {
        self.unitsPerHour = unitsPerHour
        self.duration = duration
    }
}

extension TempBasalRecommendation: Codable {}
