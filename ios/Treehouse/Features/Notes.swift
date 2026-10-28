import SwiftUI

extension NoteNode {
    var outlineChildren: [NoteNode]? { children.isEmpty ? nil : children }
}

struct NotesList: View {
    let api: APIClient
    @State private var notes: [NoteNode] = []
    @State private var loading = true
    @State private var error: String?
    @State private var creating = false
    @State private var search = ""
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Room for an idea.", systemImage: "leaf").font(.title2.bold()).foregroundStyle(TreeTheme.green)
                    Text("Plans, lists, and things worth remembering.").font(.subheadline).foregroundStyle(TreeTheme.muted)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if loading && notes.isEmpty { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            if !loading && notes.isEmpty { EmptyTree(title: "Plant your first idea", subtitle: "Add a page to start your shared notebook.").listRowBackground(Color.clear) }
            Section("Your notebook") {
                if search.isEmpty {
                    OutlineGroup(notes, children: \.outlineChildren) { node in noteLink(node) }
                } else {
                    ForEach(notes.flatMap(\.flattened).filter { $0.path.localizedCaseInsensitiveContains(search) }) { noteLink($0) }
                }
            }.listRowBackground(TreeTheme.paper)
        }.treeList().navigationTitle("Notes").searchable(text: $search, prompt: "Find a page")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New page", systemImage: "square.and.pencil") { creating = true } } }
            .task { notes = api.store.read("notes") ?? []; await refresh() }
            .refreshable { await refresh() }
            .sheet(isPresented: $creating, onDismiss: { Task { await refresh() } }) {
                NoteEditor(api: api, original: nil, initialPath: "")
            }
    }
    private func noteLink(_ node: NoteNode) -> some View {
        NavigationLink {
            NoteDetail(api: api, node: node)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: node.children.isEmpty ? "doc.text" : "folder").foregroundStyle(TreeTheme.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.title).font(.body.weight(.semibold))
                    Text("\(node.updatedBy.capitalized) · \(ServerDate.label(node.updatedAt))").font(.caption).foregroundStyle(TreeTheme.muted)
                }.padding(.vertical, 7)
            }
        }.accessibilityIdentifier("note-\(node.id)")
    }
    private func refresh() async {
        do { notes = try await api.notes(); api.store.write(notes, key: "notes"); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct NoteDetail: View {
    let api: APIClient
    let node: NoteNode
    @State private var note: Note?
    @State private var error: String?
    @State private var editing = false
    @State private var child = false
    @State private var moving = false
    @State private var newPath = ""
    @State private var deleting = false
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let error { ErrorBanner(message: error) }
                if let note {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(note.path).font(.caption.weight(.semibold)).foregroundStyle(TreeTheme.green)
                        Text(note.title).font(.largeTitle.bold())
                        Label("\(note.updatedBy.capitalized) · \(ServerDate.label(note.updatedAt))", systemImage: "clock")
                            .font(.caption).foregroundStyle(TreeTheme.muted)
                    }
                    MarkdownBody(text: note.body).frame(maxWidth: .infinity, alignment: .leading).paperCard()
                    if !node.children.isEmpty {
                        Text("INSIDE THIS PAGE").font(.caption.bold()).tracking(1).foregroundStyle(TreeTheme.muted)
                        ForEach(node.children) { child in
                            NavigationLink { NoteDetail(api: api, node: child) } label: { Label(child.title, systemImage: "doc.text").frame(maxWidth: .infinity, alignment: .leading).paperCard() }
                        }
                    }
                } else if error == nil { ProgressView().frame(maxWidth: .infinity).padding(60) }
            }.padding(20)
        }.background(PaperBackground()).navigationTitle("Page").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "pencil") { editing = true }.disabled(note == nil || busy) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add page inside", systemImage: "doc.badge.plus") { child = true }
                        Button("Rename or move", systemImage: "folder") { newPath = note?.path ?? node.path; moving = true }
                        Button("Delete page", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { Image(systemName: "ellipsis.circle") }.disabled(note == nil || busy)
                }
            }
            .task { note = api.store.read("note-\(node.id)"); await refresh() }
            .refreshable { await refresh() }
            .sheet(isPresented: $editing, onDismiss: { Task { await refresh() } }) {
                if let note { NoteEditor(api: api, original: note, initialPath: note.path) }
            }
            .sheet(isPresented: $child) { NoteEditor(api: api, original: nil, initialPath: (note?.path ?? node.path) + "/") }
            .alert("Rename or move page", isPresented: $moving) {
                TextField("Full page path", text: $newPath)
                Button("Save") { Task { await move() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Use / between parent pages. The destination parent must already exist.") }
            .confirmationDialog("Delete this page\(node.descendants > 0 ? " and its \(node.descendants) nested pages" : "") for everyone?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete page\(node.descendants > 0 ? " and nested pages" : "")", role: .destructive) { Task { await delete() } }
            } message: { Text("This can’t be undone.") }
    }
    private func refresh() async {
        do { note = try await api.note(id: node.id); api.store.write(note, key: "note-\(node.id)"); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func move() async {
        busy = true; defer { busy = false }
        do { try await api.moveNote(path: note?.path ?? node.path, newPath: newPath); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func delete() async {
        busy = true; defer { busy = false }
        do { try await api.deleteNote(path: note?.path ?? node.path, recursive: node.descendants > 0); api.store.remove("note-\(node.id)"); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct NoteDraft: Codable {
    var path: String
    var text: String
    var original: Note?
}

struct NoteEditor: View {
    let api: APIClient
    @State var original: Note?
    let initialPath: String
    @State private var path = ""
    @State private var text = ""
    @State private var error: String?
    @State private var saving = false
    @State private var preview = false
    @State private var loaded = false
    @State private var latest: Note?
    @State private var comparing = false
    @Environment(\.dismiss) private var dismiss
    private var draftKey: String { "note-draft-\(original?.id.description ?? initialPath)" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if original == nil {
                    TextField("Page title or Parent/Title", text: $path).textInputAutocapitalization(.sentences)
                        .padding(16).background(TreeTheme.paper).accessibilityIdentifier("notePath")
                }
                if let error {
                    ErrorBanner(message: error)
                    if latest != nil {
                        Button("Compare with latest version") { comparing = true }.font(.footnote).padding(8)
                    }
                }
                if preview {
                    ScrollView { MarkdownBody(text: text).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    TextEditor(text: $text).scrollContentBackground(.hidden).padding(12)
                        .font(.body.monospaced()).accessibilityIdentifier("noteBody")
                }
                HStack {
                    Label("Draft saved on this iPhone", systemImage: "checkmark.circle").font(.caption)
                    Spacer()
                    Text("\(text.utf16.count.formatted()) / 200,000").font(.caption2.monospacedDigit())
                }.foregroundStyle(TreeTheme.muted).padding(12).background(TreeTheme.paper)
            }.background(PaperBackground()).navigationTitle(original == nil ? "New page" : "Edit page")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { persist(); dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .topBarTrailing) { Button(preview ? "Write" : "Preview") { preview.toggle() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save").bold() } }
                            .disabled(saving || path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf16.count > 200_000)
                            .accessibilityIdentifier("saveNote")
                    }
                }
                .onAppear {
                    guard !loaded else { return }
                    let draft: NoteDraft? = api.store.read(draftKey)
                    path = draft?.path ?? initialPath; text = draft?.text ?? original?.body ?? ""
                    if let savedOriginal = draft?.original { original = savedOriginal }
                    loaded = true
                }
                .onChange(of: text) { _, _ in persist() }
                .onChange(of: path) { _, _ in persist() }
                .interactiveDismissDisabled(saving)
                .sheet(isPresented: $comparing) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Your draft").font(.headline); Text(text).textSelection(.enabled)
                                Divider()
                                Text("Latest on Treehouse").font(.headline); Text(latest?.body ?? "").textSelection(.enabled)
                                Text("Copy any changes you want to keep into your draft. Saving after accepting the latest version will replace its contents with your draft.").font(.footnote).foregroundStyle(TreeTheme.muted)
                                Button("Keep my draft; accept latest as its base") { original = latest; error = nil; persist(); comparing = false }
                            }.padding(20)
                        }.navigationTitle("Compare changes").toolbar { Button("Done") { comparing = false } }
                    }
                }
        }.tint(TreeTheme.green)
    }
    private func persist() {
        guard loaded else { return }
        api.store.write(NoteDraft(path: path, text: text, original: original), key: draftKey)
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            try await api.saveNote(path: path.trimmingCharacters(in: .whitespacesAndNewlines), text: text, original: original)
            api.store.remove(draftKey); dismiss()
        } catch {
            self.error = error.localizedDescription
            if error as? APIError == .conflict, let original { latest = try? await api.note(id: original.id) }
        }
    }
}

struct MarkdownBody: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if text.isEmpty { Text("A little room for an idea.").foregroundStyle(TreeTheme.muted) }
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                if paragraph.hasPrefix("# ") { Text(String(paragraph.dropFirst(2))).font(.title.bold()) }
                else if paragraph.hasPrefix("## ") { Text(String(paragraph.dropFirst(3))).font(.title3.bold()) }
                else if paragraph.hasPrefix("### ") { Text(String(paragraph.dropFirst(4))).font(.headline) }
                else {
                    Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                        .lineSpacing(5)
                }
            }
        }.textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded })
    }
}
