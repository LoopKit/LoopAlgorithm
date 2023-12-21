//
//  BasalRelativeDose.swift
//  
//
//  Created by Pete Schwamb on 12/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

public enum BasalRelativeDoseType {
    case bolus
    case tempBasal(scheduledRate: Double)
}

public struct BasalRelativeDose: TimelineValue {
    public var type: BasalRelativeDoseType
    public var startDate: Date
    public var endDate: Date
    public var volume: Double
    public var insulinType: InsulinType?

    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
}

extension BasalRelativeDose {
    /// The number of units delivered, net the basal rate scheduled during that time, which can be used to compute insulin on-board and glucose effects
    public var netBasalUnits: Double {

        if case .tempBasal(let scheduledRate) = type {
            guard duration.hours > 0 else {
                return 0
            }
            let scheduledUnits = scheduledRate * duration.hours
            return volume - scheduledUnits
        } else {
            return volume
        }
    }
}

extension BasalRelativeDose {
    static func fromBolus(dose: InsulinDose) -> BasalRelativeDose {
        precondition(dose.type == .bolus, "Dose passed to fromBolus() must be a bolus.")
        
        return BasalRelativeDose(
            type: .bolus,
            startDate: dose.startDate,
            endDate: dose.endDate,
            volume: dose.volume,
            insulinType: dose.insulinType
        )
    }
}
