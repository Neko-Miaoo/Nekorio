import SwiftUI

struct CheckInDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CheckInStore
    let projectID: UUID
    @State private var editor: Editor?
    @State private var month = Date()
    @State private var daySelection: SelectedDay?

    private enum Editor: Identifiable {
        case project, item(CheckInItem), goals, timeline
        var id: String {
            switch self {
            case .project: "project"
            case .item(let item): item.id.uuidString
            case .goals: "goals"
            case .timeline: "timeline"
            }
        }
    }

    private struct SelectedDay: Identifiable {
        var date: Date
        var id: Date { date }
    }

    var body: some View {
        if let project = store.project(projectID) {
            let metrics = CheckInMetrics(records: store.records(for: projectID))
            ScrollView {
                VStack(spacing: 9) {
                    if !project.activeItems.isEmpty {
                        goalCard(project, metrics: metrics)
                    }
                    calendarCard(project, metrics: metrics)
                    CheckInStatisticsView(project: project, metrics: metrics)
                    CheckInHeatmap(project: project, metrics: metrics)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(CheckInStyle.background)
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("\(project.icon) \(project.name)").font(.headline)
                        if !project.subtitle.isEmpty {
                            Text(project.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        editor = .timeline
                    } label: {
                        Label("时间线", systemImage: "clock").labelStyle(.iconOnly)
                    }
                    Menu {
                        Button("编辑项目", systemImage: "square.and.pencil") { editor = .project }
                        ForEach(project.visibleItems) { item in
                            Button("【\(item.name)】编辑子项目", systemImage: "pencil") { editor = .item(item) }
                        }
                    } label: {
                        Label("更多选项", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(item: $editor) { selection in
                switch selection {
                case .project:
                    CheckInProjectEditor(project: project, isNew: false, onSave: store.save)
                case .item(let item):
                    CheckInItemEditor(
                        item: item, counts: project.itemKind == .count || !project.sumValues,
                        onSave: saveItem
                    )
                case .goals:
                    CheckInGoalsView(projectID: projectID, onSave: saveItem)
                case .timeline:
                    CheckInTimeline(projectID: projectID)
                }
            }
            .sheet(item: $daySelection) { selection in
                CheckInTimeline(projectID: projectID, selectedDay: selection.date)
            }
        } else {
            Color.clear.task { dismiss() }
        }
    }

    private func saveItem(_ item: CheckInItem) -> Bool {
        guard var project = store.project(projectID),
              let index = project.items.firstIndex(where: { $0.id == item.id }) else { return false }
        project.items[index] = item
        return store.save(project)
    }

    private func goalCard(_ project: CheckInProject, metrics: CheckInMetrics) -> some View {
        let goals = project.activeItems.filter { $0.goal.enabled }
        let progress = goals.reduce(0.0) { total, item in
            total + metrics.filtered(item.goal.period, at: .now).goalResult(for: item, in: project).progressRatio
        }
        return Button {
            editor = .goals
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("子项目目标").font(.headline)
                        Text("总体目标达成率").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(goals.isEmpty ? "设置" : (progress / goals.count.double).formatted(.percent.precision(.fractionLength(0))))
                        .font(.headline.monospacedDigit()).foregroundStyle(.tint)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                    ForEach(project.activeItems) { item in
                        let result = metrics.filtered(item.goal.enabled ? item.goal.period : .all, at: .now)
                            .goalResult(for: item, in: project)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.caption.bold())
                            Text(item.goal.enabled ? result.summary(unit: project.goalUnit(for: item)) : "\(result.value.checkInText)\(project.goalUnit(for: item))").font(.caption2)
                            if item.goal.enabled {
                                Text("\(item.goal.rule.title) \(item.goal.target.checkInText)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                ProgressView(value: result.progressRatio).tint(item.color.tint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(item.color.tint.opacity(0.15), in: .rect(cornerRadius: 6))
                    }
                }
            }
            .checkInCard()
        }
        .buttonStyle(.plain)
    }

    private func calendarCard(_ project: CheckInProject, metrics: CheckInMetrics) -> some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let dayTotal = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let recordsByDay = metrics.days
        let completed = metrics.completedDays(for: project)
        return VStack(alignment: .leading, spacing: 8) {
            CheckInDateHeader(period: .month, date: $month, currentTitle: "本月")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(symbols[(index + calendar.firstWeekday - 1) % 7])
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<(leading + dayTotal), id: \.self) { index in
                    if index < leading {
                        Color.clear.frame(height: 34).accessibilityHidden(true)
                    } else if let date = calendar.date(byAdding: .day, value: index - leading, to: start) {
                        let colors = CheckInMetrics(records: recordsByDay[date] ?? []).colors(for: project)
                        Button {
                            daySelection = SelectedDay(date: date)
                        } label: {
                            Text("\(index - leading + 1)")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background {
                                    if !colors.isEmpty, completed[date] == nil {
                                        Circle().strokeBorder(.red, lineWidth: 1.5)
                                    } else if !colors.isEmpty {
                                        CheckInColorMarker(colors: colors).clipShape(Circle())
                                    } else if calendar.isDateInToday(date) {
                                        Circle().strokeBorder(.tint, lineWidth: 1)
                                    }
                                }
                                .foregroundStyle(completed[date] == nil ? Color.primary : .white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(.dateTime.month().day()))
                        .accessibilityValue(colors.isEmpty ? "无记录" : completed[date] == nil ? "目标未达成" : "有记录")
                    }
                }
            }
            Text("项目创建于 \(project.createdAt.formatted(.dateTime.year().month().day()))")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .checkInCard()
    }
}

struct CheckInDateHeader: View {
    var period: CheckInPeriod
    @Binding var date: Date
    var currentTitle: String?

    var body: some View {
        HStack {
            Text(period.label(for: date)).font(.headline)
            Spacer()
            if period != .all {
                if let currentTitle {
                    Button(currentTitle) { date = .now }.font(.caption.bold())
                }
                Button { date = period.offset(date, by: -1) } label: {
                    Label("上一周期", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                Button { date = period.offset(date, by: 1) } label: {
                    Label("下一周期", systemImage: "chevron.right").labelStyle(.iconOnly)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct CheckInGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CheckInStore
    let projectID: UUID
    let onSave: (CheckInItem) -> Bool
    @State private var selectedID: UUID?
    @State private var editor: CheckInItem?
    @State private var offset = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let project = store.project(projectID),
                   let item = project.activeItems.first(where: { $0.id == selectedID }) ?? project.activeItems.first {
                    let metrics = CheckInMetrics(records: store.records(for: projectID))
                    VStack(spacing: 10) {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(project.activeItems) { option in
                                    Button {
                                        selectedID = option.id
                                        offset = 0
                                    } label: {
                                        Label(option.name, systemImage: "circle.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(option.id == item.id ? option.color.tint : .secondary)
                                    .accessibilityAddTraits(option.id == item.id ? .isSelected : [])
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .checkInCard()
                        if item.goal.enabled {
                            history(item, project: project, metrics: metrics)
                        } else {
                            Text("尚未设置目标").checkInCard()
                        }
                    }
                    .padding(14)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("设置目标") { editor = item }
                        }
                    }
                    .sheet(item: $editor) { updated in
                        CheckInItemEditor(item: updated,
                                          counts: project.itemKind == .count || !project.sumValues,
                                          onSave: onSave)
                    }
                }
            }
            .background(CheckInStyle.background)
            .navigationTitle("子项目目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CheckInSheetToolbar(cancel: { dismiss() }) }
        }
    }

    private func history(_ item: CheckInItem, project: CheckInProject, metrics: CheckInMetrics) -> some View {
        let period = item.goal.period
        let count = period == .all ? 1 : 5
        let dates = (0..<count).map { period.offset(.now, by: offset - $0) }
        return VStack(spacing: 10) {
            if let first = dates.first, let last = dates.last, period != .all {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(period.label(for: last)) – \(period.label(for: first))").font(.subheadline.bold())
                        Text("最近 5 个周期 · \(period.title)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { offset -= count } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("更早的目标周期")
                    Button { offset = min(0, offset + count) } label: { Image(systemName: "chevron.right") }
                        .disabled(offset == 0)
                        .accessibilityLabel("更新的目标周期")
                }
                .checkInCard()
            }
            Text("目标  \(period.title) \(item.goal.rule.title) \(item.goal.target.checkInText)\(project.goalUnit(for: item))")
                .font(.subheadline.bold()).foregroundStyle(item.color.tint).checkInCard()
            VStack(spacing: 7) {
                ForEach(dates, id: \.self) { date in
                    let result = metrics.filtered(period, at: date).goalResult(for: item, in: project)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(period.label(for: date)).font(.subheadline.bold())
                            Text(item.goal.rule == .maximum ? result.summary(unit: project.goalUnit(for: item)) : "累计值 " + result.summary(unit: project.goalUnit(for: item)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(result.ratio.formatted(.percent.precision(.fractionLength(0))))
                                .font(.subheadline.bold()).foregroundStyle(item.color.tint)
                            Label(result.achieved ? "已达成" : "未达成", systemImage: result.achieved ? "checkmark.circle" : "circle")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background {
                        GeometryReader { proxy in
                            item.color.tint.opacity(0.24).frame(width: proxy.size.width * result.progressRatio)
                        }
                    }
                    .background(CheckInStyle.background)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
            .checkInCard()
        }
    }
}

struct CheckInTimeline: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CheckInStore
    let projectID: UUID
    var selectedDay: Date?
    @State private var year = Date()
    @State private var adding = false
    @State private var editing: CheckInRecord?
    @State private var deleting: CheckInRecord?

    var body: some View {
        NavigationStack {
            if let project = store.project(projectID) {
                let records = store.records(for: projectID).filter { record in
                    if let selectedDay { return Calendar.current.isDate(record.date, inSameDayAs: selectedDay) }
                    return CheckInPeriod.year.contains(record.date, around: year)
                }
                List {
                    if selectedDay == nil {
                        CheckInDateHeader(period: .year, date: $year, currentTitle: "今年")
                    }
                    if records.isEmpty {
                        Text("暂无记录").foregroundStyle(.secondary)
                    }
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("\(project.icon) \(project.name)").font(.headline)
                                Spacer()
                                Menu {
                                    Button("编辑记录", systemImage: "pencil") { editing = record }
                                    Button("删除记录", systemImage: "trash", role: .destructive) { deleting = record }
                                } label: {
                                    Label("记录选项", systemImage: "ellipsis").labelStyle(.iconOnly)
                                }
                            }
                            ForEach(project.items) { item in
                                if let value = record.values[item.id] {
                                    HStack(spacing: 6) {
                                        Text(item.name).bold().foregroundStyle(item.color.tint)
                                        Text("\(project.metricValue(value).checkInText)\(project.unit(for: item))")
                                    }
                                    .font(.subheadline)
                                }
                            }
                            if !record.note.isEmpty { Text(record.note).font(.subheadline) }
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(record.photos) { photo in
                                        if let image = UIImage(data: photo.jpeg) {
                                            Image(uiImage: image)
                                                .resizable().scaledToFill()
                                                .frame(width: 100, height: 92)
                                                .clipShape(.rect(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            Text(record.date.formatted(.dateTime.year().month().day().hour().minute()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { deleting = record }
                        }
                    }
                }
                .navigationTitle(selectedDay.map { $0.formatted(.dateTime.month().day()) } ?? "时间线")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    CheckInSheetToolbar(cancel: { dismiss() })
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("新增记录", systemImage: "plus") { adding = true }.labelStyle(.iconOnly)
                    }
                }
                .sheet(isPresented: $adding) {
                    CheckInRecordEditor(initialProjectID: projectID, initialDate: selectedDay)
                }
                .sheet(item: $editing) { record in
                    CheckInRecordEditor(existing: record)
                }
                .alert("删除这条打卡记录？", isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }
                ), presenting: deleting) { record in
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) { store.delete(record) }
                }
            }
        }
    }
}
