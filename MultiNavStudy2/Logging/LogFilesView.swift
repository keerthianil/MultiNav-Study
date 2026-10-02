// LogFilesView.swift
// Lists the study logs in Documents, newest first, with share and delete.

import SwiftUI

struct LogFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// "Route 3 touches" from Route3_20260930_153012_touches.csv.
    var title: String {
        if name == StudyLog.appLogName { return "App log" }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_").map(String.init)
        guard parts.count >= 4, parts[0].hasPrefix("Route"), let kind = parts.last else { return name }
        return "Route \(parts[0].dropFirst("Route".count)) \(kind)"
    }
}

struct LogFilesView: View {
    @State private var files: [LogFile] = []
    @State private var pendingDelete: LogFile?
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if files.isEmpty {
                Text("No log files yet. Open a route to start a session.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(files) { file in
                        LogFileRow(file: file, canDelete: file.name != StudyLog.appLogName) { pendingDelete = file }
                    }
                } header: {
                    Text("Saved logs")
                } footer: {
                    Text("Logs are also in the Files app under On My iPhone, MultiNav Study 2.")
                }
                Section {
                    Button("Delete All Logs", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .navigationTitle("Data Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .refreshable { reload() }
        .alert("Delete this log?", isPresented: Binding(get: { pendingDelete != nil },
                                                        set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let file = pendingDelete { delete([file]) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.name ?? "")
        }
        .alert("Delete all logs?", isPresented: $confirmDeleteAll) {
            Button("Delete All", role: .destructive) { delete(files) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app log is kept.")
        }
    }

    private func reload() {
        StudyLog.shared.flush()
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: StudyLog.documents, includingPropertiesForKeys: keys,
                                                                 options: .skipsHiddenFiles)) ?? []
        files = urls
            .filter { ["csv", "txt"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return LogFile(url: url, size: Int64(values?.fileSize ?? 0),
                               modified: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    private func delete(_ targets: [LogFile]) {
        for file in targets where file.name != StudyLog.appLogName {
            do {
                try FileManager.default.removeItem(at: file.url)
            } catch {
                StudyLog.shared.error("Could not delete \(file.name): \(error.localizedDescription)")
            }
        }
        reload()
    }
}

private struct LogFileRow: View {
    let file: LogFile
    let canDelete: Bool
    let onDelete: () -> Void

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        return "\(file.modified.formatted(date: .abbreviated, time: .shortened)), \(size)"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            ShareLink(item: file.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Share \(file.title)")
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(file.title)")
            }
        }
        .padding(.vertical, 4)
    }
}
