import Foundation
import SwiftUI

enum CheckInPeriod: String, Codable, CaseIterable, Identifiable {
    case day, week, month, year, all
    var id: Self { self }
    var title: String {
        switch self {
        case .day: "每日"
        case .week: "每周"
        case .month: "每月"
        case .year: "每年"
        case .all: "累计"
        }
    }

    var component: Calendar.Component? {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }

    func interval(at date: Date, calendar: Calendar = .current) -> DateInterval? {
        component.flatMap { calendar.dateInterval(of: $0, for: date) }
    }

    func contains(_ date: Date, around reference: Date) -> Bool {
        guard let interval = interval(at: reference) else { return true }
        return date >= interval.start && date < interval.end
    }

    func offset(_ date: Date, by amount: Int, calendar: Calendar = .current) -> Date {
        guard let component else { return date }
        return calendar.date(byAdding: component, value: amount, to: date) ?? date
    }

    func label(for date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.year().month().day())
        case .week:
            if let interval = interval(at: date) {
                "\(interval.start.formatted(.dateTime.month().day())) – \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month().day()))"
            } else {
                date.formatted(.dateTime.month().day())
            }
        case .month: date.formatted(.dateTime.year().month(.twoDigits))
        case .year: date.formatted(.dateTime.year())
        case .all: "全部记录"
        }
    }
}

enum CheckInColor: String, Codable, CaseIterable, Identifiable {
    case gold, olive, cyan, orange, green, blue, pink, purple
    var id: Self { self }
    var tint: Color {
        switch self {
        case .gold: Color(red: 0.88, green: 0.61, blue: 0.02)
        case .olive: Color(red: 0.54, green: 0.63, blue: 0.12)
        case .cyan: Color(red: 0.02, green: 0.63, blue: 0.77)
        case .orange: Color(red: 0.95, green: 0.38, blue: 0.10)
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .purple: .purple
        }
    }
    var title: String {
        switch self {
        case .gold: "金黄"
        case .olive: "橄榄绿"
        case .cyan: "湖蓝"
        case .orange: "橙色"
        case .green: "绿色"
        case .blue: "蓝色"
        case .pink: "粉色"
        case .purple: "紫色"
        }
    }
}

enum GoalRule: String, Codable, CaseIterable, Identifiable {
    case minimum, maximum
    var id: Self { self }
    var title: String { self == .minimum ? "需达到" : "不超过" }
}

struct CheckInGoal: Codable, Equatable {
    var enabled = false
    var period: CheckInPeriod = .month
    var rule: GoalRule = .minimum
    var target: Double = 10

    func ratio(_ value: Double) -> Double {
        guard target > 0 else { return 0 }
        return value / target
    }

}

struct CheckInItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var unit = "次"
    var color: CheckInColor = .gold
    var goal = CheckInGoal()
    var deletedAt: Date?
}

enum CheckInItemKind: String, Codable, CaseIterable, Identifiable {
    case number, count
    var id: Self { self }
    var title: String { self == .number ? "数值型" : "次数型" }
}

struct CheckInProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var icon = "⭐️"
    var subtitle = ""
    var group = "日常"
    var color: CheckInColor = .gold
    var targetDays = 30
    var showRecordCount = false
    var itemsEnabled = true
    var itemKind: CheckInItemKind = .number
    var sumValues = true
    var reminderEnabled = false
    var reminderHour = 20
    var reminderMinute = 0
    var items: [CheckInItem] = []
    var createdAt = Date()
    var modifiedAt = Date()
    var deletedAt: Date?

    var visibleItems: [CheckInItem] { items.filter { $0.deletedAt == nil } }
    var activeItems: [CheckInItem] { itemsEnabled ? visibleItems : [] }
    func unit(for item: CheckInItem) -> String { itemKind == .count ? "次" : item.unit }
    func goalUnit(for item: CheckInItem) -> String { sumValues ? unit(for: item) : "次" }
    func metricValue(_ recordedValue: Double) -> Double { itemKind == .count ? 1 : recordedValue }
}

struct CheckInPhoto: Identifiable, Codable, Equatable {
    var id = UUID()
    var jpeg: Data
}

struct CheckInRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var projectID: UUID
    var date = Date()
    var values: [UUID: Double] = [:]
    var note = ""
    var photos: [CheckInPhoto] = []
    var modifiedAt = Date()
    var deleted = false
}

struct CheckInArchive: Codable, Equatable {
    static let currentSchema = 1
    var schemaVersion = Self.currentSchema
    var projects: [CheckInProject] = []
    var records: [CheckInRecord] = []
    var themePreference: AppThemePreference?

    static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        switch header.schemaVersion {
        case 1: return try decoder.decode(Self.self, from: data)
        default: throw CocoaError(.fileReadUnknown)
        }
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    var isValidBackup: Bool {
        guard Set(projects.map(\.id)).count == projects.count,
              Set(records.map(\.id)).count == records.count else { return false }
        if let theme = themePreference?.theme {
            guard [theme.hue, theme.saturation, theme.brightness].allSatisfy({ (0...1).contains($0) }) else {
                return false
            }
        }
        return projects.allSatisfy { project in
            project.targetDays > 0 &&
                (0...23).contains(project.reminderHour) &&
                (0...59).contains(project.reminderMinute) &&
                Set(project.items.map(\.id)).count == project.items.count &&
                project.items.allSatisfy { !$0.goal.enabled || $0.goal.target > 0 }
        } && records.allSatisfy { record in
            record.values.values.allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }

    mutating func merge(_ other: Self) {
        if let incoming = other.themePreference,
           themePreference.map({ incoming.modifiedAt > $0.modifiedAt }) ?? true {
            themePreference = incoming
        }
        for project in other.projects {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                let previous = projects[index]
                var merged = project.modifiedAt > previous.modifiedAt ? project : previous
                merged.deletedAt = previous.deletedAt ?? project.deletedAt
                for item in (previous.items + project.items) where item.deletedAt != nil {
                    if let position = merged.items.firstIndex(where: { $0.id == item.id }) {
                        merged.items[position].deletedAt = item.deletedAt
                    } else {
                        merged.items.append(item)
                    }
                }
                projects[index] = merged
            } else {
                projects.append(project)
            }
        }
        for record in other.records {
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                if record.modifiedAt > records[index].modifiedAt { records[index] = record }
            } else {
                records.append(record)
            }
        }
    }
}

struct CheckInGoalResult {
    let value: Double
    let ratio: Double
    let achieved: Bool
    var achievedDays: Int?
    var progressRatio: Double { min(ratio, 1) }

    func summary(unit: String) -> String {
        if let achievedDays { return "\(achievedDays) 天达成" }
        return "\(value.checkInText)\(unit)"
    }
}

struct CheckInMetrics {
    let records: [CheckInRecord]

    var dayCount: Int { Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count }

    func filtered(_ period: CheckInPeriod, at date: Date) -> Self {
        Self(records: records.filter { period.contains($0.date, around: date) })
    }

    func values(for item: CheckInItem) -> [Double] {
        records.compactMap { $0.values[item.id] }
    }

    func progress(for item: CheckInItem, in project: CheckInProject) -> Double {
        let values = values(for: item)
        return project.sumValues ? values.reduce(0) { $0 + project.metricValue($1) } : values.count.double
    }

    var days: [Date: [CheckInRecord]] {
        Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) }
    }

    func meetsMaximum(for item: CheckInItem, in project: CheckInProject) -> Bool {
        let entries = values(for: item)
        return !entries.isEmpty && progress(for: item, in: project) <= item.goal.target
    }

    func completedDays(for project: CheckInProject) -> [Date: [CheckInRecord]] {
        let limits = project.activeItems.filter { $0.goal.enabled && $0.goal.rule == .maximum }
        return days.filter { _, entries in
            let day = Self(records: entries)
            return limits.allSatisfy { day.meetsMaximum(for: $0, in: project) }
        }
    }

    func goalResult(for item: CheckInItem, in project: CheckInProject) -> CheckInGoalResult {
        let value = progress(for: item, in: project)
        if item.goal.rule == .minimum {
            return CheckInGoalResult(value: value, ratio: item.goal.ratio(value), achieved: value >= item.goal.target)
        }
        let grouped = days
        let achievedDays = grouped.values.filter { Self(records: $0).meetsMaximum(for: item, in: project) }.count
        let ratio = grouped.isEmpty ? 0 : achievedDays.double / grouped.count.double
        return CheckInGoalResult(value: value, ratio: ratio, achieved: ratio == 1, achievedDays: achievedDays)
    }

    func colors(for project: CheckInProject) -> [CheckInColor] {
        guard !records.isEmpty else { return [] }
        let ids = Set(records.flatMap { $0.values.keys })
        let colors = project.items.filter { ids.contains($0.id) }.map(\.color)
        return colors.isEmpty ? [project.color] : colors
    }
}

extension Int {
    var double: Double { Double(self) }
}

extension Double {
    var checkInText: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }
}
