//
//  CarbEntry.swift
//
//  Created by Nathan Racklyeft on 1/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol CarbEntry: SampleValue {
    /// The carbohydrate amount in grams
    var grams: Double { get }
    var absorptionTime: TimeInterval? { get }
}

extension CarbEntry {
    var quantity: LoopQuantity {
        LoopQuantity(unit: .gram, doubleValue: grams)
    }
}

