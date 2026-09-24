import Foundation

/// The daily release check follows the Mac's current calendar and time zone.
enum UpdateCheckSchedule {
    static let hour = 11

    static func nextCheck(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }

    static func isDue(
        at now: Date,
        lastAttempt: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let today = calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: now
        ) else { return false }

        // A fresh install waits until 11:00. After a missed day, catch up on
        // the next launch or wake, even if it happens before today's 11:00.
        guard let lastAttempt else { return now >= today }
        let latestScheduledCheck = now >= today
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)
        guard let latestScheduledCheck else { return false }
        return lastAttempt < latestScheduledCheck
    }
}
