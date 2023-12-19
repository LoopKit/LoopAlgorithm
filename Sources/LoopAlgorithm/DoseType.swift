//
//  DoseType.swift
//  LoopKit
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


/// A general set of ways insulin can be delivered by a pump
public enum DoseType: String, CaseIterable {
    case basal
    case bolus
    case resume
    case suspend
    case tempBasal
}

extension DoseType: Codable {}
