//
//  AbsoluteScheduleValue.swift
//  
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

public struct AbsoluteScheduleValue<T>: TimelineValue {
    public let startDate: Date
    public let endDate: Date
    public let value: T

    public init(startDate: Date, endDate: Date, value: T) {
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
    }
}

extension AbsoluteScheduleValue: Equatable where T: Equatable {}

extension AbsoluteScheduleValue: Codable where T: Codable {}
