import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class CheckInStore: ObservableObject {
    @Published private(set) var archive = CheckInArchive()
    @Published private(set) var storageError: String?
    private let archiveURL: URL
    private var localArchiveReadable = true

    init() {
        archiveURL = URL.applicationSupportDirectory
            .appending(path: "Nekorio/check-in.json", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
        do {
            archive = try CheckInArchive.decode(Data(contentsOf: archiveURL))
        } catch {
            localArchiveReadable = false
            storageError = "无法读取打卡数据。原文件已保留。"
        }
    }

    var theme: AppTheme { archive.themePreference?.theme ?? .lightPink }

    func saveTheme(_ theme: AppTheme) -> Bool {
        var next = archive
        next.themePreference = AppThemePreference(theme: theme, modifiedAt: Date())
        guard persist(next) else { return false }
        return true
    }

    var projects: [CheckInProject] { archive.projects.filter { $0.deletedAt == nil } }

    func project(_ id: UUID) -> CheckInProject? {
        projects.first { $0.id == id }
    }

    func records(for id: UUID) -> [CheckInRecord] {
        archive.records.filter { $0.projectID == id && !$0.deleted }.sorted { $0.date > $1.date }
    }

    @discardableResult
    func save(_ project: CheckInProject) -> Bool {
        var updated = project
        updated.modifiedAt = Date()
        var next = archive
        next.merge(CheckInArchive(projects: [updated]))
        guard persist(next) else { return false }
        return true
    }

    @discardableResult
    func save(_ record: CheckInRecord) -> Bool {
        var updated = record
        updated.modifiedAt = Date()
        var next = archive
        next.merge(CheckInArchive(records: [updated]))
        guard persist(next) else { return false }
        return true
    }

    func deleteProject(_ id: UUID) -> Bool {
        guard var project = project(id) else { return false }
        project.deletedAt = .now
        guard save(project) else { return false }
        Task { try? await CheckInReminder.update(project, requestPermission: false) }
        return true
    }

    func delete(_ record: CheckInRecord) {
        var tombstone = record
        tombstone.deleted = true
        tombstone.values = [:]
        tombstone.note = ""
        tombstone.photos = []
        save(tombstone)
    }

    private func persist(_ next: CheckInArchive) -> Bool {
        guard localArchiveReadable else { return false }
        do {
            try FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try next.encoded().write(to: archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            storageError = nil
            return true
        } catch {
            storageError = "打卡数据写入失败，请重试。"
            return false
        }
    }

    func exportBackup() throws -> Data {
        guard localArchiveReadable else { throw CocoaError(.fileReadCorruptFile) }
        return try archive.encoded()
    }

    func importBackup(_ data: Data) throws {
        let imported = try CheckInArchive.decode(data)
        guard imported.isValidBackup else { throw CocoaError(.fileReadCorruptFile) }

        let previous = archive
        var merged = previous
        merged.merge(imported)
        guard localArchiveReadable else { throw CocoaError(.fileReadCorruptFile) }
        guard merged != previous else { return }
        guard persist(merged) else { throw CocoaError(.fileWriteUnknown) }
        let oldProjects = Dictionary(previous.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for project in merged.projects where oldProjects[project.id] != project {
            Task { try? await CheckInReminder.update(project, requestPermission: false) }
        }
    }
}

enum CheckInReminder {
    static func update(_ project: CheckInProject, requestPermission: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        let id = "check-in.\(project.id.uuidString)"
        guard project.deletedAt == nil, project.reminderEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }
        if requestPermission {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw CocoaError(.userCancelled)
            }
        } else {
            let settings = await center.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = "打卡提醒"
        content.body = "\(project.icon) \(project.name)"
        content.sound = .default
        let time = DateComponents(hour: project.reminderHour, minute: project.reminderMinute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
