import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct FilesList: View {
    let api: APIClient
    @State private var files: [TreehouseFile] = []
    @State private var loading = true
    @State private var error: String?
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var search = ""
    @State private var selected: TreehouseFile?
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Keep it here.", systemImage: "tray").font(.title2.bold()).foregroundStyle(TreeTheme.green)
                    Text("Photos, useful bits, and things to come back to.").font(.subheadline).foregroundStyle(TreeTheme.muted)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if loading || uploading { HStack { ProgressView(); Text(uploading ? "Uploading to Treehouse…" : "Opening the cupboard…").font(.caption) }.listRowBackground(Color.clear) }
            if !loading && files.isEmpty { EmptyTree(title: "A place for your things", subtitle: "Add a photo or document to share.", symbol: "folder").listRowBackground(Color.clear) }
            Section("Shared files") {
                ForEach(files.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { file in
                    Button { selected = file } label: {
                        HStack(spacing: 14) {
                            Image(systemName: file.symbol).font(.title2).foregroundStyle(TreeTheme.green)
                                .frame(width: 46, height: 52).background(TreeTheme.softGreen, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(file.name).font(.body.weight(.semibold)).foregroundStyle(TreeTheme.ink)
                                Text("\(file.formattedSize) · \(file.uploadedBy.capitalized)").font(.caption).foregroundStyle(TreeTheme.muted)
                                if !file.description.isEmpty { Text(file.description).font(.caption).foregroundStyle(TreeTheme.muted).lineLimit(2) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(TreeTheme.muted)
                        }.padding(.vertical, 7)
                    }.accessibilityIdentifier("file-\(file.id)")
                }
            }.listRowBackground(TreeTheme.paper)
            Text("Up to 25 MB per file. Shared with everyone in your Treehouse.").font(.caption).foregroundStyle(TreeTheme.muted).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }.treeList().navigationTitle("Files").searchable(text: $search, prompt: "Find a file")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        PhotosPicker(selection: $photo, matching: .images) { Label("Photo library", systemImage: "photo") }
                        Button("Choose file", systemImage: "doc") { importing = true }
                    } label: { Image(systemName: "plus") }.disabled(uploading).accessibilityLabel("Upload file")
                }
            }
            .task { files = api.store.read("files") ?? []; await refresh() }
            .refreshable { await refresh() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                Task { do { try await upload(PendingUpload.read(result.get())) } catch { self.error = error.localizedDescription } }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw APIError.message("Couldn’t load this photo.") }
                        let type = item.supportedContentTypes.first ?? .jpeg
                        try await upload(PendingUpload(name: "Photo-\(UUID().uuidString.prefix(8)).\(type.preferredFilenameExtension ?? "jpg")",
                                                       contentType: type.preferredMIMEType ?? "image/jpeg", data: data))
                    } catch { self.error = error.localizedDescription }
                }
            }
            .sheet(item: $selected, onDismiss: { Task { await refresh() } }) { FileDetail(api: api, file: $0) }
    }
    private func refresh() async {
        do { files = try await api.files(); api.store.write(files, key: "files"); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
        loading = false
    }
    private func upload(_ file: PendingUpload) async throws {
        uploading = true; defer { uploading = false }
        _ = try await api.upload(file); await refresh()
    }
}

struct FileDetail: View {
    let api: APIClient
    let file: TreehouseFile
    @State private var url: URL?
    @State private var text: String?
    @State private var error: String?
    @State private var deleting = false
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error { ErrorBanner(message: error) }
                if let url {
                    if file.isImage { AuthenticatedImage(api: api, file: file).padding(20).frame(maxHeight: .infinity) }
                    else if let text { ScrollView { Text(text).font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) } }
                    else if file.contentType == "application/pdf" { LocalDocumentPreview(url: url) }
                    else { EmptyTree(title: "Ready to share", subtitle: "Save this file or open it in another app.", symbol: file.symbol) }
                    VStack(alignment: .leading, spacing: 14) {
                        Text(file.name).font(.headline)
                        Text("\(file.formattedSize) · Shared by \(file.uploadedBy.capitalized)").font(.caption).foregroundStyle(TreeTheme.muted)
                        ShareLink(item: url) { Label("Share or save file", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(6) }
                            .buttonStyle(.borderedProminent).foregroundStyle(TreeTheme.paper)
                    }.padding(20).background(TreeTheme.paper)
                } else if error == nil { Spacer(); ProgressView("Opening file…"); Spacer() }
                else { Button("Try again") { Task { await load() } }.padding(); Spacer() }
            }.background(PaperBackground()).navigationTitle("File").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Delete file", systemImage: "trash", role: .destructive) { deleting = true }.disabled(busy) }
                }
                .task { await load() }
                .confirmationDialog("Delete \(file.name) for everyone?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete file", role: .destructive) {
                        Task {
                            busy = true; defer { busy = false }
                            do { try await api.deleteFile(id: file.id); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                } message: { Text("Messages stay, but their attachment will be removed. This can’t be undone.") }
        }.tint(TreeTheme.green)
    }
    private func load() async {
        error = nil
        do {
            let loaded = try await api.download(file)
            if file.contentType == "text/plain" || file.contentType == "text/markdown" { text = try String(contentsOf: loaded, encoding: .utf8) }
            url = loaded
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct LocalDocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
