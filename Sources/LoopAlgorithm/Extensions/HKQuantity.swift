//
//  HKQuantity.swift
//  LoopAlgorithm
//
//  Created by Nathan Racklyeft on 3/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


extension HKQuantity: @retroactive Comparable { }

public func <(lhs: HKQuantity, rhs: HKQuantity) -> Bool {
    return lhs.compare(rhs) == .orderedAscending
}
