import Charts
import SwiftUI

struct CheckInStatisticsView: View {
    let project: CheckInProject
    let metrics: CheckInMetrics
    @State private var period: CheckInPeriod = .month
    @State private var date = Date()
    @State private var byValue = false

    private struct ItemStatistics: Identifiable {
        let item: CheckInItem
        let entries: [CheckInRecord]
        let project: CheckInProject
        var id: UUID { item.id }
        var values: [Double] { entries.compactMap { $0.values[id] }.map(project.metricValue) }
        var total: Double { values.reduce(0, +) }
        var average: Double { entries.isEmpty ? 0 : total / entries.count.double }
        var dayCount: Int { CheckInMetrics(records: entries).dayCount }
    }

    var body: some View {
        let selected = metrics.filtered(period, at: date)
        let items = project.activeItems.map { item in
            ItemStatistics(item: item, entries: selected.records.filter { $0.values[item.id] != nil }, project: project)
        }
        VStack(alignment: .leading, spacing: 10) {
            Picker("统计周期", selection: $period) {
                ForEach(CheckInPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, _ in date = .now }
            VStack(alignment: .leading, spacing: 2) {
                CheckInDateHeader(period: period, date: $date, currentTitle: currentPeriodTitle)
                Text("按所选时间范围统计数据").font(.caption2).foregroundStyle(.secondary)
            }
            summary(selected)
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(items) { entry in
                        if entry.id != items.first?.id { Divider() }
                        itemRow(entry)
                    }
                }
                .padding(8)
                .background(CheckInStyle.background, in: .rect(cornerRadius: 9))
                distribution(items)
                ForEach(items.filter { !$0.entries.isEmpty }) { entry in
                    chart(entry)
                }
            }
        }
        .checkInCard()
    }

    private var currentPeriodTitle: String? {
        switch period {
        case .day: "今天"
        case .week: "本周"
        case .month: "本月"
        case .year: "今年"
        case .all: nil
        }
    }

    private var daysInSelection: Double {
        let calendar = Calendar.current
        if let interval = period.interval(at: date) {
            return max(1, (calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1).double)
        }
        guard let first = metrics.records.last, let last = metrics.records.first else { return 1 }
        let start = calendar.startOfDay(for: first.date)
        let end = calendar.startOfDay(for: last.date)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0).double + 1)
    }

    private func summary(_ selected: CheckInMetrics) -> some View {
        let count = selected.records.count
        return HStack {
            metric("\(selected.dayCount) 天", "累计")
            Divider()
            metric("\(count) 次", "累计")
            Divider()
            metric(count == 0 ? "—" : "\((daysInSelection / count.double).checkInText) 天/次", "平均")
        }
        .frame(height: 52)
        .padding(.vertical, 5)
        .background(CheckInStyle.background, in: .rect(cornerRadius: 9))
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func itemRow(_ entry: ItemStatistics) -> some View {
        HStack(spacing: 8) {
            Text(entry.item.name)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(5)
                .background(entry.item.color.tint, in: .rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.average.checkInText)\(project.unit(for: entry.item))/次")
                Text(entry.entries.isEmpty ? "—" : "\((daysInSelection / entry.entries.count.double).checkInText) 天/次")
            }
            .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.total.checkInText)\(project.unit(for: entry.item))").font(.subheadline.bold())
                Text("\(entry.entries.count) 次").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func distribution(_ items: [ItemStatistics]) -> some View {
        let measure: (ItemStatistics) -> Double = { byValue ? $0.total : $0.entries.count.double }
        let visible = items.filter { measure($0) > 0 }
        let total = visible.reduce(0.0) { $0 + measure($1) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("子项目占比").font(.subheadline.bold())
                Picker("占比方式", selection: $byValue) {
                    Text("按次数").tag(false)
                    Text("按累计值").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if visible.isEmpty {
                Text("暂无可统计记录")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                Chart(visible) { entry in
                    SectorMark(angle: .value("占比", measure(entry)), innerRadius: .ratio(0.38), angularInset: 1.5)
                        .foregroundStyle(entry.item.color.tint)
                        .accessibilityLabel(entry.item.name)
                        .accessibilityValue((measure(entry) / total).formatted(.percent))
                }
                .frame(height: 175)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], spacing: 5) {
                    ForEach(visible) { entry in
                        Label("\(entry.item.name) \((measure(entry) / total).formatted(.percent.precision(.fractionLength(1))))",
                              systemImage: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(entry.item.color.tint)
                    }
                }
            }
        }
        .padding(10)
        .background(CheckInStyle.background, in: .rect(cornerRadius: 9))
    }

    private func chart(_ entry: ItemStatistics) -> some View {
        let calendar = Calendar.current
        let component: Calendar.Component = period == .day ? .hour : period == .all ? .year : period == .year ? .month : .day
        let grouped = Dictionary(grouping: entry.entries) {
            calendar.dateInterval(of: component, for: $0.date)?.start ?? $0.date
        }
        let points = grouped.mapValues { records in records.compactMap { $0.values[entry.id] }.map(project.metricValue).reduce(0, +) }
        return VStack(alignment: .leading, spacing: 6) {
            Chart(points.keys.sorted(), id: \.self) { point in
                BarMark(
                    x: .value("日期", point, unit: component),
                    y: .value("累计值", points[point, default: 0])
                )
                .foregroundStyle(entry.item.color.tint)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
            .frame(height: 112)
            HStack {
                Label(entry.item.name, systemImage: "square.fill")
                    .foregroundStyle(entry.item.color.tint).font(.caption.bold())
                Spacer()
                Text("\(entry.dayCount) 天 · \(entry.entries.count) 次 · \((daysInSelection / entry.entries.count.double).checkInText) 天/次")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                metric(entry.total.checkInText, "累计值")
                metric(entry.average.checkInText, "平均值")
                metric((entry.values.max() ?? 0).checkInText, "最大值")
                metric((entry.values.min() ?? 0).checkInText, "最小值")
            }
        }
        .padding(10)
        .background(CheckInStyle.background, in: .rect(cornerRadius: 9))
    }
}

struct CheckInHeatmap: View {
    let project: CheckInProject
    let metrics: CheckInMetrics
    @State private var year = Date()

    var body: some View {
        let calendar = Calendar.current
        let yearStart = calendar.dateInterval(of: .year, for: year)?.start ?? year
        let days = Dictionary(grouping: metrics.records) { calendar.startOfDay(for: $0.date) }
        VStack(alignment: .leading, spacing: 7) {
            CheckInDateHeader(period: .year, date: $year, currentTitle: nil)
            Text("年度打卡热力图").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<12, id: \.self) { month in
                if let date = calendar.date(byAdding: .month, value: month, to: yearStart) {
                    let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 0
                    HStack(spacing: 2) {
                        Text("\(month + 1)").font(.system(size: 8).monospacedDigit())
                            .frame(width: 15, alignment: .trailing)
                        ForEach(0..<31, id: \.self) { index in
                            if index < count, let day = calendar.date(byAdding: .day, value: index, to: date) {
                                let colors = CheckInMetrics(records: days[day] ?? []).colors(for: project)
                                CheckInColorMarker(colors: colors).frame(maxWidth: .infinity)
                                    .accessibilityHidden(false)
                                    .accessibilityLabel("\(month + 1)月\(index + 1)日")
                                    .accessibilityValue(colors.isEmpty ? "无记录" : "有记录")
                            } else {
                                Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(height: 8)
                }
            }
            if !project.activeItems.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), alignment: .leading)], spacing: 5) {
                    ForEach(project.activeItems) { item in
                        Label(item.name, systemImage: "square.fill").font(.caption2)
                            .foregroundStyle(item.color.tint)
                    }
                }
            }
        }
        .checkInCard()
    }
}
