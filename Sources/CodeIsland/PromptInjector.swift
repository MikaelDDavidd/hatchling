import Foundation
import AppKit
import CodeIslandCore
import os

/// Types text into a running CLI session on the user's behalf, for prompts sent from the phone.
///
/// There is no clean way to do this on macOS. `TIOCSTI`, the obvious one, was disabled years ago
/// precisely because it lets one process stuff input into another's terminal. What is left:
///
/// - **tmux `send-keys`** — a real, supported API. Works whether or not the terminal is focused,
///   needs no special permission, and cannot type into the wrong window. Requires the session to
///   be running inside tmux.
/// - **Synthesised keystrokes** — works anywhere, but needs Accessibility permission, has to
///   raise the terminal window first, and types into whatever ends up frontmost. If the user
///   switches windows mid-send, the text lands somewhere else. Off by default, and the setting
///   says so.
///
/// `canInject` is published to the phone as `canPrompt` so the UI can hide a box it cannot honour
/// rather than failing after the fact.
enum PromptInjector {

    private static let log = Logger(subsystem: "com.mikaeldavid.CodeIsland", category: "PromptInjector")

    // MARK: - Capability

    static func canInject(into session: SessionSnapshot) -> Bool {
        if hasTmuxPane(session) { return true }
        return keystrokeInjectionEnabled && session.cliPid != nil
    }

    private static func hasTmuxPane(_ session: SessionSnapshot) -> Bool {
        guard let pane = session.tmuxPane?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !pane.isEmpty
    }

    private static var keystrokeInjectionEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.mobileAllowKeystrokeInjection)
    }

    // MARK: - Injection

    /// Returns nil on success, or a message explaining why it did not happen.
    @MainActor
    static func inject(text: String, into session: SessionSnapshot) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty prompt" }

        if hasTmuxPane(session) {
            return injectViaTmux(text: trimmed, session: session)
        }
        guard keystrokeInjectionEnabled else {
            return "This session is not in tmux. Turn on keystroke injection in Settings to send prompts to it."
        }
        return injectViaKeystrokes(text: trimmed, session: session)
    }

    // MARK: - tmux

    private static func injectViaTmux(text: String, session: SessionSnapshot) -> String? {
        guard let pane = session.tmuxPane, let tmux = findTmux() else {
            return "tmux not found on PATH"
        }

        var env = ProcessInfo.processInfo.environment
        if let socket = session.tmuxEnv, !socket.isEmpty {
            env["TMUX"] = socket
        }

        // Two calls, deliberately. `send-keys -l` sends the text literally, so a prompt
        // containing "Enter" or a semicolon cannot be read as a key name; the second call
        // sends the actual Return.
        guard run(tmux, ["send-keys", "-t", pane, "-l", text], env: env) else {
            return "tmux rejected the text"
        }
        guard run(tmux, ["send-keys", "-t", pane, "Enter"], env: env) else {
            return "tmux rejected the newline"
        }
        return nil
    }

    private static func findTmux() -> String? {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String], env: [String: String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.environment = env
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            log.error("failed to run \(launchPath): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Keystrokes

    @MainActor
    private static func injectViaKeystrokes(text: String, session: SessionSnapshot) -> String? {
        guard AXIsProcessTrusted() else {
            return "Accessibility permission is not granted to Hatchling"
        }

        // Raise the session's terminal first. Without this the keystrokes land in whatever is
        // frontmost, which could be anything.
        TerminalActivator.activate(session: session)

        // Give the window server a moment to actually change focus before typing.
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
            break
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return "Could not create an event source"
        }

        for chunk in text.chunked(into: 20) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                return "Could not synthesise keystrokes"
            }
            var utf16 = Array(chunk.utf16)
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
        }

        // Return, by key code rather than as text.
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        return nil
    }
}

private extension String {
    /// `keyboardSetUnicodeString` gets unreliable with long strings; send it in pieces.
    func chunked(into size: Int) -> [String] {
        guard count > size else { return [self] }
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<end]))
            index = end
        }
        return result
    }
}
