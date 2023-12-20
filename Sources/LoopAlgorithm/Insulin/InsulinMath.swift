//
//  InsulinMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit

public struct InsulinMath {
    public static var defaultInsulinActivityDuration: TimeInterval = TimeInterval(hours: 6) + TimeInterval(minutes: 10)
    public static var longestInsulinActivityDuration: TimeInterval = TimeInterval(hours: 6) + TimeInterval(minutes: 10)
}

extension DoseEntry {
    private func continuousDeliveryInsulinOnBoard(at date: Date, model: InsulinModel, delta: TimeInterval) -> Double {
        let doseDuration = endDate.timeIntervalSince(startDate)  // t1
        let time = date.timeIntervalSince(startDate)
        var iob: Double = 0
        var doseDate = TimeInterval(0)  // i

        repeat {
            let segment: Double

            if doseDuration > 0 {
                segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            } else {
                segment = 1
            }

            iob += segment * model.percentEffectRemaining(at: time - doseDate)
            doseDate += delta
        } while doseDate <= min(floor((time + model.delay) / delta) * delta, doseDuration)

        return iob
    }

    func insulinOnBoard(at date: Date, model: InsulinModel, delta: TimeInterval) -> Double {
        let time = date.timeIntervalSince(startDate)
        guard time >= 0 else {
            return 0
        }

        // Consider doses within the delta time window as momentary
        if endDate.timeIntervalSince(startDate) <= 1.05 * delta {
            return netBasalUnits * model.percentEffectRemaining(at: time)
        } else {
            return netBasalUnits * continuousDeliveryInsulinOnBoard(at: date, model: model, delta: delta)
        }
    }

    private func continuousDeliveryGlucoseEffect(at date: Date, model: InsulinModel, delta: TimeInterval) -> Double {
        let doseDuration = endDate.timeIntervalSince(startDate)  // t1
        let time = date.timeIntervalSince(startDate)
        var value: Double = 0
        var doseDate = TimeInterval(0)  // i

        repeat {
            let segment: Double

            if doseDuration > 0 {
                segment = max(0, min(doseDate + delta, doseDuration) - doseDate) / doseDuration
            } else {
                segment = 1
            }

            value += segment * (1.0 - model.percentEffectRemaining(at: time - doseDate))
            doseDate += delta
        } while doseDate <= min(floor((time + model.delay) / delta) * delta, doseDuration)

        return value
    }

    func glucoseEffect(at date: Date, model: InsulinModel, insulinSensitivity: Double, delta: TimeInterval) -> Double {
        let time = date.timeIntervalSince(startDate)

        guard time >= 0 else {
            return 0
        }

        // Consider doses within the delta time window as momentary
        if endDate.timeIntervalSince(startDate) <= 1.05 * delta {
            return netBasalUnits * -insulinSensitivity * (1.0 - model.percentEffectRemaining(at: time))
        } else {
            return netBasalUnits * -insulinSensitivity * continuousDeliveryGlucoseEffect(at: date, model: model, delta: delta)
        }
    }

    func glucoseEffect(during interval: DateInterval, model: InsulinModel, insulinSensitivity: Double, delta: TimeInterval) -> Double {
        let start = interval.start.timeIntervalSince(startDate)
        let end = interval.end.timeIntervalSince(startDate)

        guard end-start >= 0 else {
            return 0
        }

        // Consider doses within the delta time window as momentary
        if endDate.timeIntervalSince(startDate) <= 1.05 * delta {
            let effect = model.percentEffectRemaining(at: start) - model.percentEffectRemaining(at: end)
            return netBasalUnits * -insulinSensitivity * effect
        } else {
            return netBasalUnits * -insulinSensitivity * continuousDeliveryGlucoseEffect(at: interval.end, model: model, delta: delta)
        }
    }


    public func trimmed(from start: Date? = nil, to end: Date? = nil, syncIdentifier: String? = nil) -> DoseEntry {

        let originalDuration = endDate.timeIntervalSince(startDate)

        let startDate = max(start ?? .distantPast, self.startDate)
        let endDate = max(startDate, min(end ?? .distantFuture, self.endDate))

        var trimmedDeliveredUnits: Double? = deliveredUnits
        var trimmedValue: Double = value

        if originalDuration > .ulpOfOne && (startDate > self.startDate || endDate < self.endDate) {
            let updatedActualDelivery = unitsInDeliverableIncrements * (endDate.timeIntervalSince(startDate) / originalDuration)
            if deliveredUnits != nil {
                trimmedDeliveredUnits = updatedActualDelivery
            }
            if case .units = unit  {
                trimmedValue = updatedActualDelivery
            }
        }

        return DoseEntry(
            type: type,
            startDate: startDate,
            endDate: endDate,
            value: trimmedValue,
            unit: unit,
            deliveredUnits: trimmedDeliveredUnits,
            description: description,
            syncIdentifier: syncIdentifier,
            scheduledBasalRate: scheduledBasalRate,
            insulinType: insulinType,
            automatic: automatic,
            isMutable: isMutable,
            wasProgrammedByPumpUI: wasProgrammedByPumpUI
        )
    }
}


extension DoseEntry {

    /// Annotates a dose with the context of a history of scheduled basal rates
    ///
    /// If the dose crosses a schedule boundary, it will be split into multiple doses so each dose has a
    /// single scheduled basal rate.
    ///
    /// - Parameter basalHistory: The history of basal schedule values to apply. Only schedule values overlapping the dose should be included.
    /// - Returns: An array of annotated doses
    fileprivate func annotated(with basalHistory: [AbsoluteScheduleValue<Double>]) -> [DoseEntry] {

        var doses: [DoseEntry] = []

        for (index, basalItem) in basalHistory.enumerated() {
            let startDate: Date
            let endDate: Date

            // If we're splitting into multiple entries, keep the syncIdentifier unique
            var syncIdentifier = self.syncIdentifier
            if syncIdentifier != nil, basalHistory.count > 1 {
                syncIdentifier! += " \(index + 1)/\(basalHistory.count)"
            }

            if index == 0 {
                startDate = self.startDate
            } else {
                startDate = basalItem.startDate
            }

            if index == basalHistory.count - 1 {
                endDate = self.endDate
            } else {
                endDate = basalHistory[index + 1].startDate
            }

            var dose = trimmed(from: startDate, to: endDate, syncIdentifier: syncIdentifier)

            dose.scheduledBasalRate = HKQuantity(unit: DoseEntry.unitsPerHour, doubleValue: basalItem.value)

            doses.append(dose)
        }

        return doses
    }

    /// Annotates a dose with the specified insulin type.
    ///
    /// - Parameter insulinType: The insulin type to annotate the dose with.
    /// - Returns: A dose annotated with the insulin model
    public func annotated(with insulinType: InsulinType) -> DoseEntry {
        return DoseEntry(
            type: type,
            startDate: startDate,
            endDate: endDate,
            value: value,
            unit: unit,
            deliveredUnits: deliveredUnits,
            description: description,
            syncIdentifier: syncIdentifier,
            scheduledBasalRate: scheduledBasalRate,
            insulinType: insulinType,
            automatic: automatic,
            isMutable: isMutable,
            wasProgrammedByPumpUI: wasProgrammedByPumpUI
        )
    }
}

extension DoseEntry {
    fileprivate var resolvingDelivery: DoseEntry {
        guard !isMutable, deliveredUnits == nil else {
            return self
        }

        let resolvedUnits: Double

        if case .units = unit {
            resolvedUnits = value
        } else {
            switch type {
            case .tempBasal:
                resolvedUnits = unitsInDeliverableIncrements
            case .basal:
                resolvedUnits = programmedUnits
            default:
                return self
            }
        }
        return DoseEntry(type: type, startDate: startDate, endDate: endDate, value: value, unit: unit, deliveredUnits: resolvedUnits, description: description, syncIdentifier: syncIdentifier, scheduledBasalRate: scheduledBasalRate, insulinType: insulinType, automatic: automatic, isMutable: isMutable, wasProgrammedByPumpUI: wasProgrammedByPumpUI)
    }
}

extension Collection where Element: TimelineValue {
    public var timespan: DateInterval {

        guard count > 0 else {
            return DateInterval(start: Date(), duration: 0)
        }

        var min: Date = .distantFuture
        var max: Date = .distantPast
        for value in self {
            if value.startDate < min {
                min = value.startDate
            }
            if value.endDate > max {
                max = value.endDate
            }
        }
        return DateInterval(start: min, end: max)
    }
}

extension Collection where Element == DoseEntry {

    /**
     Maps a timeline of dose entries with overlapping start and end dates to a timeline of doses that represents actual insulin delivery.

     - returns: An array of reconciled insulin delivery history, as TempBasal and Bolus records
     */
    func reconciled() -> [DoseEntry] {

        var reconciled: [DoseEntry] = []

        var lastSuspend: DoseEntry?
        var lastBasal: DoseEntry?

        for dose in self {
            switch dose.type {
            case .bolus:
                reconciled.append(dose)
            case .basal, .tempBasal:
                if lastSuspend == nil, let last = lastBasal {
                    let endDate = Swift.min(last.endDate, dose.startDate)

                    // Ignore 0-duration doses
                    if endDate > last.startDate {
                        reconciled.append(last.trimmed(from: nil, to: endDate, syncIdentifier: last.syncIdentifier))
                    }
                } else if let suspend = lastSuspend, dose.type == .tempBasal {
                    // Handle missing resume. Basal following suspend, with no resume.
                    reconciled.append(DoseEntry(
                        type: suspend.type,
                        startDate: suspend.startDate,
                        endDate: dose.startDate,
                        value: suspend.value,
                        unit: suspend.unit,
                        description: suspend.description ?? dose.description,
                        syncIdentifier: suspend.syncIdentifier,
                        insulinType: suspend.insulinType,
                        automatic: suspend.automatic,
                        isMutable: suspend.isMutable,
                        wasProgrammedByPumpUI: suspend.wasProgrammedByPumpUI
                    ))
                    lastSuspend = nil
                }

                lastBasal = dose
            case .resume:
                if let suspend = lastSuspend {

                    reconciled.append(DoseEntry(
                        type: suspend.type,
                        startDate: suspend.startDate,
                        endDate: dose.startDate,
                        value: suspend.value,
                        unit: suspend.unit,
                        description: suspend.description ?? dose.description,
                        syncIdentifier: suspend.syncIdentifier,
                        insulinType: suspend.insulinType,
                        automatic: suspend.automatic,
                        isMutable: suspend.isMutable,
                        wasProgrammedByPumpUI: suspend.wasProgrammedByPumpUI
                    ))

                    lastSuspend = nil

                    // Continue temp basals that may have started before suspending
                    if let last = lastBasal {
                        if last.endDate > dose.endDate {
                            lastBasal = DoseEntry(
                                type: last.type,
                                startDate: dose.endDate,
                                endDate: last.endDate,
                                value: last.value,
                                unit: last.unit,
                                description: last.description,
                                // We intentionally use the resume's identifier, as the basal entry has already been entered
                                syncIdentifier: dose.syncIdentifier,
                                insulinType: last.insulinType,
                                automatic: last.automatic,
                                isMutable: last.isMutable,
                                wasProgrammedByPumpUI: last.wasProgrammedByPumpUI
                            )
                        } else {
                            lastBasal = nil
                        }
                    }
                }
            case .suspend:
                if let last = lastBasal {

                    reconciled.append(DoseEntry(
                        type: last.type,
                        startDate: last.startDate,
                        endDate: Swift.min(last.endDate, dose.startDate),
                        value: last.value,
                        unit: last.unit,
                        description: last.description,
                        syncIdentifier: last.syncIdentifier,
                        insulinType: last.insulinType,
                        automatic: last.automatic,
                        isMutable: last.isMutable,
                        wasProgrammedByPumpUI: last.wasProgrammedByPumpUI
                    ))

                    if last.endDate <= dose.startDate {
                        lastBasal = nil
                    }
                }

                lastSuspend = dose
            }
        }

        if let suspend = lastSuspend {
            reconciled.append(DoseEntry(
                type: suspend.type,
                startDate: suspend.startDate,
                endDate: nil,
                value: suspend.value,
                unit: suspend.unit,
                description: suspend.description,
                syncIdentifier: suspend.syncIdentifier,
                insulinType: suspend.insulinType,
                automatic: suspend.automatic,
                isMutable: true,  // Consider mutable until paired resume
                wasProgrammedByPumpUI: suspend.wasProgrammedByPumpUI
            ))
        } else if let last = lastBasal, last.endDate > last.startDate {
            reconciled.append(last)
        }

        return reconciled.map { $0.resolvingDelivery }
    }

    /// Annotates a sequence of dose entries with the configured basal history
    ///
    /// Doses which cross time boundaries in the basal rate schedule are split into multiple entries.
    ///
    /// - Parameter basalSchedule: A history of basal rates covering the timespan of these doses.
    /// - Returns: An array of annotated dose entries
    public func annotated(with basalHistory: [AbsoluteScheduleValue<Double>]) -> [DoseEntry] {
        var annotatedDoses: [DoseEntry] = []

        for dose in self {
            let basalItems = basalHistory.filterDateRange(dose.startDate, dose.endDate)
            annotatedDoses += dose.annotated(with: basalItems)
        }

        return annotatedDoses
    }


    /**
     Calculates the total insulin delivery for a collection of doses

     - returns: The total insulin insulin, in Units
     */
    var totalDelivery: Double {
        return reduce(0) { (total, dose) -> Double in
            return total + dose.unitsInDeliverableIncrements
        }
    }

    /**
     Calculates the timeline of insulin remaining for a collection of doses

     - parameter insulinModelProvider:  A factory that can provide an insulin model given an insulin type
     - parameter longestEffectDuration: The longest duration that a dose could be active.
     - parameter start:                 The date to start the timeline
     - parameter end:                   The date to end the timeline
     - parameter delta:                 The differential between timeline entries, Defaults to 5 minutes.

     - returns: A sequence of insulin amount remaining
     */
    public func insulinOnBoard(
        insulinModelProvider: InsulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil),
        longestEffectDuration: TimeInterval = InsulinMath.defaultInsulinActivityDuration,
        from start: Date? = nil,
        to end: Date? = nil,
        delta: TimeInterval = GlucoseMath.defaultDelta
    ) -> [InsulinValue] {
        guard let (start, end) = LoopMath.simulationDateRangeForSamples(self, from: start, to: end, duration: longestEffectDuration, delta: delta) else {
            return []
        }

        var date = start
        var values = [InsulinValue]()

        repeat {
            let value = reduce(0) { (value, dose) -> Double in
                return value + dose.insulinOnBoard(at: date, model: insulinModelProvider.model(for: dose.insulinType), delta: delta)
            }

            values.append(InsulinValue(startDate: date, value: value))
            date = date.addingTimeInterval(delta)
        } while date <= end

        return values
    }

    /**
     Calculates insulin remaining at a given point in time for a collection of doses

     - parameter insulinModelProvider:  A factory that can provide an insulin model given an insulin type
     - parameter date:                  The date at which to calculate remaining insulin.  If nil, current date is used.

     - returns: A sequence of insulin amount remaining
     */
    public func insulinOnBoard(
        insulinModelProvider: InsulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil),
        at date: Date? = nil
    ) -> Double {

        let date = date ?? Date()

        return reduce(0) { (value, dose) -> Double in
            return value + dose.insulinOnBoard(at: date, model: insulinModelProvider.model(for: dose.insulinType), delta: GlucoseMath.defaultDelta)
        }
    }


    /// Calculates the timeline of glucose effects for a collection of doses. The ISF used for a given dose is based on the ISF in effect at the dose start time.
    ///
    /// - Parameters:
    ///   - insulinModelProvider: A factory that can provide an insulin model given an insulin type
    ///   - insulinSensitivityHistory: The timeline of glucose effect per unit of insulin
    ///   - start: The earliest date of effects to return
    ///   - end: The latest date of effects to return. If nil is passed, it will be calculated from the last sample end date plus the longestEffectDuration.
    ///   - delta: The interval between returned effects
    /// - Returns: An array of glucose effects for the duration of the doses
    public func glucoseEffects(
        insulinModelProvider: InsulinModelProvider,
        insulinSensitivityHistory: [AbsoluteScheduleValue<HKQuantity>],
        from start: Date? = nil,
        to end: Date? = nil,
        delta: TimeInterval = TimeInterval(/* minutes: */60 * 5)
    ) -> [GlucoseEffect] {

        let activeEntries = self.filter({ entry in
            entry.netBasalUnits != 0
        })

        guard let (start, end) = LoopMath.simulationDateRangeForSamples(activeEntries, from: start, to: end, duration: InsulinMath.longestInsulinActivityDuration, delta: delta) else {
            return []
        }

        var date = start
        var values = [GlucoseEffect]()
        let unit = HKUnit.milligramsPerDeciliter

        repeat {
            let value = reduce(0) { (value, dose) -> Double in

                guard let isfScheduleValue = insulinSensitivityHistory.closestPrior(to: dose.startDate), isfScheduleValue.endDate >= dose.startDate else {
                    preconditionFailure("ISF History must cover dose startDates")
                }
                let isf = isfScheduleValue.value.doubleValue(for: unit)
                let doseEffect = dose.glucoseEffect(at: date, model: insulinModelProvider.model(for: dose.insulinType), insulinSensitivity: isf, delta: delta)
                return value + doseEffect
            }

            values.append(GlucoseEffect(startDate: date, quantity: HKQuantity(unit: unit, doubleValue: value)))
            date = date.addingTimeInterval(delta)
        } while date <= end

        return values
    }


    /// Calculates the timeline of glucose effects for a collection of doses.  Effects for a specific dose will vary over the course
    /// of that dose's absoption interval based on the timeline of insulin sensitivity.
    ///
    /// - Parameters:
    ///   - insulinModelProvider: A factory that can provide an insulin model given an insulin type
    ///   - longestEffectDuration: The longest duration that a dose could be active.
    ///   - insulinSensitivityTimeline: A timeline of glucose effect per unit of insulin
    ///   - start: The earliest date of effects to return
    ///   - end: The latest date of effects to return
    ///   - delta: The interval between returned effects
    /// - Returns: An array of glucose effects for the duration of the doses
    public func glucoseEffects(
        insulinModelProvider: InsulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil),
        longestEffectDuration: TimeInterval = InsulinMath.defaultInsulinActivityDuration,
        insulinSensitivityTimeline: [AbsoluteScheduleValue<HKQuantity>],
        from start: Date? = nil,
        to end: Date? = nil,
        delta: TimeInterval = TimeInterval(/* minutes: */60 * 5)
    ) -> [GlucoseEffect] {
        guard let (start, end) = LoopMath.simulationDateRangeForSamples(self.filter({ entry in
            entry.netBasalUnits != 0
        }), from: start, to: end, duration: longestEffectDuration, delta: delta) else {
            return []
        }

        var lastDate = start
        var date = start
        var effectSum: Double = 0
        var values = [GlucoseEffect]()
        let unit = HKUnit.milligramsPerDeciliter

        repeat {
            // Sum effects over doses
            let value = reduce(0) { (value, dose) -> Double in
                guard date != lastDate else {
                    return 0
                }

                let model = insulinModelProvider.model(for: dose.insulinType)

                // Sum effects over pertinent ISF timeline segments
                let isfSegments = insulinSensitivityTimeline.filterDateRange(lastDate, date)
                return value + isfSegments.reduce(0, { partialResult, segment in
                    let start = Swift.max(lastDate, segment.startDate)
                    let end = Swift.min(date, segment.endDate)
                    return partialResult + dose.glucoseEffect(during: DateInterval(start: start, end: end), model: model, insulinSensitivity: segment.value.doubleValue(for: unit), delta: delta)
                })
            }

            effectSum += value
            values.append(GlucoseEffect(startDate: date, quantity: HKQuantity(unit: unit, doubleValue: effectSum)))
            lastDate = date
            date = date.addingTimeInterval(delta)
        } while date <= end

        return values
    }

    /// Calculates the timeline of glucose effects for a collection of doses at specified points in time. Effects for a specific dose will vary over the course
    /// of that dose's absoption interval based on the timeline of insulin sensitivity.
    ///
    /// - Parameters:
    ///   - insulinModelProvider: A factory that can provide an insulin model given an insulin type
    ///   - longestEffectDuration: The longest duration that a dose could be active.
    ///   - insulinSensitivityTimeline: A timeline of glucose effect per unit of insulin
    ///   - effectDates: The dates at which to calculate glucose effects
    ///   - delta: The interval below which to consider doses as momentary
    /// - Returns: An array of glucose effects for the duration of the doses
    public func glucoseEffects(
        insulinModelProvider: InsulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil),
        longestEffectDuration: TimeInterval = InsulinMath.defaultInsulinActivityDuration,
        insulinSensitivityTimeline: [AbsoluteScheduleValue<HKQuantity>],
        effectDates: [Date],
        delta: TimeInterval = TimeInterval(/* minutes: */60 * 5)
    ) -> [GlucoseEffect] {

        var lastDate = effectDates.first!
        var values = [GlucoseEffect]()
        let unit = HKUnit.milligramsPerDeciliter

        for date in effectDates {
            // Sum effects over doses
            let value = reduce(0) { (value, dose) -> Double in
                guard date != lastDate else {
                    return 0
                }

                let model = insulinModelProvider.model(for: dose.insulinType)

                // Sum effects over pertinent ISF timeline segments
                let isfSegments = insulinSensitivityTimeline.filterDateRange(lastDate, date)
                return value + isfSegments.reduce(0, { partialResult, segment in
                    let start = Swift.max(lastDate, segment.startDate)
                    let end = Swift.min(date, segment.endDate)
                    let effect = dose.glucoseEffect(during: DateInterval(start: start, end: end), model: model, insulinSensitivity: segment.value.doubleValue(for: unit), delta: delta)
                    return partialResult + effect
                })
            }

            values.append(GlucoseEffect(startDate: date, quantity: HKQuantity(unit: unit, doubleValue: value)))
            lastDate = date
        }

        return values
    }

    /// Fills any missing gaps in basal delivery with new doses based on the supplied basal history. Compared to `overlayBasalSchedule`, this uses a history of
    /// of basal rates, rather than a daily schedule, so it can work across multiple schedule changes.  This method is suitable for generating a display of basal delivery
    /// that includes scheduled and temp basals. Boluses are not included in the returned array.
    ///
    /// - Parameters:
    ///   - basalHistory: A history of scheduled basal rates. The first record should have a timestamp matching or earlier than the start date of the first DoseEntry in this array.
    ///   - endDate: Infill to this date, if supplied. If not supplied, infill will stop at the last DoseEntry.
    ///   - gapPatchInterval: if the gap between two temp basals is less than this, then the start date of the second dose will be fudged to fill the gap. Used for display purposes.
    /// - Returns: An array of doses, with new doses created for any gaps between basalHistory.first.startDate and the end date.
    public func infill(with basalHistory: [AbsoluteScheduleValue<Double>], endDate: Date? = nil, gapPatchInterval: TimeInterval = 0) -> [DoseEntry] {
        guard basalHistory.count > 0 else {
            return Array(self)
        }

        var newEntries = [DoseEntry]()
        var curBasalIdx = basalHistory.startIndex
        var lastDate = basalHistory[curBasalIdx].startDate

        func addBasalsBetween(startDate: Date, endDate: Date) {
            while lastDate < endDate {
                let entryEnd: Date
                let nextBasalIdx = curBasalIdx + 1
                let curRate = basalHistory[curBasalIdx].value
                if nextBasalIdx < basalHistory.endIndex && basalHistory[nextBasalIdx].startDate < endDate {
                    entryEnd = Swift.max(startDate, basalHistory[nextBasalIdx].startDate)
                    curBasalIdx = nextBasalIdx
                } else {
                    entryEnd = endDate
                }

                if lastDate != entryEnd {
                    newEntries.append(
                        DoseEntry(
                            type: .basal,
                            startDate: lastDate,
                            endDate: entryEnd,
                            value: curRate,
                            unit: .unitsPerHour))

                    lastDate = entryEnd
                }
            }
        }

        for dose in self {
            switch dose.type {
            case .tempBasal, .basal, .suspend:
                var doseStart = dose.startDate
                if doseStart.timeIntervalSince(lastDate) > gapPatchInterval {
                    addBasalsBetween(startDate: lastDate, endDate: dose.startDate)
                } else {
                    doseStart = lastDate
                }
                newEntries.append(DoseEntry(
                    type: dose.type,
                    startDate: doseStart,
                    endDate: dose.endDate,
                    value: dose.unitsPerHour,
                    unit: .unitsPerHour)
                )
                lastDate = dose.endDate
            case .resume:
                assertionFailure("No resume events should be present in reconciled doses")
            case .bolus:
                break
            }
        }

        if let endDate, endDate > lastDate {
            addBasalsBetween(startDate: lastDate, endDate: endDate)
        }

        return newEntries
    }

    /// Creates an array of DoseEntry values by unioning another array, de-duplicating by syncIdentifier
    ///
    /// - Parameter otherDoses: An array of doses to union
    /// - Returns: A new array of doses
    func appendedUnion(with otherDoses: [DoseEntry]) -> [DoseEntry] {
        var union: [DoseEntry] = []
        var syncIdentifiers: Set<String> = []

        for dose in (self + otherDoses) {
            if let syncIdentifier = dose.syncIdentifier {
                let (inserted, _) = syncIdentifiers.insert(syncIdentifier)
                if !inserted {
                    continue
                }
            }

            union.append(dose)
        }

        return union
    }
}


extension BidirectionalCollection where Element == DoseEntry {
    /// The endDate of the last basal dose in the collection
    var lastBasalEndDate: Date? {
        for dose in self.reversed() {
            if dose.type == .basal || dose.type == .tempBasal || dose.type == .resume {
                return dose.endDate
            }
        }

        return nil
    }
}
