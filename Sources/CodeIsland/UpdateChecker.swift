import AppKit
import Combine
import os.log

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, dmgURL: String?, releaseURL: String)
    case downloading(progress: Double)
    case installing
    case failed(String)
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    private static let log = Logger(subsystem: "com.codeisland", category: "UpdateChecker")
    // Hatchling's own releases. It pointed at the upstream CodeIsland, whose versions
    // (1.x) are always "newer" than ours, so every copy offered to replace itself with
    // a different app.
    private let repo = "MikaelDDavidd/hatchling"

    @Published var state: UpdateState = .idle

    private var currentVersion: String { AppVersion.current }
    private var isChecking = false

    private weak var appState: AppState?
    private var schedule: Timer?
    private var idleWait: Timer?

    /// Checks now and every six hours. With auto-update on (the default), a newer release
    /// is downloaded and installed by itself the next time nothing is going on: no
    /// session working, nothing waiting for the user, the notch closed. The app restarts
    /// into the new version and Hatch says so.
    func startAutomaticUpdates(appState: AppState) {
        self.appState = appState
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkForUpdates() }
        schedule?.invalidate()
        schedule = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        schedule?.tolerance = 600
    }

    private var autoUpdateEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.autoUpdate) as? Bool ?? SettingsDefaults.autoUpdate
    }

    private func installWhenIdle() {
        guard autoUpdateEnabled, !isHomebrewInstall, idleWait == nil else { return }
        guard case .available(_, let dmg, _) = state, dmg != nil else { return }
        idleWait = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let appState = self.appState else { return }
                let busy = appState.sessions.values.contains {
                    $0.status == .processing || $0.status == .running
                        || $0.status == .waitingApproval || $0.status == .waitingQuestion
                }
                guard !busy, !appState.hasPendingInteraction, appState.surface == .collapsed else { return }
                self.idleWait?.invalidate()
                self.idleWait = nil
                self.performUpdate()
            }
        }
        idleWait?.fire()
    }

    var isHomebrewInstall: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/Caskroom/") || path.contains("/homebrew/")
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        // A check landing mid-install would flip the state back to "available" and start a
        // second install over the same files.
        switch state {
        case .downloading, .installing: return
        default: break
        }
        if currentVersion == AppVersion.fallback && Bundle.main.bundleIdentifier == nil { return }
        isChecking = true
        state = .checking

        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            state = .failed("Invalid URL")
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        Task {
            defer { isChecking = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    state = .failed("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else {
                    state = .failed("Invalid response")
                    return
                }

                let remote = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

                var dmgURL: String?
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            dmgURL = downloadURL
                            break
                        }
                    }
                }

                if Self.isNewer(remote: remote, local: currentVersion) {
                    state = .available(version: remote, dmgURL: dmgURL, releaseURL: htmlURL)
                    installWhenIdle()
                } else {
                    state = .upToDate
                }
            } catch {
                Self.log.debug("Update check failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    func performUpdate() {
        guard case let .available(_, dmgURL, releaseURL) = state else { return }
        guard let dmgURL, let downloadURL = URL(string: dmgURL) else {
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        state = .downloading(progress: 0)

        let currentAppPath = Bundle.main.bundlePath
        let dmgPath = NSTemporaryDirectory() + "Hatchling-update.dmg"
        let mountPoint = NSTemporaryDirectory() + "hatchling-update-mount"

        Task {
            do {
                // 1. Download DMG with progress via URLSessionDownloadDelegate
                Self.log.info("Downloading update from \(downloadURL.absoluteString)")
                let progressDelegate = DownloadProgressDelegate { [weak self] progress in
                    Task { @MainActor in self?.state = .downloading(progress: progress) }
                }
                let session = URLSession(configuration: .default, delegate: progressDelegate, delegateQueue: nil)
                let (tempURL, response) = try await session.download(from: downloadURL, delegate: progressDelegate)
                session.invalidateAndCancel()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError.downloadFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
                }

                state = .downloading(progress: 1.0)

                // An approval or question may have arrived during the download. Installing now
                // would quit the app with it unanswered, so wait for things to calm down again.
                while let appState, appState.hasPendingInteraction || appState.sessions.values.contains(where: {
                    $0.status == .processing || $0.status == .running
                }) {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }

                // 2. Move downloaded file, mount, replace — all off main thread
                state = .installing
                let running = currentVersion
                try await Task.detached {
                    let fm = FileManager.default
                    // Move downloaded temp file to known path
                    try? fm.removeItem(atPath: dmgPath)
                    try fm.moveItem(at: tempURL, to: URL(fileURLWithPath: dmgPath))

                    // Mount DMG
                    try Self.runShellProcess("/usr/bin/hdiutil", args: ["attach", "-nobrowse", "-quiet", "-mountpoint", mountPoint, dmgPath])

                    // Find .app in mounted volume
                    guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint),
                          let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                        _ = try? Self.runShellProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                        try? fm.removeItem(atPath: dmgPath)
                        throw UpdateError.appNotFoundInDMG
                    }

                    // Only an app signed by the same developer team replaces this one, so a
                    // tampered or foreign download can never take its place.
                    let sourceAppPath = mountPoint + "/" + appName
                    guard Self.signatureIsValid(sourceAppPath),
                          let newTeam = Self.teamIdentifier(sourceAppPath),
                          newTeam == Self.teamIdentifier(currentAppPath) else {
                        _ = try? Self.runShellProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                        try? fm.removeItem(atPath: dmgPath)
                        throw UpdateError.untrustedSignature
                    }
                    // The DMG must hold a newer build than the one running. A mislabelled or
                    // stale asset would otherwise install, relaunch, look "new" again and loop.
                    let newVersion = (NSDictionary(contentsOfFile: sourceAppPath + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String) ?? ""
                    guard Self.isNewer(remote: newVersion, local: running) else {
                        _ = try? Self.runShellProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                        try? fm.removeItem(atPath: dmgPath)
                        throw UpdateError.notNewer(newVersion)
                    }

                    // Copy next to the current app first and swap in one step. Removing the
                    // installed app before copying left people with no app at all whenever the
                    // copy failed (full disk, interrupted install).
                    let staging = currentAppPath + ".update"
                    try? fm.removeItem(atPath: staging)
                    try fm.copyItem(atPath: sourceAppPath, toPath: staging)
                    if fm.fileExists(atPath: currentAppPath) {
                        _ = try fm.replaceItemAt(URL(fileURLWithPath: currentAppPath), withItemAt: URL(fileURLWithPath: staging))
                    } else {
                        try fm.moveItem(atPath: staging, toPath: currentAppPath)
                    }

                    // Cleanup
                    _ = try? Self.runShellProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                    try? fm.removeItem(atPath: dmgPath)
                }.value

                // 3. Relaunch (back on MainActor). Hatch mentions the update on the way up.
                UserDefaults.standard.set(currentVersion, forKey: SettingsKey.updatedFrom)
                Self.log.info("Relaunching app")
                // Opening the bundle while this copy still runs only brings it forward. A
                // detached shell waits for this process to exit and then opens the new one.
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", currentAppPath]
                try? relaunch.run()
                try await Task.sleep(nanoseconds: 300_000_000)
                NSApp.terminate(nil)

            } catch {
                Self.log.error("Update failed: \(error.localizedDescription)")
                await Task.detached {
                    _ = try? Self.runShellProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                    try? FileManager.default.removeItem(atPath: dmgPath)
                }.value
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated static func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    @discardableResult
    private nonisolated static func runShellProcess(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private nonisolated static func signatureIsValid(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// "TeamIdentifier=ABCDE12345" from codesign; nil for ad-hoc or unsigned builds.
    private nonisolated static func teamIdentifier(_ path: String) -> String? {
        guard let out = try? runShellProcess("/usr/bin/codesign", args: ["-dv", "--verbose=2", path]) else { return nil }
        for line in out.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let team = String(line.dropFirst("TeamIdentifier=".count))
            return team == "not set" ? nil : team
        }
        return nil
    }

    private enum UpdateError: LocalizedError {
        case appNotFoundInDMG
        case untrustedSignature
        case notNewer(String)
        case downloadFailed(Int)
        var errorDescription: String? {
            switch self {
            case .appNotFoundInDMG: return "App not found in DMG"
            case .notNewer(let version): return "The downloaded build (\(version)) is not newer than this one"
            case .downloadFailed(let status): return "The download failed (HTTP \(status))"
            case .untrustedSignature: return "The update is not signed by the same developer"
            }
        }
    }
}

// MARK: - Download progress delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled by the async download(from:delegate:) return value
    }
}
