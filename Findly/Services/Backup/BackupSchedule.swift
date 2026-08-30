import Foundation

enum BackupFrequency: String, CaseIterable, Codable, Sendable {
    case daily
    case weekly

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

/// A fixed, local-calendar backup schedule.
///
/// Weekdays use `Calendar`'s numbering: 1 is Sunday and 7 is Saturday.
struct BackupSchedule: Equatable, Sendable {
    var frequency: BackupFrequency
    var hour: Int
    var minute: Int
    var weekday: Int

    init(
        frequency: BackupFrequency = .daily,
        hour: Int = 21,
        minute: Int = 0,
        weekday: Int = 1
    ) {
        self.frequency = frequency
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekday = min(max(weekday, 1), 7)
    }

    func nextOccurrence(
        after date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        calendar.nextDate(
            after: date,
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    func mostRecentOccurrence(
        atOrBefore date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        // Move one second forward so an occurrence exactly at `date` is included.
        calendar.nextDate(
            after: date.addingTimeInterval(1),
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward
        )
    }

    func dueOccurrence(
        at date: Date,
        establishedAt: Date,
        lastHandledOccurrence: Date?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let occurrence = mostRecentOccurrence(atOrBefore: date, calendar: calendar),
              occurrence > establishedAt else {
            return nil
        }

        if let lastHandledOccurrence, occurrence <= lastHandledOccurrence {
            return nil
        }
        return occurrence
    }

    private var matchingComponents: DateComponents {
        var components = DateComponents()
        if frequency == .weekly {
            components.weekday = weekday
        }
        components.hour = hour
        components.minute = minute
        components.second = 0
        return components
    }
}

extension BackupSchedule {
    func description(calendar: Calendar = .autoupdatingCurrent) -> String {
        var components = DateComponents()
        components.calendar = calendar
        components.hour = hour
        components.minute = minute
        let time = components.date?.formatted(date: .omitted, time: .shortened) ?? ""

        switch frequency {
        case .daily:
            return "Every day at \(time)"
        case .weekly:
            let symbols = calendar.weekdaySymbols
            let day = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
            return "Every \(day) at \(time)"
        }
    }
}
