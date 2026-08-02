import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Drives the real `MobileBridge` against the real relay, over a real socket.
///
/// The protocol has two independent implementations, and every bug worth catching here lives in
/// the gap between them — a renamed key, a nested body, an enum spelled differently. Mocking
/// either side would test the mock.
///
/// Skips itself when the relay has not been built, so a checkout without Node still passes.
@MainActor
final class MobileBridgeIntegrationTests: XCTestCase {

    private static let macToken = "integration-token-long-enough-ok"
    private var relay: Process?
    private var port: Int = 0
    private var storeDir: URL?

    // MARK: - Harness

    private var relayEntrypoint: URL? {
        // Tests/CodeIslandTests/ -> repo root -> sibling checkout
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidate = repoRoot
            .deletingLastPathComponent()
            .appendingPathComponent("hatchling-mobile/relay/dist/index.js")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func findNode() -> String? {
        var candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        let nvm = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            for version in versions.sorted().reversed() {
                candidates.append(nvm.appendingPathComponent("\(version)/bin/node").path)
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func startRelay() throws {
        guard let entrypoint = relayEntrypoint, let node = findNode() else {
            throw XCTSkip("relay not built — run `npx tsc` in hatchling-mobile/relay")
        }

        port = Int.random(in: 8900...8990)
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatchling-bridge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        self.storeDir = storeDir

        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [entrypoint.path]
        process.environment = [
            "PORT": String(port),
            "HATCHLING_MAC_TOKEN": Self.macToken,
            "HATCHLING_STORE": storeDir.appendingPathComponent("devices.json").path,
            "PATH": "/usr/bin:/bin",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        relay = process

        // Wait for /health rather than sleeping a fixed amount.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if healthOK() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("relay never became healthy")
    }

    private func healthOK() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 1)
        return ok
    }

    override func tearDown() async throws {
        MobileBridge.shared.stop()
        relay?.terminate()
        relay = nil
        if let storeDir { try? FileManager.default.removeItem(at: storeDir) }
        for key in [
            SettingsKey.mobileBridgeEnabled,
            SettingsKey.mobileRelayURL,
            SettingsKey.mobileRelayToken,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try await super.tearDown()
    }

    private func configureBridge() {
        // This runs in the xctest process, which has its own defaults domain — the installed
        // app's preferences are not touched.
        UserDefaults.standard.set(true, forKey: SettingsKey.mobileBridgeEnabled)
        UserDefaults.standard.set("ws://127.0.0.1:\(port)/ws", forKey: SettingsKey.mobileRelayURL)
        UserDefaults.standard.set(Self.macToken, forKey: SettingsKey.mobileRelayToken)
    }

    /// Minimal phone client, speaking the protocol by hand so the test does not depend on the
    /// same encoder the bridge uses.
    private final class TestPhone {
        private let task: URLSessionWebSocketTask
        private var received: [[String: Any]] = []
        private let lock = NSLock()

        init(port: Int, token: String) {
            let url = URL(string: "ws://127.0.0.1:\(port)/ws")!
            task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            listen()
            send(type: "hello", body: ["role": "phone", "token": token, "device": "Test Phone"])
        }

        private func listen() {
            task.receive { [weak self] result in
                guard let self else { return }
                if case .success(let message) = result {
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.lock.lock()
                        self.received.append(json)
                        self.lock.unlock()
                    }
                    self.listen()
                }
            }
        }

        func send(type: String, body: [String: Any]) {
            let envelope: [String: Any] = [
                "v": 1, "type": type, "id": UUID().uuidString, "ts": 0, "body": body,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: envelope),
                  let text = String(data: data, encoding: .utf8) else { return }
            task.send(.string(text)) { _ in }
        }

        func waitFor(type: String, timeout: TimeInterval = 5) -> [String: Any]? {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                lock.lock()
                let match = received.first { $0["type"] as? String == type }
                lock.unlock()
                if let match { return match }
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            return nil
        }

        func close() { task.cancel(with: .goingAway, reason: nil) }
    }

    private func pairPhone() throws -> String {
        // Ask the relay for a code the way the Mac will, then redeem it the way the app will.
        let phoneToken = expectation(description: "paired")
        var token: String?

        let mac = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        mac.resume()
        func send(_ type: String, _ body: [String: Any]) {
            let envelope: [String: Any] = ["v": 1, "type": type, "id": UUID().uuidString, "ts": 0, "body": body]
            let data = try! JSONSerialization.data(withJSONObject: envelope)
            mac.send(.string(String(data: data, encoding: .utf8)!)) { _ in }
        }
        send("hello", ["role": "mac", "token": Self.macToken, "device": "Pairing Mac"])
        send("pair.create", [:])

        func listen() {
            mac.receive { result in
                guard case .success(.string(let text)) = result else { return }
                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    listen(); return
                }
                if json["type"] as? String == "pair.created",
                   let body = json["body"] as? [String: Any],
                   let code = body["code"] as? String {
                    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(self.port)/pair")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = try? JSONSerialization.data(
                        withJSONObject: ["code": code, "device": "Test Phone"]
                    )
                    URLSession.shared.dataTask(with: request) { data, _, _ in
                        if let data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            token = json["token"] as? String
                        }
                        phoneToken.fulfill()
                    }.resume()
                    return
                }
                listen()
            }
        }
        listen()

        wait(for: [phoneToken], timeout: 10)
        mac.cancel(with: .goingAway, reason: nil)
        return try XCTUnwrap(token, "pairing did not produce a token")
    }

    // MARK: - Tests

    func testBridgePublishesSessionsThatReachAPhone() throws {
        try startRelay()
        let phoneToken = try pairPhone()
        configureBridge()

        MobileBridge.shared.start()

        // Wait for the handshake to land before publishing.
        let connected = Date().addingTimeInterval(5)
        while Date() < connected {
            if case .online = MobileBridge.shared.state { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard case .online = MobileBridge.shared.state else {
            return XCTFail("bridge never reached online, got \(MobileBridge.shared.state)")
        }

        let phone = TestPhone(port: port, token: phoneToken)
        defer { phone.close() }
        XCTAssertNotNil(phone.waitFor(type: "ready"), "phone never completed its handshake")

        // A phone joining makes the relay ask the Mac to resend; give the bridge a beat, then
        // publish as AppState would.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        MobileBridge.shared.publish(sessions: [
            "s1": MobileSession(
                sessionId: "s1", source: "claude", status: "running", project: "Hatchling",
                cwd: "/tmp", model: "opus-5", currentTool: "Bash", toolDescription: "running tests",
                lastUserPrompt: "go", lastAssistantMessage: "on it",
                startTime: 1, lastActivity: 2, interrupted: false, canPrompt: false, contextPercent: 12,
                verb: nil, contextTokens: nil, contextLimit: nil, terminal: nil, subagents: []
            )
        ])

        let message = phone.waitFor(type: "sessions")
        let body = try XCTUnwrap(message?["body"] as? [String: Any], "phone never received sessions")
        let sessions = try XCTUnwrap(body["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?["sessionId"] as? String, "s1")
        XCTAssertEqual(sessions.first?["project"] as? String, "Hatchling")
        XCTAssertEqual(sessions.first?["toolDescription"] as? String, "running tests")
    }

    func testPhoneCommandsReachTheBridgeAndAreAcked() throws {
        try startRelay()
        let phoneToken = try pairPhone()
        configureBridge()

        // Collect every command: the relay also sends `sessions.refresh` when a phone joins,
        // and the two arrive in no guaranteed order.
        var seen: [MobileBridge.Command] = []
        MobileBridge.shared.commandHandler = { command in
            seen.append(command)
            return nil  // success
        }
        MobileBridge.shared.start()

        let connected = Date().addingTimeInterval(5)
        while Date() < connected {
            if case .online = MobileBridge.shared.state { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let phone = TestPhone(port: port, token: phoneToken)
        defer { phone.close() }
        _ = phone.waitFor(type: "ready")

        phone.send(type: "permission.respond", body: ["attentionId": "a1", "decision": "allowAlways"])

        // Give both the refresh and the command time to land.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let permission = seen.compactMap { command -> (String, String)? in
            guard case .permissionRespond(let attentionId, let decision) = command else { return nil }
            return (attentionId, decision)
        }.first

        let decoded = try XCTUnwrap(permission, "bridge never decoded a permission response; saw \(seen)")
        XCTAssertEqual(decoded.0, "a1")
        XCTAssertEqual(decoded.1, "allowAlways")

        let ack = phone.waitFor(type: "ack")
        let body = try XCTUnwrap(ack?["body"] as? [String: Any], "no ack came back")
        XCTAssertEqual(body["ok"] as? Bool, true)
    }

    func testFailedCommandComesBackAsANackWithReason() throws {
        try startRelay()
        let phoneToken = try pairPhone()
        configureBridge()

        MobileBridge.shared.commandHandler = { _ in "This session is not in tmux" }
        MobileBridge.shared.start()

        let connected = Date().addingTimeInterval(5)
        while Date() < connected {
            if case .online = MobileBridge.shared.state { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let phone = TestPhone(port: port, token: phoneToken)
        defer { phone.close() }
        _ = phone.waitFor(type: "ready")

        phone.send(type: "session.prompt", body: ["sessionId": "s1", "text": "hello"])

        let ack = phone.waitFor(type: "ack")
        let body = try XCTUnwrap(ack?["body"] as? [String: Any])
        XCTAssertEqual(body["ok"] as? Bool, false)
        XCTAssertEqual(body["detail"] as? String, "This session is not in tmux")
    }
}
