//
//  DoseType.swift
//  LoopAlgorithm
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation


/// A general set of ways insulin can be delivered by a pump
public enum InsulinDeliveryType: String, CaseIterable, Equatable {
    case bolus
    case basal

    init?(fixtureValue: String) {
        switch fixtureValue {
        case "TempBasal":
            self = .basal
        case "Bolus":
            self = .bolus
        default:
            return nil
        }
    }
}

extension InsulinDeliveryType: Codable {}
