import SwiftUI
import Observation

@MainActor @Observable
final class AppSession {
    var api: APIClient?
    var person: String?
    var connecting = false
    var restored = false
    var error: String?
    var selectedTab = "chat"

    func connect(endpoint: String, key: String) async {
        connecting = true; error = nil
        defer { connecting = false }
        var candidate: APIClient?
        do {
            let url = try APIClient.validatedEndpoint(endpoint)
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw APIError.message("Paste your personal Treehouse key.") }
            let client = APIClient(endpoint: url, key: trimmed, onUnauthorized: { [weak self] in self?.signOut(expired: true) })
            candidate = client
            let identity = try await client.me()
            try CredentialStore.save(Credentials(endpoint: url, key: trimmed))
            client.store.write(identity, key: "identity")
            api = client; person = identity
        } catch {
            // Failed sign-in must not delete previously cached content.
            candidate?.activeSessionFailed()
            self.error = error.localizedDescription
        }
    }
    func restore() async {
        guard !restored else { return }
        restored = true
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            startDemo()
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--screen"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) { selectedTab = ProcessInfo.processInfo.arguments[index + 1] }
            return
        }
        guard let credentials = CredentialStore.load() else { return }
        connecting = true
        defer { connecting = false }
        let client = APIClient(endpoint: credentials.endpoint, key: credentials.key,
                               onUnauthorized: { [weak self] in self?.signOut(expired: true) })
        do {
            let identity = try await client.me()
            client.store.write(identity, key: "identity")
            api = client; person = identity
        } catch APIError.unauthorized { client.deactivate(); self.error = APIError.unauthorized.localizedDescription }
        catch {
            if let identity: String = client.store.read("identity") { api = client; person = identity }
            else { client.activeSessionFailed(); self.error = error.localizedDescription }
        }
    }
    func startDemo() {
        let store = LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("TreehouseDemo-" + UUID().uuidString))
        api = APIClient(endpoint: APIClient.production, key: "", demo: true, store: store)
        person = "sam"; error = nil
    }
    func signOut(expired: Bool = false) {
        let demo = api?.isDemo == true
        api?.deactivate(); api = nil; person = nil
        if !demo { CredentialStore.clear() }
        error = expired ? APIError.unauthorized.localizedDescription : nil
    }
}

@main
struct TreehouseApp: App {
    @State private var session = AppSession()
    var body: some Scene {
        WindowGroup {
            Group {
                if let api = session.api, let person = session.person {
                    MainTabs(api: api, person: person).id(ObjectIdentifier(api))
                } else { WelcomeView() }
            }
            .environment(session)
            .tint(TreeTheme.green)
            .foregroundStyle(TreeTheme.ink)
            .fontDesign(.rounded)
            .task { await session.restore() }
        }
    }
}

struct MainTabs: View {
    @Environment(AppSession.self) private var session
    let api: APIClient
    let person: String
    var body: some View {
        @Bindable var session = session
        VStack(spacing: 0) {
            if api.isDemo {
                HStack {
                    Label("Sample space", systemImage: "leaf.circle")
                    Spacer()
                    Button("Leave demo") { session.signOut() }
                }.font(.caption.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 8)
                    .background(TreeTheme.softGreen)
            }
            TabView(selection: $session.selectedTab) {
                NavigationStack { ChannelList(api: api) }.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag("chat")
                NavigationStack { NotesList(api: api) }.tabItem { Label("Notes", systemImage: "book.closed") }.tag("notes")
                NavigationStack { FilesList(api: api) }.tabItem { Label("Files", systemImage: "folder") }.tag("files")
                NavigationStack { SettingsView(api: api, person: person) }.tabItem { Label("Settings", systemImage: "gearshape") }.tag("settings")
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @State private var key = ""
    @State private var endpoint = "https://workspace.example.com"
    @State private var advanced = false
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 28)
                TreehouseArt().frame(width: 180, height: 198)
                VStack(spacing: 10) {
                    Text("A little closer\nto home.").font(.system(size: 38, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                    Text("Your people, your plans, your Treehouse.").foregroundStyle(TreeTheme.muted).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("TREEHOUSE 310").font(.caption.weight(.bold)).tracking(2).foregroundStyle(TreeTheme.green)
                    SecureField("Your personal key", text: $key).textContentType(.password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(14).background(TreeTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("personalKey")
                    if let error = session.error { ErrorBanner(message: error) }
                    Button {
                        Task { await session.connect(endpoint: endpoint, key: key); if session.person != nil { key = "" } }
                    } label: {
                        HStack { Spacer(); if session.connecting { ProgressView() }; Text("Climb up").fontWeight(.bold); Image(systemName: "arrow.up.right"); Spacer() }
                            .padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).foregroundStyle(TreeTheme.paper).disabled(session.connecting || key.isEmpty)
                        .accessibilityIdentifier("connectButton")
                    Text("Your key is kept securely in this iPhone’s Keychain.").font(.caption).foregroundStyle(TreeTheme.muted)
                }.paperCard()
                Button("Take a look around") { session.startDemo() }.font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("demoButton")
                DisclosureGroup("Connection settings", isExpanded: $advanced) {
                    TextField("Server URL", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).padding(.top, 10)
                    Text("Use your own Treehouse server, or keep the default.").font(.caption).foregroundStyle(TreeTheme.muted)
                }.font(.footnote).foregroundStyle(TreeTheme.muted)
                Spacer(minLength: 20)
            }.padding(26).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }.background(PaperBackground()).scrollDismissesKeyboard(.interactively)
    }
}

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    let api: APIClient
    let person: String
    @State private var confirm = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    TreehouseArt().frame(width: 66, height: 74)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("You’re home, \(person.capitalized).").font(.headline)
                        Text(api.isDemo ? "Exploring the sample space" : "Connected to your Treehouse").font(.subheadline).foregroundStyle(TreeTheme.muted)
                    }
                }.padding(.vertical, 10)
            }.listRowBackground(TreeTheme.paper)
            Section("Your connection") {
                LabeledContent("Server", value: api.endpoint.host ?? "")
                LabeledContent("Version", value: "0.1 (1)")
                Text("Chat refreshes while it’s on screen. Notifications aren’t enabled in this first version.")
                    .font(.footnote).foregroundStyle(TreeTheme.muted)
            }.listRowBackground(TreeTheme.paper)
            Section("Privacy") {
                Text("Conversations, notes, and files are shared with the people and agents in your Treehouse. The app sends them only to your configured server.")
                Text("No advertising or analytics SDKs. Your key stays in Keychain. Signing out removes local drafts, cached content, and downloaded previews.")
                if !api.isDemo {
                    Text("Notes use the existing server’s save behavior. The app checks for changes before saving, but simultaneous edits can still overwrite one another.")
                }
            }.font(.footnote).listRowBackground(TreeTheme.paper)
            Section {
                Button(api.isDemo ? "Leave sample space" : "Sign out", role: .destructive) { confirm = true }
            }.listRowBackground(TreeTheme.paper)
        }.treeList().navigationTitle("Settings")
            .confirmationDialog("Sign out and remove local drafts and downloads?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { session.signOut() }
            }
    }
}
