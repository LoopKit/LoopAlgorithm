//
//  DoseHistoryTests.swift
//  LoopAlgorithmTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import LoopAlgorithm

/// A dose in the pump event format of LoopKit's dose fixtures
struct PumpEventDose {
    enum Kind: String {
        case basal = "BasalProfileStart"
        case bolus = "Bolus"
        case resume = "PumpResume"
        case suspend = "PumpSuspend"
        case tempBasal = "TempBasal"
    }

    var kind: Kind
    var startDate: Date
    var endDate: Date
    var value: Double
    var isRate: Bool
    var deliveredUnits: Double? = nil
    var scheduledBasalRate: Double? = nil

    var programmedUnits: Double {
        isRate ? value * endDate.timeIntervalSince(startDate).hours : value
    }

    var unitsInDeliverableIncrements: Double {
        guard isRate else {
            return deliveredUnits ?? programmedUnits
        }
        return deliveredUnits ?? round(programmedUnits * 20) / 20
    }

    func basalRelativeDose(with insulinModel: InsulinModel) -> BasalRelativeDose {
        let type: BasalRelativeDoseType
        switch kind {
        case .bolus:
            type = .bolus
        case .basal:
            type = .basal(scheduledRate: value)
        case .resume, .suspend, .tempBasal:
            type = .basal(scheduledRate: scheduledBasalRate ?? 0)
        }
        return BasalRelativeDose(type: type, startDate: startDate, endDate: endDate, volume: deliveredUnits ?? programmedUnits, insulinModel: insulinModel)
    }

    func insulinDose(with insulinModel: InsulinModel) -> MockInsulinDose {
        MockInsulinDose(deliveryType: kind == .bolus ? .bolus : .basal, startDate: startDate, endDate: endDate,
                        volume: deliveredUnits ?? programmedUnits, insulinModel: insulinModel)
    }
}

struct MockInsulinDose: InsulinDose {
    var deliveryType: InsulinDeliveryType
    var startDate: Date
    var endDate: Date
    var volume: Double
    var insulinModel: InsulinModel
}

/// John Walsh's IOB curves, as LoopKit's WalshInsulinModel; some fixtures were generated with it
struct WalshInsulinModel: InsulinModel {
    let actionDuration: TimeInterval
    let delay: TimeInterval = 600

    var effectDuration: TimeInterval { actionDuration + delay }

    func percentEffectRemaining(at time: TimeInterval) -> Double {
        let timeAfterDelay = time - delay
        guard timeAfterDelay > 0 else { return 1 }
        guard timeAfterDelay < actionDuration else { return 0 }

        let nearestModeledDuration = TimeInterval(hours: min(6, max(3, round(actionDuration.hours))))
        let minutes = timeAfterDelay.minutes * nearestModeledDuration / actionDuration

        switch nearestModeledDuration {
        case TimeInterval(hours: 3):
            return -3.2030e-9 * pow(minutes, 4) + 1.354e-6 * pow(minutes, 3) - 1.759e-4 * pow(minutes, 2) + 9.255e-4 * minutes + 0.99951
        case TimeInterval(hours: 4):
            return -3.310e-10 * pow(minutes, 4) + 2.530e-7 * pow(minutes, 3) - 5.510e-5 * pow(minutes, 2) - 9.086e-4 * minutes + 0.99950
        case TimeInterval(hours: 5):
            return -2.950e-10 * pow(minutes, 4) + 2.320e-7 * pow(minutes, 3) - 5.550e-5 * pow(minutes, 2) + 4.490e-4 * minutes + 0.99300
        default:
            return -1.493e-10 * pow(minutes, 4) + 1.413e-7 * pow(minutes, 3) - 4.095e-5 * pow(minutes, 2) + 6.365e-4 * minutes + 0.99700
        }
    }
}

/// A repeating daily basal schedule, expanded the way LoopKit's DailyValueSchedule.between does for a
/// fixed-offset time zone and a first item at midnight
struct DailyBasalSchedule {
    var items: [(startTime: TimeInterval, rate: Double)]
    var timeZone: TimeZone

    func between(start: Date, end: Date) -> [AbsoluteScheduleValue<Double>] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var day = calendar.startOfDay(for: start).addingTimeInterval(.hours(-24))
        var values: [AbsoluteScheduleValue<Double>] = []
        while day <= end {
            for (index, item) in items.enumerated() {
                let segmentStart = day.addingTimeInterval(item.startTime)
                let segmentEnd = day.addingTimeInterval(index + 1 < items.count ? items[index + 1].startTime : .hours(24))
                if segmentEnd > start && segmentStart <= end {
                    values.append(AbsoluteScheduleValue(startDate: segmentStart, endDate: segmentEnd, value: item.rate))
                }
            }
            day = day.addingTimeInterval(.hours(24))
        }
        return values
    }
}

final class DoseHistoryTests: XCTestCase {

    private let fixtureTimeZone = TimeZone(secondsFromGMT: 0)!

    let exponentialModel = ExponentialInsulinModel(actionDuration: .minutes(360), peakActivityTime: .minutes(75))

    let walshModel = WalshInsulinModel(actionDuration: .hours(4))

    private func fixtureDate(_ input: String) -> Date {
        let formatter = DateFormatter.descriptionFormatter
        formatter.timeZone = fixtureTimeZone
        return formatter.date(from: input)!
    }

    func loadDoseFixture(_ resourceName: String) -> [PumpEventDose] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDate(timeZone: fixtureTimeZone)

        return fixture.compactMap {
            guard let kind = PumpEventDose.Kind(rawValue: $0["type"] as! String) else {
                return nil
            }
            return PumpEventDose(
                kind: kind,
                startDate: dateFormatter.date(from: $0["start_at"] as! String)!,
                endDate: dateFormatter.date(from: $0["end_at"] as! String)!,
                value: $0["amount"] as! Double,
                isRate: $0["unit"] as! String == "U/hour",
                deliveredUnits: $0["delivered"] as? Double,
                scheduledBasalRate: $0["scheduled"] as? Double
            )
        }
    }

    func loadInsulinValueFixture(_ resourceName: String) -> [InsulinValue] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDate(timeZone: fixtureTimeZone)

        return fixture.map {
            InsulinValue(startDate: dateFormatter.date(from: $0["date"] as! String)!, value: $0["value"] as! Double)
        }
    }

    func loadBasalScheduleFixture(_ resourceName: String) -> DailyBasalSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        return DailyBasalSchedule(items: fixture.map { (.minutes($0["minutes"] as! Double), $0["rate"] as! Double) }, timeZone: fixtureTimeZone)
    }

    func testIOBFromSuspend() {
        let input = loadDoseFixture("suspend_dose_reconciled")
        let normalizedOutput = loadDoseFixture("suspend_dose_reconciled_normalized")
        let iobOutput = loadInsulinValueFixture("suspend_dose_reconciled_normalized_iob")
        let basals = loadBasalScheduleFixture("basal")

        let basalTimeline = basals.between(start: input.first!.startDate, end: input.first!.startDate)

        let normalized = input.map { $0.insulinDose(with: walshModel) }.annotated(with: basalTimeline)

        XCTAssertEqual(normalizedOutput.count, normalized.count)

        for (expected, calculated) in zip(normalizedOutput, normalized) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, calculated.netBasalUnitsPerHour, accuracy: Double(Float.ulpOfOne))
        }

        let iob = normalized.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)

        XCTAssertEqual(iobOutput.count, iob.count)

        for (expected, calculated) in zip(iobOutput, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: Double(Float.ulpOfOne))
        }
    }

    func testIOBFromDoses() {
        let input = loadDoseFixture("normalized_doses")
        let output = loadInsulinValueFixture("iob_from_doses_output")

        let iob = input.map { $0.basalRelativeDose(with: walshModel) }.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)

        XCTAssertEqual(output.count, iob.count)

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.5)
        }
    }

    func testIOBFromNoDoses() {
        let input: [BasalRelativeDose] = []

        XCTAssertEqual(0, input.insulinOnBoardTimeline(longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration).count)
    }

    func testIOBFromDosesExponential() {
        let input = loadDoseFixture("normalized_doses")
        let output = loadInsulinValueFixture("iob_from_doses_exponential_output")

        let iob = input.map { $0.basalRelativeDose(with: exponentialModel) }.insulinOnBoardTimeline()

        XCTAssertEqual(output.count, iob.count)

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.5)
        }
    }

    func testIOBFromDosesWithDifferentInsulinCurves() {
        let f = fixtureDate
        let output = loadInsulinValueFixture("iob_from_multiple_curves_output")

        let doses = [
            PumpEventDose(kind: .basal, startDate: f("2018-05-15 14:42:36 +0000"), endDate: f("2018-05-16 14:42:36 +0000"), value: 0.84999999999999998, isRate: true),
            PumpEventDose(kind: .bolus, startDate: f("2018-05-15 14:44:46 +0000"), endDate: f("2018-05-15 14:44:46 +0000"), value: 0.9, isRate: false),
            PumpEventDose(kind: .tempBasal, startDate: f("2018-05-15 14:42:36 +0000"), endDate: f("2018-05-15 14:42:36 +0000"), value: 0.0, isRate: true),
            PumpEventDose(kind: .tempBasal, startDate: f("2018-05-15 14:32:51 +0000"), endDate: f("2018-05-15 15:02:51 +0000"), value: 1.8999999999999999, isRate: true),
            PumpEventDose(kind: .bolus, startDate: f("2018-05-15 14:52:51 +0000"), endDate: f("2018-05-15 15:52:51 +0000"), value: 0.9, isRate: false),
        ]

        let iobWithoutModel = doses.map { $0.basalRelativeDose(with: exponentialModel) }.insulinOnBoardTimeline()

        // The first bolus is Fiasp; everything else uses the child curve.
        let models: [InsulinModel] = [ExponentialInsulinModelPreset.rapidActingChild, ExponentialInsulinModelPreset.fiasp,
                                      ExponentialInsulinModelPreset.rapidActingChild, ExponentialInsulinModelPreset.rapidActingChild,
                                      ExponentialInsulinModelPreset.rapidActingChild]
        let iobWithModel = zip(doses, models).map { $0.basalRelativeDose(with: $1) }.insulinOnBoardTimeline()

        XCTAssertEqual(iobWithoutModel.count, iobWithModel.count)

        for (expected, calculated) in zip(output, iobWithModel) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.00001)
        }
    }

    func testIOBFromReservoirDoses() {
        let input = loadDoseFixture("normalized_reservoir_history_output")
        let output = loadInsulinValueFixture("iob_from_reservoir_output")

        let iob = input.map { $0.basalRelativeDose(with: walshModel) }.insulinOnBoardTimeline(longestEffectDuration: walshModel.effectDuration)

        XCTAssertEqual(output.count, iob.count)

        for (expected, calculated) in zip(output, iob) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.value, calculated.value, accuracy: 0.01)
        }
    }

    func testNormalizeReservoirDoses() {
        let input = loadDoseFixture("reservoir_history_with_rewind_and_prime_output")
        let output = loadDoseFixture("normalized_reservoir_history_output")
        let basalTimeline = loadBasalScheduleFixture("basal").between(start: input.last!.startDate, end: input.first!.endDate)

        let doses = input.map { $0.insulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult) }.annotated(with: basalTimeline)

        XCTAssertEqual(output.count, doses.count)

        // Total delivery on split doses should add up to delivery from original doses
        XCTAssertEqual(
            input.map(\.unitsInDeliverableIncrements).reduce(0, +),
            doses.map(\.volume).reduce(0, +),
            accuracy: Double(Float.ulpOfOne))

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.endDate, calculated.endDate)
            XCTAssertEqual(expected.value, calculated.volume / calculated.duration.hours, accuracy: Double(Float.ulpOfOne))
            switch calculated.type {
            case .basal(let scheduledRate):
                XCTAssertEqual(expected.scheduledBasalRate, scheduledRate)
            case .bolus:
                XCTFail("Unexpected bolus in dose history")
            }
        }
    }

    func testNormalizeEdgeCaseDoses() {
        assertNormalizes("normalize_edge_case_doses_input", into: "normalize_edge_case_doses_output")
    }

    func testNormalizeEdgeCaseDosesMutable() {
        assertNormalizes("normalize_edge_case_doses_mutable_input", into: "normalize_edge_case_doses_mutable_output")
    }

    private func assertNormalizes(_ inputName: String, into outputName: String, line: UInt = #line) {
        let input = loadDoseFixture(inputName)
        let output = loadDoseFixture(outputName)
        let basalTimeline = loadBasalScheduleFixture("basal").between(start: input.first!.startDate, end: input.last!.endDate)

        let doses = input.map { $0.insulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult) }.annotated(with: basalTimeline)

        XCTAssertEqual(output.count, doses.count, line: line)

        for (expected, calculated) in zip(output, doses) {
            XCTAssertEqual(expected.startDate, calculated.startDate, line: line)
            XCTAssertEqual(expected.endDate, calculated.endDate, line: line)
            XCTAssertEqual(expected.value, expected.isRate ? calculated.netBasalUnitsPerHour : calculated.netBasalUnits, accuracy: 0.01, line: line)
        }
    }

    func testAnnotateSplitsDeliveredUnitsProportionally() {
        assertSplitsProportionally(deliveredUnits: 0.1)
    }

    func testAnnotateSplitsPartialDeliveryProportionally() {
        assertSplitsProportionally(deliveredUnits: 0.05)
    }

    private func assertSplitsProportionally(deliveredUnits: Double, line: UInt = #line) {
        // A 5 minute temp basal starting one minute before a basal schedule change at noon
        let startDate = fixtureDate("2018-07-16 11:59:00 +0000")
        let endDate = startDate.addingTimeInterval(.minutes(5))
        let dose = PumpEventDose(kind: .tempBasal, startDate: startDate, endDate: endDate, value: 1, isRate: true, deliveredUnits: deliveredUnits)
        let basals = loadBasalScheduleFixture("basal").between(start: startDate, end: endDate)

        let splitDoses = [dose.insulinDose(with: ExponentialInsulinModelPreset.rapidActingAdult)].annotated(with: basals)

        XCTAssertEqual(2, splitDoses.count, line: line)
        XCTAssertEqual(deliveredUnits * 1.0/5.0, splitDoses[0].volume, accuracy: .ulpOfOne, line: line)
        XCTAssertEqual(deliveredUnits * 4.0/5.0, splitDoses[1].volume, accuracy: .ulpOfOne, line: line)
    }
}

private extension BasalRelativeDose {
    var netBasalUnitsPerHour: Double {
        duration > 0 ? netBasalUnits / duration.hours : 0
    }
}
