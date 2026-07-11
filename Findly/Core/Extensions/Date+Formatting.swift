import Foundation

extension Date {

    // MARK: - Relative strings

    /// e.g. "just now", "5 minutes ago", "2 hours ago", "Yesterday", "3 days ago"
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short version: "now", "5m", "2h", "1d", "3mo"
    var shortRelativeString: String {
        let seconds = Date().timeIntervalSince(self)
        switch seconds {
        case ..<60:         return "now"
        case ..<3600:       return "\(Int(seconds / 60))m ago"
        case ..<86400:      return "\(Int(seconds / 3600))h ago"
        case ..<2592000:    return "\(Int(seconds / 86400))d ago"
        case ..<31536000:   return "\(Int(seconds / 2592000))mo ago"
        default:            return "\(Int(seconds / 31536000))y ago"
        }
    }

    // MARK: - Formatted display

    /// e.g. "July 11, 2026"
    var fullDateString: String {
        formatted(date: .long, time: .omitted)
    }

    /// e.g. "Jul 11, 2026 at 3:45 PM"
    var fullDateTimeString: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    /// e.g. "3:45 PM"
    var shortTimeString: String {
        formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Grouping helpers

    var isToday: Bool      { Calendar.current.isDateInToday(self) }
    var isYesterday: Bool  { Calendar.current.isDateInYesterday(self) }
    var isThisWeek: Bool   { Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) }
    var isThisMonth: Bool  { Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month) }
    var isThisYear: Bool   { Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) }

    var groupLabel: String {
        if isToday       { return "Today" }
        if isYesterday   { return "Yesterday" }
        if isThisWeek    { return "This Week" }
        if isThisMonth   { return "This Month" }
        if isThisYear    { return formatted(.dateTime.month(.wide)) }
        return formatted(.dateTime.year())
    }
}

// MARK: - File size formatting

extension Int64 {
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Int {
    var fileSizeString: String {
        Int64(self).fileSizeString
    }
}
