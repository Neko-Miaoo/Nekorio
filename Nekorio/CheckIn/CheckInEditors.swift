import ImageIO
import PhotosUI
import SwiftUI

struct CheckInProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CheckInStore
    @State var project: CheckInProject
    var isNew = true
    let onSave: (CheckInProject) -> Bool
    @State private var itemEditor: CheckInItem?
    @State private var message: String?
    @State private var confirmingDeletion = false

    private let emoji = ["⭐️", "🏋️", "📚", "💧", "🏃", "💪", "🧘", "🎨", "🎵", "🌱", "💤", "✅"]

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: project.reminderHour, minute: project.reminderMinute, second: 0, of: .now) ?? .now
        } set: { value in
            let components = Calendar.current.dateComponents([.hour, .minute], from: value)
            project.reminderHour = components.hour ?? 20
            project.reminderMinute = components.minute ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Menu {
                            ForEach(emoji, id: \.self) { symbol in
                                Button(symbol) { project.icon = symbol }
                            }
                        } label: {
                            Text(project.icon)
                                .font(.largeTitle)
                                .frame(width: 54, height: 54)
                                .background(project.color.tint.opacity(0.13), in: Circle())
                                .accessibilityLabel("选择项目图标")
                        }
                        VStack {
                            TextField("项目名称", text: $project.name)
                            Divider()
                            TextField("项目描述", text: $project.subtitle)
                        }
                    }
                    TextField("自定义表情或图标文字", text: $project.icon)
                    CheckInColorPicker(title: "项目颜色", selection: $project.color)
                }
                Section {
                    TextField("所属分组", text: $project.group)
                    Toggle("时间提醒", isOn: $project.reminderEnabled)
                    if project.reminderEnabled {
                        DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    Picker("首页显示", selection: $project.showRecordCount) {
                        Text("打卡天数").tag(false)
                        Text("打卡次数").tag(true)
                    }
                    LabeledContent("目标天数") {
                        TextField("天数", value: $project.targetDays, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Toggle("启用子项目", isOn: $project.itemsEnabled)
                    if project.itemsEnabled {
                        Picker("子项目类型", selection: $project.itemKind) {
                            ForEach(CheckInItemKind.allCases) { Text($0.title).tag($0) }
                        }
                        if project.itemKind == .number {
                            Toggle("累加子项目数值", isOn: $project.sumValues)
                        }
                    }
                } footer: {
                    Text("关闭累加时，子项目进度和目标按填写次数计算。")
                }
                if project.itemsEnabled {
                    Section("已添加的子项目") {
                        ForEach(project.visibleItems) { item in
                            Button {
                                itemEditor = item
                            } label: {
                                HStack {
                                    Label(item.name, systemImage: "circle.fill").foregroundStyle(item.color.tint)
                                    Spacer()
                                    if item.goal.enabled {
                                        Text("\(item.goal.period.title) \(item.goal.rule.title) \(item.goal.target.checkInText)\(project.goalUnit(for: item))")
                                            .font(.caption)
                                    }
                                    Image(systemName: "square.and.pencil")
                                }
                            }
                        }
                        Button("添加子项目", systemImage: "plus") {
                            itemEditor = CheckInItem(color: CheckInColor.allCases[project.items.count % CheckInColor.allCases.count])
                        }
                    }
                }
                if !isNew {
                    Section {
                        Button("删除主项目", role: .destructive) { confirmingDeletion = true }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "新增主项目" : "编辑项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CheckInSheetToolbar(cancel: { dismiss() }, save: save, disabled: !valid)
            }
            .sheet(item: $itemEditor) { item in
                CheckInItemEditor(
                    item: item,
                    isNew: !project.items.contains { $0.id == item.id },
                    counts: project.itemKind == .count || !project.sumValues
                ) { updated in
                    if updated.deletedAt != nil, var saved = store.project(project.id),
                       let index = saved.items.firstIndex(where: { $0.id == updated.id }) {
                        saved.items[index].deletedAt = updated.deletedAt
                        guard store.save(saved) else { return false }
                    }
                    if let index = project.items.firstIndex(where: { $0.id == updated.id }) {
                        project.items[index] = updated
                    } else {
                        project.items.append(updated)
                    }
                    return true
                }
            }
            .alert("删除主项目？", isPresented: $confirmingDeletion) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if store.deleteProject(project.id) { dismiss() }
                    else { message = store.storageError ?? "无法删除项目。" }
                }
            } message: {
                Text("「\(project.name)」及其记录将从打卡界面移除。")
            }
            .alert("项目设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var valid: Bool {
        !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && project.targetDays > 0
    }

    private func save() {
        var draft = project
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.group = draft.group.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.group.isEmpty { draft.group = "日常" }
        draft.icon = String(draft.icon.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        if draft.icon.isEmpty { draft.icon = "⭐️" }
        guard onSave(draft) else {
            message = store.storageError ?? "无法保存项目。"
            return
        }
        Task {
            do {
                try await CheckInReminder.update(draft, requestPermission: draft.reminderEnabled)
                dismiss()
            } catch {
                message = "项目已保存。通知未安排，请检查系统通知权限。"
            }
        }
    }
}

struct CheckInItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CheckInStore
    @State var item: CheckInItem
    var isNew = false
    var counts = false
    let onSave: (CheckInItem) -> Bool
    @State private var saveFailed = false
    @State private var confirmingDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section("子项目信息") {
                    HStack {
                        TextField("名称", text: $item.name)
                        Menu("选一个") {
                            ForEach(["跑步", "深蹲", "俯卧撑", "卧推", "阅读", "饮水"], id: \.self) { name in
                                Button(name) { item.name = name }
                            }
                        }
                    }
                    if !counts {
                        HStack {
                            TextField("单位", text: $item.unit)
                            Menu("选一个") {
                                ForEach(["次", "个", "分钟", "公里", "毫升", "页", "本"], id: \.self) { unit in
                                    Button(unit) { item.unit = unit }
                                }
                            }
                        }
                    }
                    CheckInColorPicker(title: "颜色", selection: $item.color)
                }
                Section {
                    Toggle("子项目目标", isOn: $item.goal.enabled)
                    if item.goal.enabled {
                        Picker("目标周期", selection: $item.goal.period) {
                            ForEach(CheckInPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Picker("达标条件", selection: $item.goal.rule) {
                                ForEach(GoalRule.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            TextField("目标", value: $item.goal.target, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(counts ? "次" : item.unit).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("子项目目标")
                } footer: {
                    Text(item.goal.rule == .maximum
                         ? "按天核对，只有当天有记录且合计不超过上限才算达成。"
                         : "目标单位跟随子项目单位，按次数统计时使用「次」。")
                }
                if !isNew {
                    Section {
                        Button("删除子项目", role: .destructive) { confirmingDeletion = true }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "新增子项目" : "编辑子项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CheckInSheetToolbar(
                    cancel: { dismiss() }, save: save,
                    disabled: item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (item.goal.enabled && (!item.goal.target.isFinite || item.goal.target <= 0))
                )
            }
            .alert("删除子项目？", isPresented: $confirmingDeletion) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    var deleted = item
                    deleted.deletedAt = .now
                    if onSave(deleted) { dismiss() } else { saveFailed = true }
                }
            } message: {
                Text("「\(item.name)」将从打卡选项和目标中移除，历史记录仍可查看。")
            }
            .alert("保存失败", isPresented: $saveFailed) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.storageError ?? "无法保存子项目。")
            }
        }
    }

    private func save() {
        var draft = item
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.unit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.unit.isEmpty { draft.unit = "次" }
        if onSave(draft) { dismiss() } else { saveFailed = true }
    }
}

struct CheckInRecordEditor: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CheckInStore
    var initialProjectID: UUID?
    var initialDate: Date?
    var existing: CheckInRecord?
    @State private var projectID: UUID?
    @State private var date = Date()
    @State private var values: [UUID: String] = [:]
    @State private var counts: Set<UUID> = []
    @State private var note = ""
    @State private var photos: [CheckInPhoto] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var addingProject = false
    @State private var loadingPhotos = false
    @State private var message: String?

    private var project: CheckInProject? { projectID.flatMap(store.project) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let project {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("记录日期").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                DatePicker("日期", selection: $date, displayedComponents: .date).labelsHidden()
                                DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute).labelsHidden()
                            }
                        }
                        if !project.activeItems.isEmpty {
                            Divider()
                            Text("子项目").font(.caption).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(project.activeItems) { entry(for: $0, in: project) }
                            }
                        }
                        Divider()
                        Text("备注和照片").font(.caption).foregroundStyle(.secondary)
                        noteAndPhotos
                    } else {
                        ContentUnavailableView("先选择主项目", systemImage: "folder",
                                               description: Text("从左上角菜单选择现有项目或新增主项目。"))
                    }
                }
                .padding(16)
            }
            .background(CheckInStyle.card)
            .navigationTitle(existing == nil ? "添加记录" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(existing == nil ? "添加记录" : "编辑记录").font(.headline)
                        if let project {
                            Text("\(project.icon) \(project.name)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("关闭", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                    Menu {
                        ForEach(store.projects) { option in
                            Button("\(option.icon) \(option.name)") { select(option.id) }
                        }
                        Button("新增主项目", systemImage: "plus") { addingProject = true }
                    } label: {
                        Label("选择主项目", systemImage: "chevron.down.circle").labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) { Label("保存", systemImage: "checkmark").labelStyle(.iconOnly) }
                        .disabled(project == nil || loadingPhotos)
                }
            }
            .sheet(isPresented: $addingProject) {
                CheckInProjectEditor(project: CheckInProject()) { updated in
                    guard store.save(updated) else { return false }
                    select(updated.id)
                    return true
                }
            }
            .onAppear(perform: prepare)
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                loadingPhotos = true
                Task { await loadPhotos(items) }
            }
            .alert("打卡记录", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func entry(for item: CheckInItem, in project: CheckInProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.caption.bold())
                .padding(5)
                .foregroundStyle(.white)
                .background(item.color.tint, in: .rect(cornerRadius: 4))
            if project.itemKind == .count {
                Toggle("记录一次", isOn: Binding {
                    counts.contains(item.id)
                } set: { checked in
                    if checked { counts.insert(item.id) } else { counts.remove(item.id) }
                })
                .font(.caption)
            } else {
                HStack {
                    TextField("数值", text: Binding(
                        get: { values[item.id, default: ""] },
                        set: { values[item.id] = $0 }
                    ))
                    .accessibilityLabel("\(item.name)数值")
                    .keyboardType(.decimalPad)
                    Text(item.unit).font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
                .background(CheckInStyle.card, in: .rect(cornerRadius: 4))
            }
        }
        .checkInCard(padding: 6)
        .background(CheckInStyle.field, in: .rect(cornerRadius: 7))
    }

    private var noteAndPhotos: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("你还可以输入备注…", text: $note, axis: .vertical)
                .lineLimit(3...7)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        if let image = UIImage(data: photo.jpeg) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 86)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.removeAll { $0.id == photo.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.65))
                                    }
                                    .padding(4)
                                    .accessibilityLabel("移除照片")
                                }
                        }
                    }
                    if photos.count < 8 {
                        PhotosPicker(selection: $selection, maxSelectionCount: 8 - photos.count, matching: .images) {
                            VStack(spacing: 5) {
                                if loadingPhotos { ProgressView() } else { Image(systemName: "plus") }
                                Text("添加照片").font(.caption)
                            }
                            .frame(width: 90, height: 86)
                            .background(theme.color.opacity(0.14), in: .rect(cornerRadius: 8))
                        }
                        .disabled(loadingPhotos)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .background(CheckInStyle.background, in: .rect(cornerRadius: 12))
    }

    private func prepare() {
        guard projectID == nil else { return }
        projectID = existing?.projectID ?? initialProjectID ?? store.projects.first?.id
        date = existing?.date ?? initialDate ?? .now
        if let existing {
            values = existing.values.mapValues { $0.formatted(.number.grouping(.never)) }
            counts = Set(existing.values.keys)
            note = existing.note
            photos = existing.photos
        }
    }

    private func select(_ id: UUID) {
        guard projectID != id else { return }
        projectID = id
        values = [:]
        counts = []
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var failed = false
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1280
                  ] as CFDictionary),
                  let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.75) else {
                failed = true
                continue
            }
            photos.append(CheckInPhoto(jpeg: jpeg))
        }
        if failed { message = "部分照片无法读取，请重新选择。" }
        selection = []
        loadingPhotos = false
    }

    private func save() {
        guard let project else { return }
        var parsed: [UUID: Double] = existing?.projectID == project.id ? existing?.values ?? [:] : [:]
        for item in project.activeItems {
            if project.itemKind == .count {
                parsed[item.id] = counts.contains(item.id) ? parsed[item.id] ?? 1 : nil
            } else {
                let raw = values[item.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty {
                    parsed[item.id] = nil
                } else if let value = try? Double(raw, format: .number, lenient: false), value.isFinite, value >= 0 {
                    parsed[item.id] = value
                } else {
                    message = "「\(item.name)」请输入有效的非负数值。"
                    return
                }
            }
        }
        var updated = existing ?? CheckInRecord(projectID: project.id)
        updated.projectID = project.id
        updated.date = date
        updated.values = parsed
        updated.note = note
        updated.photos = photos
        if store.save(updated) { dismiss() } else { message = store.storageError ?? "无法保存记录。" }
    }
}
