import SwiftUI

struct CheckInView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var store: CheckInStore
    @State private var filter: String?
    @State private var addingRecord = false
    @State private var addingProject = false
    @State private var selectedProjectID: UUID?
    @State private var deleting: CheckInProject?
    @State private var revealedProjectID: UUID?

    private var groups: [String] {
        Array(Set(store.projects.map(\.group))).sorted()
    }

    private var projects: [CheckInProject] {
        store.projects.filter { filter == nil || $0.group == filter }
    }

    var body: some View {
        NavigationStack {
            List {
                groupBar
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14))
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("暂无打卡项目", systemImage: "calendar.badge.checkmark")
                    } description: {
                        Text("创建一个项目，开始记录你的习惯。")
                    } actions: {
                        Button("新增主项目") { addingProject = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(projects) { project in
                    CheckInSwipeRow(
                        project: project,
                        metrics: CheckInMetrics(records: store.records(for: project.id)),
                        revealedProjectID: $revealedProjectID,
                        open: { selectedProjectID = project.id },
                        requestDeletion: { deleting = project }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if let error = store.storageError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CheckInStyle.background)
            .alert("删除主项目？", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), presenting: deleting) { project in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if store.deleteProject(project.id), !groups.contains(project.group) { filter = nil }
                }
            } message: { project in
                Text("「\(project.name)」及其记录将从打卡界面移除。")
            }
            .navigationTitle("打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text("打卡").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingRecord = true
                    } label: {
                        Label("新增记录", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .navigationDestination(item: $selectedProjectID) { id in
                CheckInDetailView(projectID: id)
            }
            .sheet(isPresented: $addingRecord) {
                CheckInRecordEditor()
            }
            .sheet(isPresented: $addingProject) {
                CheckInProjectEditor(project: CheckInProject()) { project in
                    if store.save(project) {
                        filter = nil
                        return true
                    }
                    return false
                }
            }
        }
    }

    private var groupBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                groupButton("全部", value: nil)
                ForEach(groups, id: \.self) { groupButton($0, value: $0) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func groupButton(_ title: String, value: String?) -> some View {
        Button {
            revealedProjectID = nil
            filter = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filter == value ? theme.color : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(filter == value ? Color.white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
}

private struct CheckInSwipeRow: View {
    let project: CheckInProject
    let metrics: CheckInMetrics
    @Binding var revealedProjectID: UUID?
    let open: () -> Void
    let requestDeletion: () -> Void

    @GestureState private var drag: CGFloat = 0
    private let actionWidth: CGFloat = 76

    private var isRevealed: Bool { revealedProjectID == project.id }
    private var revealWidth: CGFloat {
        min(actionWidth, max(0, (isRevealed ? actionWidth : 0) - drag))
    }

    var body: some View {
        CheckInProjectCard(project: project, metrics: metrics)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckInStyle.card)
            .contentShape(Rectangle())
            .simultaneousGesture(cardGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activateCard() }
            .offset(x: -revealWidth)
        .overlay(alignment: .trailing) {
            Button(role: .destructive, action: confirmDeletion) {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("删除").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: revealWidth, alignment: .trailing)
            .clipped()
            .allowsHitTesting(isRevealed && drag == 0)
            .accessibilityHidden(!isRevealed)
        }
        .background(.red)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityAction(named: Text("删除项目"), confirmDeletion)
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($drag) { value, state, _ in
                if abs(value.translation.width) > abs(value.translation.height) {
                    state = value.translation.width
                }
            }
            .exclusively(before: TapGesture())
            .onEnded { gesture in
                switch gesture {
                case .first(let value):
                    let delta = value.translation
                    guard abs(delta.width) > abs(delta.height) else { return }
                    let distance = (isRevealed ? actionWidth : 0) - delta.width
                    setRevealed(distance > actionWidth / 2)
                case .second:
                    activateCard()
                }
            }
    }

    private func activateCard() {
        if revealedProjectID != nil {
            setRevealed(false)
        } else {
            open()
        }
    }

    private func setRevealed(_ revealed: Bool) {
        withAnimation(.easeOut(duration: 0.2)) {
            revealedProjectID = revealed ? project.id : nil
        }
    }

    private func confirmDeletion() {
        setRevealed(false)
        requestDeletion()
    }
}

private struct CheckInProjectCard: View {
    let project: CheckInProject
    let metrics: CheckInMetrics

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(project.icon).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name).font(.subheadline.bold())
                if !project.subtitle.isEmpty {
                    Text(project.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                progressStrip
                if !project.activeItems.isEmpty {
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        itemRow
                        ScrollView(.horizontal) { itemRow }.scrollIndicators(.hidden)
                    }
                }
            }
            progressRing
        }
    }

    private var completedDays: [Date: [CheckInRecord]] { metrics.completedDays(for: project) }

    private var progressStrip: some View {
        let days = completedDays
        let orderedDays = days.keys.sorted()
        let slotCount = 30
        let filled = Int((min(completedDays.count.double / project.targetDays.double, 1) * slotCount.double).rounded(.up))
        return HStack(spacing: 2) {
            ForEach(0..<slotCount, id: \.self) { index in
                if index < filled, !orderedDays.isEmpty {
                    let day = orderedDays[index * orderedDays.count / max(filled, 1)]
                    CheckInColorMarker(colors: CheckInMetrics(records: days[day] ?? []).colors(for: project))
                } else {
                    Capsule().fill(.quaternary)
                }
            }
        }
        .frame(height: 7)
        .accessibilityLabel("项目进度")
        .accessibilityValue("\(completedDays.count) / \(project.targetDays) 天")
    }

    private var itemRow: some View {
        HStack(spacing: 5) {
            ForEach(project.activeItems) { item in
                let result = metrics.filtered(item.goal.enabled ? item.goal.period : .all, at: .now)
                    .goalResult(for: item, in: project)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Circle().fill(item.color.tint).frame(width: 5, height: 5)
                        Text(item.name).font(.caption2.weight(.semibold))
                    }
                    Text(item.goal.enabled ? result.summary(unit: project.goalUnit(for: item)) : "\(result.value.checkInText)\(project.goalUnit(for: item))")
                        .font(.caption2.monospacedDigit())
                    if item.goal.enabled {
                        ProgressView(value: result.progressRatio).tint(item.color.tint)
                    }
                }
                .foregroundStyle(.primary)
                .padding(5)
                .frame(minWidth: 48, alignment: .leading)
                .background(item.color.tint.opacity(0.17), in: .rect(cornerRadius: 5))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var progressRing: some View {
        let tint = project.color.tint
        let progress = min(completedDays.count.double / project.targetDays.double, 1)
        return VStack(spacing: 3) {
            Text("\(completedDays.count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .frame(width: 49, height: 49)
                .background(tint.opacity(0.10), in: Circle())
                .overlay {
                    Circle().stroke(tint.opacity(0.22), lineWidth: 3)
                    Circle().trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            Text("目标 \(project.targetDays) 天").font(.caption2).foregroundStyle(.secondary)
            if project.showRecordCount {
                Text("\(metrics.records.count) 次").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
