//
//  DoubleRange.swift
//

import Foundation
import HealthKit

public struct DoubleRange {
    public let minValue: Double
    public let maxValue: Double

    public init(minValue: Double, maxValue: Double) {
        self.minValue = minValue
        self.maxValue = maxValue
    }

    public var isZero: Bool {
        return abs(minValue) < .ulpOfOne && abs(maxValue) < .ulpOfOne
    }
}


extension DoubleRange: RawRepresentable {
    public typealias RawValue = [Double]

    public init?(rawValue: RawValue) {
        guard rawValue.count == 2 else {
            return nil
        }

        minValue = rawValue[0]
        maxValue = rawValue[1]
    }

    public var rawValue: RawValue {
        return [minValue, maxValue]
    }
}

extension DoubleRange: Equatable {
    public static func ==(lhs: DoubleRange, rhs: DoubleRange) -> Bool {
        return abs(lhs.minValue - rhs.minValue) < .ulpOfOne &&
               abs(lhs.maxValue - rhs.maxValue) < .ulpOfOne
    }
}

extension DoubleRange: Hashable {}

extension DoubleRange: Codable {}

extension DoubleRange {
    public func quantityRange(for unit: HKUnit) -> ClosedRange<HKQuantity> {
        let lowerBound = HKQuantity(unit: unit, doubleValue: minValue)
        let upperBound = HKQuantity(unit: unit, doubleValue: maxValue)
        return lowerBound...upperBound
    }
}
