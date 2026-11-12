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

    /// A prompt is a message to the agent, not a document. The cap keeps a stray paste (or a
    /// hostile client) from flooding the terminal, and stays far below tmux's argv limit.
    static let maxPromptLength = 8_000

    /// Shells a tmux pane falls back to once the CLI exits. Typing a prompt plus Return into
    /// one of these would run the prompt as a shell command.
    private static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "tcsh", "csh", "ksh", "nu", "login"]

    /// Returns nil on success, or a message explaining why it did not happen. Runs the tmux
    /// calls off the main actor, with a timeout, so a stuck tmux cannot freeze the notch.
    static func inject(text: String, into session: SessionSnapshot) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.shared["prompt_err_empty"] }
        guard trimmed.count <= maxPromptLength else {
            return String(format: L10n.shared["prompt_err_too_long"], trimmed.count, maxPromptLength)
        }
        // While the agent waits on an approval or a question, Return would answer that dialog
        // instead of sending a prompt.
        if session.status == .waitingApproval || session.status == .waitingQuestion {
            return L10n.shared["prompt_err_waiting"]
        }

        if hasTmuxPane(session) {
            return await Task.detached { injectViaTmux(text: trimmed, session: session) }.value
        }
        guard keystrokeInjectionEnabled else {
            return L10n.shared["prompt_err_not_tmux"]
        }
        return await MainActor.run { injectViaKeystrokes(text: trimmed, session: session) }
    }

    // MARK: - tmux

    private static func injectViaTmux(text: String, session: SessionSnapshot) -> String? {
        guard let pane = session.tmuxPane, let tmux = findTmux() else {
            return L10n.shared["prompt_err_no_tmux"]
        }

        var env = ProcessInfo.processInfo.environment
        if let socket = session.tmuxEnv, !socket.isEmpty {
            env["TMUX"] = socket
        }

        // The pane must still be running the agent. If the CLI exited, the pane is back at a
        // shell prompt and the text would be executed as a command.
        if let current = output(tmux, ["display-message", "-p", "-t", pane, "#{pane_current_command}"], env: env) {
            let name = current.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if shells.contains(name.lowercased()) {
                return L10n.shared["prompt_err_pane_gone"]
            }
        } else {
            return L10n.shared["prompt_err_pane_check"]
        }

        // Two calls, deliberately. `send-keys -l` sends the text literally, so a prompt
        // containing "Enter" or a semicolon cannot be read as a key name; the second call
        // sends the actual Return.
        guard run(tmux, ["send-keys", "-t", pane, "-l", text], env: env) else {
            return L10n.shared["prompt_err_tmux_text"]
        }
        guard run(tmux, ["send-keys", "-t", pane, "Enter"], env: env) else {
            return L10n.shared["prompt_err_tmux_newline"]
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
        execute(launchPath, args, env: env) != nil
    }

    /// Standard output of a successful run, or nil.
    private static func output(_ launchPath: String, _ args: [String], env: [String: String]) -> String? {
        execute(launchPath, args, env: env)
    }

    /// Runs a short command and gives up after `timeout` seconds. Never called on the main
    /// actor: a tmux server that stops answering must not take the notch down with it.
    private static func execute(_ launchPath: String, _ args: [String], env: [String: String], timeout: TimeInterval = 3) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            log.error("failed to run \(launchPath): \(error.localizedDescription)")
            return nil
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            log.error("\(launchPath) timed out")
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Keystrokes

    @MainActor
    private static func injectViaKeystrokes(text: String, session: SessionSnapshot) -> String? {
        guard AXIsProcessTrusted() else {
            return L10n.shared["prompt_err_accessibility"]
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
            return L10n.shared["prompt_err_event_source"]
        }

        for chunk in text.chunked(into: 20) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                return L10n.shared["prompt_err_keystrokes"]
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
