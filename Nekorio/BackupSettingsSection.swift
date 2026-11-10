import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsSection: View {
    @EnvironmentObject private var store: CheckInStore
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var notice: Notice?

    private struct Notice: Identifiable {
        let title: String
        let message: String
        var id: String { title }
    }

    var body: some View {
        Section {
            Button("导出备份", systemImage: "square.and.arrow.up", action: export)
            Button("导入备份", systemImage: "square.and.arrow.down") { importing = true }
        } header: {
            Text("数据备份")
        } footer: {
            Text("备份包含打卡项目、记录、照片和主题色。导入会合并本机数据，同一条数据保留更新的版本。")
        }
        .fileExporter(
            isPresented: $exporting,
            document: document,
            contentType: .json,
            defaultFilename: "Nekorio-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        ) { result in
            document = nil
            if case .failure(let error) = result { showError(error, title: "导出失败") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                var readError: NSError?
                var contents: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
                    contents = Result { try Data(contentsOf: coordinatedURL) }
                }
                if let readError { throw readError }
                try store.importBackup(contents.get())
                notice = Notice(title: "导入完成", message: "备份已与本机数据合并。")
            } catch {
                showError(error, title: "导入失败")
            }
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("好")))
        }
    }

    private func export() {
        do {
            document = BackupDocument(data: try store.exportBackup())
            exporting = true
        } catch {
            showError(error, title: "导出失败")
        }
    }

    private func showError(_ error: Error, title: String) {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError { return }
        notice = Notice(title: title, message: store.storageError ?? "请确认文件是有效的 Nekorio 备份，并且应用支持其格式版本。")
    }
}

private struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
