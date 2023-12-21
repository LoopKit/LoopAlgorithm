//
//  InsulinDose.swift
//
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


public protocol InsulinDose: TimelineValue {
    var type: InsulinDoseType { get }
    var startDate: Date { get }
    var endDate: Date { get }
    var volume: Double { get }
    var insulinType: InsulinType? { get }
}

extension InsulinDose {
    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }

    var unitsPerHour: Double {
        return volume / duration.hours
    }

}
