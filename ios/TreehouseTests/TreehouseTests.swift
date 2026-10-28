import XCTest
@testable import Treehouse

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (code, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class TreehouseTests: XCTestCase {
    private var client: APIClient!
    private var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        client = APIClient(endpoint: APIClient.production, key: "unit-test-key", configuration: configuration,
                           store: LocalStore(directory: directory))
    }
    override func tearDown() async throws {
        client.deactivate(); StubProtocol.handler = nil
    }
    func testAuthenticatedRequestAndPercentEncodedChannel() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
            XCTAssertEqual(request.url?.host, "workspace.example.com")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "channel" })?.value, "a&b")
            return (200, Data("{\"messages\":[]}".utf8))
        }
        let messages = try await client.messages(channel: "a&b")
        XCTAssertTrue(messages.isEmpty)
    }
    func testPlainTextUnauthorizedDoesNotTryJSONDecoding() async throws {
        var invalidated = false
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubProtocol.self]
        let api = APIClient(endpoint: APIClient.production, key: "invalid", configuration: configuration,
                            store: LocalStore(directory: directory), onUnauthorized: { invalidated = true })
        defer { api.deactivate() }
        StubProtocol.handler = { _ in (401, Data("Unauthorized".utf8)) }
        do { _ = try await api.me(); XCTFail("Expected authentication failure") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(invalidated)
    }
    func testServerInputErrorIsShown() async throws {
        StubProtocol.handler = { _ in (400, Data("{\"error\":\"Choose a file to upload.\"}".utf8)) }
        do { _ = try await client.me(); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? APIError, .message("Choose a file to upload.")) }
    }
    func testRedirectCannotBeMistakenForSuccess() async throws {
        StubProtocol.handler = { _ in (302, Data()) }
        do { _ = try await client.me(); XCTFail("Expected redirect rejection") }
        catch { XCTAssertEqual(error as? APIError, .message("Treehouse returned HTTP 302. Try again shortly.")) }
    }
    func testMessageModelsDecodeNullableAttachmentAndClaude() throws {
        let data = Data("""
        {"id":7,"channel":"general","parent_id":null,"author":"alex","via":"claude","text":"Hello","file_id":4,"file_name":"a.png","file_type":"image/png","created_at":"2026-10-28T13:41:00.123Z","reply_count":2}
        """.utf8)
        let message = try JSONDecoder.treehouse.decode(ChatMessage.self, from: data)
        XCTAssertEqual(message.authorLabel, "Alex’s Claude")
        XCTAssertEqual(message.attachment?.id, 4)
        XCTAssertTrue(message.attachment?.isImage == true)
        XCTAssertNotNil(ServerDate.parse(message.createdAt))
        XCTAssertNotNil(ServerDate.parse("2026-10-28T13:41:00Z"))
    }
    func testEmojiLimitMatchesServerUTF16Limit() async throws {
        StubProtocol.handler = { _ in XCTFail("Oversized text must be rejected locally"); return (200, Data()) }
        do { _ = try await client.post(text: String(repeating: "🌿", count: 5_001), channel: "general", replyTo: nil, fileId: nil); XCTFail("Expected size limit") }
        catch { XCTAssertEqual(error as? APIError, .message("Messages can be up to 10,000 characters.")) }
    }
    func testNoteConflictPreventsPUT() async throws {
        let original = Note(id: 1, title: "Plan", body: "Original", createdBy: "sam", updatedBy: "sam", createdAt: "a", updatedAt: "a", path: "Plan", children: [])
        var latest = original; latest.body = "Alex’s edit"; latest.updatedAt = "b"
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(latest)
        StubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET", "A detected conflict must not write")
            return (200, data)
        }
        do { try await client.saveNote(path: "Plan", text: "My draft", original: original); XCTFail("Expected conflict") }
        catch { XCTAssertEqual(error as? APIError, .conflict) }
    }
    func testDraftSurvivesReloadAndCannotReappearAfterSignOut() throws {
        let store = client.store
        let draft = NoteDraft(path: "Weekend", text: "Keep this", original: nil)
        store.write(draft, key: "draft")
        let restored = LocalStore(directory: directory)
        let loaded: NoteDraft? = restored.read("draft")
        XCTAssertEqual(loaded?.text, "Keep this")
        client.deactivate()
        store.write(draft, key: "draft")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testEndpointsRejectCredentialsAndInsecureRemoteHosts() throws {
        XCTAssertThrowsError(try APIClient.validatedEndpoint("https://person:key@example.com"))
        XCTAssertThrowsError(try APIClient.validatedEndpoint("http://example.com"))
        XCTAssertThrowsError(try APIClient.validatedEndpoint("https://example.com/api"))
        XCTAssertThrowsError(try APIClient.validatedEndpoint("https://example.com?key=secret"))
        XCTAssertEqual(try APIClient.validatedEndpoint("https://workspace.example.com").host, "workspace.example.com")
    }
    func testDemoExercisesReplyAttachmentAndFileDownloadWithoutNetwork() async throws {
        StubProtocol.handler = { _ in XCTFail("Demo must not access network"); return (500, Data()) }
        let api = APIClient(endpoint: APIClient.production, key: "", demo: true,
                            store: LocalStore(directory: directory))
        defer { api.deactivate() }
        let upload = try await api.upload(PendingUpload(name: "test.txt", contentType: "text/plain", data: Data("A real attachment".utf8)))
        let posted = try await api.post(text: "Here it is", channel: "general", replyTo: 1, fileId: upload.id)
        let thread = try await api.messages(channel: "general", thread: 1)
        XCTAssertTrue(thread.contains { $0.id == posted.id && $0.fileId == upload.id })
        let url = try await api.download(upload)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "A real attachment")
        try await api.deleteFile(id: upload.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testNoteTreeAndNoteDetailHaveDifferentChildrenTypes() async throws {
        let api = APIClient(endpoint: APIClient.production, key: "", demo: true,
                            store: LocalStore(directory: directory))
        defer { api.deactivate() }
        let tree = try await api.notes()
        XCTAssertEqual(tree.first { $0.id == 2 }?.children.first?.title, "Things to cook")
        let note = try await api.note(id: 2)
        XCTAssertEqual(note.children, ["Things to cook"])
    }
}
