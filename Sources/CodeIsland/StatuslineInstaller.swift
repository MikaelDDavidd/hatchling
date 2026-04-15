import Foundation

/// Installs Hatchling's statusline wrapper into ~/.claude/settings.json so we
/// can capture `rate_limits` from the Claude Code statusline JSON (v2.1.80+).
/// The user's existing statusline command is preserved by saving it next to
/// the wrapper and delegating to it from inside the wrapper.
enum StatuslineInstaller {
    private static var fm: FileManager { .default }

    private static var home: URL { fm.homeDirectoryForCurrentUser }
    private static var hatchDir: URL { home.appendingPathComponent(".codeisland", isDirectory: true) }
    private static var wrapperPath: URL { hatchDir.appendingPathComponent("hatchling-statusline.sh") }
    private static var originalCmdPath: URL { hatchDir.appendingPathComponent("statusline-original.cmd") }
    private static var settingsPath: URL { home.appendingPathComponent(".claude/settings.json") }

    /// Hard marker we use to recognize our wrapper command and avoid
    /// re-wrapping or losing the user's original on subsequent installs.
    private static let wrapperCommand = "~/.codeisland/hatchling-statusline.sh"

    /// Install or refresh the wrapper. Idempotent.
    @discardableResult
    static func install() -> Bool {
        do {
            try fm.createDirectory(at: hatchDir, withIntermediateDirectories: true)

            // 1. Copy/refresh the wrapper script
            guard let bundleURL = Bundle.appModule.url(
                forResource: "hatchling-statusline-wrapper",
                withExtension: "sh",
                subdirectory: "Resources"
            ) else { return false }

            let scriptData = try Data(contentsOf: bundleURL)
            try scriptData.write(to: wrapperPath)

            // chmod +x
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath.path)

            // 2. Read existing settings.json
            var settings: [String: Any] = [:]
            if let data = try? Data(contentsOf: settingsPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = json
            }

            let existingStatusline = settings["statusLine"] as? [String: Any] ?? [:]
            let existingCommand = existingStatusline["command"] as? String

            // 3. If we're not already installed, save the existing command for delegation
            if existingCommand != wrapperCommand {
                let toPreserve = existingCommand ?? ""
                try toPreserve.write(to: originalCmdPath, atomically: true, encoding: .utf8)
            }

            // 4. Patch settings.json with our wrapper
            settings["statusLine"] = [
                "type": "command",
                "command": wrapperCommand
            ]
            let patched = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
            try patched.write(to: settingsPath)
            return true
        } catch {
            return false
        }
    }

    /// Restore the user's original statusline command and remove the wrapper hook.
    /// Files in ~/.codeisland/ are left intact so a future re-install is fast.
    @discardableResult
    static func uninstall() -> Bool {
        do {
            // Read settings
            guard let data = try? Data(contentsOf: settingsPath),
                  var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }

            let original: String = (try? String(contentsOf: originalCmdPath, encoding: .utf8)) ?? ""
            let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                settings.removeValue(forKey: "statusLine")
            } else {
                settings["statusLine"] = ["type": "command", "command": trimmed]
            }

            let patched = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
            try patched.write(to: settingsPath)
            return true
        } catch {
            return false
        }
    }

    /// Whether our wrapper is currently the active statusline command.
    static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sl = json["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd == wrapperCommand
    }
}
