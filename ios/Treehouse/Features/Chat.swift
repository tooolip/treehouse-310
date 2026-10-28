import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct ChannelList: View {
    let api: APIClient
    @State private var channels: [Channel] = []
    @State private var error: String?
    @State private var loading = true
    @State private var newChannel = false
    @State private var channelName = ""
    @State private var path: [String] = []
    @Environment(\.scenePhase) private var phase
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Come on up.").font(.system(size: 30, weight: .bold))
                        Text("There’s always room for a little conversation.").font(.subheadline).foregroundStyle(TreeTheme.muted)
                    }
                    Spacer(minLength: 0)
                    TreehouseArt().frame(width: 74, height: 82)
                }.padding(.top, 8)
                if let error { ErrorBanner(message: error) }
                HStack {
                    Text("YOUR CHANNELS").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(TreeTheme.muted)
                    Spacer()
                    Text("\(channels.count)").font(.caption.monospacedDigit()).foregroundStyle(TreeTheme.muted)
                }
                if loading && channels.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                if !loading && channels.isEmpty {
                    EmptyTree(title: "It’s quiet up here", subtitle: "Start with general, or create a channel.")
                    channelCard(Channel(channel: "general", messages: 0, threads: 0, lastMessageAt: "", unread: 0))
                }
                ForEach(channels) { channel in channelCard(channel) }
                HStack(spacing: 8) {
                    Image(systemName: "leaf")
                    Text("A shared space. A little less noise.")
                }.font(.footnote).foregroundStyle(TreeTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.padding(20)
        }.background(PaperBackground()).navigationTitle("Treehouse").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { ChannelView(api: api, channel: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("New channel", systemImage: "plus") { newChannel = true } } }
            .alert("A new conversation", isPresented: $newChannel) {
                TextField("Channel name", text: $channelName).textInputAutocapitalization(.never)
                Button("Open channel") {
                    let cleaned = channelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "#", with: "")
                    guard cleaned.range(of: "^[a-z0-9][a-z0-9_-]{0,49}$", options: .regularExpression) != nil else {
                        error = "Channel names use letters, numbers, - and _, up to 50 characters."; return
                    }
                    path.append(cleaned); channelName = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("A channel appears for everyone after its first message.") }
            .navigationDestination(isPresented: Binding(get: { !path.isEmpty }, set: { if !$0 { path = [] } })) {
                if let name = path.last { ChannelView(api: api, channel: name) }
            }
            .refreshable { await refresh() }
            .task(id: "\(phase)-\(session.selectedTab)") {
                if channels.isEmpty { channels = api.store.read("channels") ?? [] }
                guard phase == .active, session.selectedTab == "chat" else { return }
                repeat {
                    await refresh()
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                } while !Task.isCancelled
            }
    }
    private func channelCard(_ channel: Channel) -> some View {
        NavigationLink(value: channel.channel) {
            HStack(spacing: 14) {
                Image(systemName: "number").font(.title2.weight(.medium)).foregroundStyle(TreeTheme.green)
                    .frame(width: 48, height: 48).background(TreeTheme.softGreen, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.channel).font(.headline).foregroundStyle(TreeTheme.ink)
                    Text("\(channel.threads) \(channel.threads == 1 ? "thread" : "threads") · \(channel.messages) \(channel.messages == 1 ? "message" : "messages")")
                        .font(.caption).foregroundStyle(TreeTheme.muted)
                }
                Spacer(minLength: 4)
                if channel.unread > 0 {
                    Text("\(channel.unread)").font(.caption.bold()).foregroundStyle(TreeTheme.paper)
                        .padding(.horizontal, 9).padding(.vertical, 5).background(TreeTheme.green, in: Capsule())
                        .accessibilityLabel("\(channel.unread) unread")
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(TreeTheme.muted)
            }.paperCard()
        }.buttonStyle(.plain).accessibilityIdentifier("channel-\(channel.channel)")
    }
    private func refresh() async {
        do {
            channels = try await api.channels(); error = nil
            api.store.write(channels, key: "channels")
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct ChannelView: View {
    let api: APIClient
    let channel: String
    var body: some View { ConversationView(api: api, channel: channel, root: nil) }
}

struct ConversationView: View {
    let api: APIClient
    let channel: String
    let root: ChatMessage?
    @State private var messages: [ChatMessage] = []
    @State private var files: [TreehouseFile] = []
    @State private var loading = true
    @State private var error: String?
    @State private var text = ""
    @State private var pending: PendingUpload?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var sending = false
    @State private var picking = false
    @State private var active = false
    @State private var scrollTarget: Int?
    @State private var selectedFile: TreehouseFile?
    @State private var ambiguousPost = false
    @State private var needsSendConfirmation = false
    @FocusState private var composing: Bool
    @Environment(\.scenePhase) private var phase
    @Environment(AppSession.self) private var session
    private var cacheKey: String { "messages-\(channel)-\(root?.id ?? 0)" }
    private var draftKey: String { "draft-\(channel)-\(root?.id ?? 0)" }
    private var roots: [ChatMessage] { messages.filter { $0.parentId == nil } }
    private var displayed: [ChatMessage] {
        if let root { return [messages.first(where: { $0.id == root.id }) ?? root] + messages.filter { $0.parentId == root.id } }
        return roots
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error { ErrorBanner(message: error) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if root == nil {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("# \(channel)").font(.title2.bold())
                                Text("A good place to leave a little hello.").font(.subheadline).foregroundStyle(TreeTheme.muted)
                            }.padding(.vertical, 10)
                        }
                        if loading && messages.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(30) }
                        if !loading && displayed.isEmpty { EmptyTree(title: "Start something good", subtitle: "Send the first message in this channel.", symbol: "bubble.left") }
                        if messages.count >= 200 {
                            Text("Showing the latest 200 messages. Older history is available on Treehouse through MCP.")
                                .font(.caption).foregroundStyle(TreeTheme.muted)
                        }
                        ForEach(displayed) { message in
                            VStack(alignment: .leading, spacing: 12) {
                                MessageRow(api: api, message: message, files: files) { selectedFile = $0 }
                                if root == nil {
                                    NavigationLink {
                                        ConversationView(api: api, channel: channel, root: message)
                                    } label: {
                                        Label((message.replyCount ?? 0) == 0 ? "Reply" : "\(message.replyCount!) \(message.replyCount == 1 ? "reply" : "replies")", systemImage: "bubble.left")
                                            .font(.caption.weight(.semibold)).padding(.vertical, 5)
                                    }.accessibilityIdentifier("thread-\(message.id)")
                                }
                            }.paperCard().id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(18)
                }.scrollDismissesKeyboard(.interactively)
                    .refreshable { await refresh() }
                    .onChange(of: scrollTarget) { _, value in
                        if value != nil { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
            }
            composer
        }.background(PaperBackground()).navigationTitle(root == nil ? channel : "Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    Button("Mark channel read", systemImage: "checkmark.bubble") {
                        Task { do { try await api.markRead(channel: channel) } catch { self.error = error.localizedDescription } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            } }
            .onAppear {
                active = true
                text = api.store.read(draftKey) ?? ""
                if messages.isEmpty { messages = api.store.read(cacheKey) ?? [] }
            }
            .onDisappear { active = false }
            .onChange(of: text) { _, value in api.store.write(value, key: draftKey) }
            .task(id: "\(phase)-\(session.selectedTab)-\(active)") {
                guard phase == .active, session.selectedTab == "chat", active else { return }
                repeat {
                    await refresh()
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                } while !Task.isCancelled
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                do { pending = try PendingUpload.read(result.get()); error = nil }
                catch { self.error = error.localizedDescription }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    picking = true; defer { picking = false; photo = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw APIError.message("Couldn’t load this photo.") }
                        guard data.count <= APIClient.maxFileSize else { throw APIError.message("Files can be up to 25 MB.") }
                        let type = item.supportedContentTypes.first ?? .jpeg
                        pending = PendingUpload(name: "Photo-\(UUID().uuidString.prefix(8)).\(type.preferredFilenameExtension ?? "jpg")",
                                                contentType: type.preferredMIMEType ?? "image/jpeg", data: data)
                    } catch { self.error = error.localizedDescription }
                }
            }
            .sheet(item: $selectedFile) { FileDetail(api: api, file: $0) }
            .confirmationDialog("The last send may have reached Treehouse. Check the thread before sending again.", isPresented: $ambiguousPost, titleVisibility: .visible) {
                Button("Send again") { needsSendConfirmation = false; Task { await send() } }
                Button("Check for my message") { Task { await refresh() } }
            }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pending {
                HStack {
                    Label(pending.name, systemImage: "paperclip").font(.caption).lineLimit(1)
                    Spacer()
                    Button("Remove attachment", systemImage: "xmark.circle.fill") { self.pending = nil }
                        .labelStyle(.iconOnly).disabled(sending)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Photo library", systemImage: "photo") }
                    Button("Choose file", systemImage: "doc") { importing = true }
                } label: { Image(systemName: "plus.circle").font(.title2).frame(width: 34, height: 44) }
                    .disabled(sending || picking).accessibilityLabel("Add attachment")
                TextField(root == nil ? "Start a thread…" : "Write a reply…", text: $text, axis: .vertical)
                    .lineLimit(1...5).padding(12).background(TreeTheme.background, in: RoundedRectangle(cornerRadius: 16))
                    .focused($composing).disabled(sending).accessibilityIdentifier("messageInput")
                Button {
                    if needsSendConfirmation { ambiguousPost = true }
                    else { Task { await send() } }
                } label: {
                    if sending || picking { ProgressView().frame(width: 42, height: 42) }
                    else { Image(systemName: "arrow.up").font(.headline).frame(width: 42, height: 42).background(TreeTheme.green, in: Circle()).foregroundStyle(TreeTheme.paper) }
                }.disabled(sending || picking || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending == nil) || text.utf16.count > 10_000)
                    .accessibilityLabel(root == nil ? "Send message" : "Send reply").accessibilityIdentifier("sendMessage")
            }
            if text.utf16.count > 9_000 { Text("\(text.utf16.count) / 10,000").font(.caption).foregroundStyle(text.utf16.count > 10_000 ? .red : TreeTheme.muted) }
        }.padding(12).background(TreeTheme.paper).overlay(alignment: .top) { Divider() }
    }
    private func refresh() async {
        do {
            let result = try await api.messages(channel: channel, thread: root?.id)
            try Task.checkCancellation()
            messages = result; api.store.write(result, key: cacheKey)
            files = (try? await api.files()) ?? files
            error = nil
        } catch is CancellationError {} catch { self.error = "Couldn’t refresh. \(error.localizedDescription) Your saved messages and draft are still here." }
        loading = false
    }
    private func send() async {
        guard !sending else { return }
        sending = true; error = nil
        defer { sending = false }
        var posting = false
        do {
            if let upload = pending, upload.uploaded == nil {
                let uploaded = try await api.upload(upload)
                pending?.uploaded = uploaded
            }
            posting = true
            let message = try await api.post(text: text, channel: channel, replyTo: root?.id, fileId: pending?.uploaded?.id)
            messages.append(message)
            text = ""; pending = nil; composing = false
            needsSendConfirmation = false
            api.store.remove(draftKey)
            await refresh(); scrollTarget = message.id
        } catch is CancellationError {} catch {
            if posting, (error as? URLError) != nil {
                needsSendConfirmation = true
                self.error = "This message may have reached Treehouse. Refresh and check before sending again. Your draft is saved."
            } else { self.error = error.localizedDescription }
        }
    }
}

struct MessageRow: View {
    let api: APIClient
    let message: ChatMessage
    let files: [TreehouseFile]
    let openFile: (TreehouseFile) -> Void
    private var legacyImages: [TreehouseFile] {
        var rest = message.text
        return files.filter(\.isImage).sorted { $0.name.count > $1.name.count }.filter {
            guard $0.id != message.fileId, rest.contains($0.name) else { return false }
            rest = rest.replacingOccurrences(of: $0.name, with: "")
            return true
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(message.via == "claude" ? "✳︎" : String(message.author.prefix(1)).uppercased())
                    .font(.subheadline.bold()).frame(width: 34, height: 34)
                    .background(message.author == "alex" ? TreeTheme.berry.opacity(0.13) : TreeTheme.sky.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(message.author == "alex" ? TreeTheme.berry : TreeTheme.sky).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.authorLabel).font(.subheadline.bold())
                    Text(ServerDate.label(message.createdAt)).font(.caption2).foregroundStyle(TreeTheme.muted)
                }
                Spacer()
                if message.via == "claude" { Text("CLAUDE").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(TreeTheme.muted) }
            }
            if !message.text.isEmpty { Text(message.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            if let file = message.attachment { attachment(file) }
            ForEach(legacyImages) { attachment($0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func attachment(_ file: TreehouseFile) -> some View {
        Button { openFile(file) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if file.isImage { AuthenticatedImage(api: api, file: file).frame(maxHeight: 210).clipShape(RoundedRectangle(cornerRadius: 12)) }
                Label(file.name, systemImage: file.symbol).font(.caption.weight(.semibold)).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).foregroundStyle(TreeTheme.green)
    }
}

struct AuthenticatedImage: View {
    let api: APIClient
    let file: TreehouseFile
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Label("Tap to open image", systemImage: "photo").padding(20) }
            else { ProgressView().frame(maxWidth: .infinity).frame(height: 110).background(TreeTheme.softGreen) }
        }.task(id: file.id) {
            do {
                let url = try await api.download(file)
                let data = try Data(contentsOf: url)
                // Downsample large uploads before displaying them in a scrolling list.
                if let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                    image = UIImage(cgImage: thumb)
                } else { failed = true }
            } catch { failed = true }
        }.accessibilityLabel(file.name)
    }
}
