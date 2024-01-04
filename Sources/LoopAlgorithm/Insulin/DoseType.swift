//
//  DoseType.swift
//  LoopKit
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


/// A general set of ways insulin can be delivered by a pump
public enum InsulinDeliveryType: String, CaseIterable, Equatable {
    case bolus
    case basal
}

extension InsulinDeliveryType: Codable {}
