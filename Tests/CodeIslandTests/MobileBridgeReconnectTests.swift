import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Reconnection, which is the part that actually failed in the field.
///
/// The bridge spent a night reporting itself connected while the relay saw nothing: the Mac
/// slept, the network went away, and the WebSocket task neither delivered a frame nor an error.
/// Nothing was broken enough to notice, which is the worst way for a connection to die.
///
/// These drive a real relay and then take it away, because the bug only exists in the gap
/// between "the socket is gone" and "the socket said so".
@MainActor
final class MobileBridgeReconnectTests: XCTestCase {

    private static let macToken = "reconnect-token-long-enough-okay"
    private var relay: Process?
    private var port = 0
    private var storeDir: URL?

    // MARK: - Harness

    private var relayEntrypoint: URL? {
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

    @discardableResult
    private func startRelay(on fixedPort: Int? = nil) throws -> Int {
        guard let entrypoint = relayEntrypoint, let node = findNode() else {
            throw XCTSkip("relay not built — run `npx tsc` in hatchling-mobile/relay")
        }

        let chosen = fixedPort ?? Int.random(in: 9100...9250)
        port = chosen

        if storeDir == nil {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hatchling-reconnect-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            storeDir = dir
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [entrypoint.path]
        process.environment = [
            "PORT": String(chosen),
            "HATCHLING_MAC_TOKEN": Self.macToken,
            "HATCHLING_STORE": storeDir!.appendingPathComponent("devices.json").path,
            "PATH": "/usr/bin:/bin",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        relay = process

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if healthOK() { return chosen }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("relay never became healthy")
        return chosen
    }

    private func stopRelay() {
        relay?.terminate()
        relay?.waitUntilExit()
        relay = nil
    }

    private func healthOK() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        URLSession(configuration: .ephemeral).dataTask(with: url) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 1)
        return ok
    }

    private func configure() {
        // The xctest process has its own defaults domain; the installed app is untouched.
        UserDefaults.standard.set(true, forKey: SettingsKey.mobileBridgeEnabled)
        UserDefaults.standard.set("ws://127.0.0.1:\(port)/ws", forKey: SettingsKey.mobileRelayURL)
        UserDefaults.standard.set(Self.macToken, forKey: SettingsKey.mobileRelayToken)
    }

    private func waitFor(_ description: String, timeout: TimeInterval = 12, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    private var isOnline: Bool {
        if case .online = MobileBridge.shared.state { return true }
        return false
    }

    override func tearDown() async throws {
        MobileBridge.shared.stop()
        stopRelay()
        if let storeDir { try? FileManager.default.removeItem(at: storeDir) }
        for key in [SettingsKey.mobileBridgeEnabled, SettingsKey.mobileRelayURL, SettingsKey.mobileRelayToken] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try await super.tearDown()
    }

    // MARK: - Tests

    /// The regression. A relay that goes away and comes back must end with the bridge online,
    /// without anyone restarting the app.
    func testBridgeComesBackAfterTheRelayDisappears() throws {
        let chosenPort = try startRelay()
        configure()

        MobileBridge.shared.start()
        XCTAssertTrue(waitFor("initial connect") { self.isOnline }, "never connected in the first place")

        // The relay vanishes, the way it does when the network drops.
        stopRelay()
        XCTAssertTrue(waitFor("notices the drop") { !self.isOnline }, "bridge never noticed the relay was gone")

        // And comes back on the same port.
        try startRelay(on: chosenPort)

        // Backoff is exponential with jitter, so this needs room for a couple of attempts.
        XCTAssertTrue(
            waitFor("reconnect", timeout: 30) { self.isOnline },
            "bridge never reconnected — state is \(MobileBridge.shared.state)"
        )
    }

    /// Connecting with nothing listening must fail fast and schedule a retry, rather than
    /// waiting forever. `waitsForConnectivity` used to make this hang silently, which is
    /// precisely how the overnight failure happened.
    func testConnectingWithNothingListeningFailsInsteadOfHanging() throws {
        _ = try startRelay()
        stopRelay()  // port now closed
        configure()

        MobileBridge.shared.start()

        let gaveUp = waitFor("fails fast", timeout: 25) {
            if case .retrying = MobileBridge.shared.state { return true }
            if case .failed = MobileBridge.shared.state { return true }
            return false
        }
        XCTAssertTrue(gaveUp, "bridge sat in \(MobileBridge.shared.state) instead of reporting a failure")
    }

    func testStoppingIsRespectedAndDoesNotReconnect() throws {
        try startRelay()
        configure()

        MobileBridge.shared.start()
        XCTAssertTrue(waitFor("connect") { self.isOnline })

        MobileBridge.shared.stop()
        XCTAssertEqual(MobileBridge.shared.state, .off)

        // A deliberate stop must stay stopped, even though the relay is still right there.
        let stayedOff = !waitFor("must not reconnect", timeout: 6) { self.isOnline }
        XCTAssertTrue(stayedOff, "stop() was overridden by a retry")
    }
}
