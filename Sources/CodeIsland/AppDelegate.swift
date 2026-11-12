import AppKit
import SwiftUI
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.codeisland", category: "AppDelegate")

    var panelController: PanelWindowController?
    private var hookServer: HookServer?
    private var hookRecoveryTimer: Timer?
    private var lastHookCheck: Date = .distantPast
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // The mascot sheet is a review window and nothing else: no hook server, no panel,
        // so it can run beside the installed app without taking its socket.
        if ProcessInfo.processInfo.arguments.contains("--mascot-sheet") {
            NSApp.setActivationPolicy(.regular)
            MascotSheet.showIfRequested()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // `--mascot-moves`: one big Hatch and a button per move, for trying each on its own.
        if ProcessInfo.processInfo.arguments.contains("--mascot-moves") {
            NSApp.setActivationPolicy(.regular)
            MascotMoves.show()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        #endif
        ProcessInfo.processInfo.disableAutomaticTermination("CodeIsland must stay running")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Pre-set app icon so Dock/menu bar use the packaged bundle icon.
        NSApp.applicationIconImage = SettingsWindowController.bundleAppIcon()
        StatusItemController.shared.startObserving()
        // Start HookServer BEFORE installing hooks into CLI configs.
        // If we write settings.json first, Claude Code picks up the new hooks
        // immediately but the socket isn't listening yet — PermissionRequest
        // hooks get no response and Claude Code denies them.
        hookServer = HookServer(appState: appState)
        hookServer?.start()
        RemoteManager.shared.onDisconnect = { [weak appState] hostId in
            appState?.removeRemoteSessions(hostId: hostId)
        }

        if ConfigInstaller.install() {
            Self.log.info("Hooks installed")
        } else {
            Self.log.warning("Failed to install hooks")
        }

        panelController = PanelWindowController(appState: appState)
        panelController?.showPanel()
        HatchDirector.shared.attach(appState)
        HatchCompanion.shared.start(appState: appState, panel: panelController)

        appState.startSessionDiscovery()
        RemoteManager.shared.startup()
        // Outbound connection to the relay, so the phone app can watch and drive sessions.
        // No-op until the user pairs a device.
        appState.setupMobileBridge()

        // Usage monitors:
        //   - Codex: parses local rollout JSONL.
        //   - Claude: real numbers from the Claude Code statusline JSON
        //     (v2.1.80+) captured by our wrapper script. We install the
        //     wrapper on launch so it kicks in next session start.
        CodexUsageMonitor.shared.start()
        StatuslineInstaller.install()
        // Asking Claude Code for its limits launches the CLI, so it is only worth it while a
        // Claude session is working or the panel is open to show the numbers.
        ClaudeRateLimitReader.shared.probeDemand = { [weak appState] in
            guard let appState else { return false }
            return appState.surface.isExpanded || appState.sessions.values.contains {
                $0.source == "claude" && !$0.isRemote && $0.status != .idle
            }
        }
        ClaudeRateLimitReader.shared.start()
        // Public Anthropic statuspage poller (every 5 min).
        AnthropicStatusMonitor.shared.start()

        // Hooks auto-recovery: periodic + app activation trigger
        hookRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }

        #if DEBUG
        // Preview mode: inject mock data if --preview flag is present
        if let scenario = DebugHarness.requestedScenario() {
            Self.log.debug("Loading scenario: \(scenario.rawValue)")
            DebugHarness.apply(scenario, to: appState)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--rehearse-drop") {
                    Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
                        MainActor.assumeIsolated { TrayFeed.rehearse() }
                    }.fire()
                }
                // `--open-chat <project>` opens that session's conversation, for reviewing the chat.
                if let i = args.firstIndex(of: "--open-chat"), i + 1 < args.count,
                   let id = appState.sessions.first(where: { $0.value.projectDisplayName == args[i + 1] })?.key {
                    appState.surface = .sessionChat(sessionId: id)
                    return
                }
                // `--wheel-test x y` feeds mouse-wheel notches through AppKit at a point of the
                // panel (top-left screen coordinates), to check the sideways rows scroll.
                if let i = args.firstIndex(of: "--wheel-test"), i + 2 < args.count,
                   let x = Double(args[i + 1]), let y = Double(args[i + 2]) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        for n in 0..<10 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.05) {
                                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                                       wheel1: -3, wheel2: 0, wheel3: 0) else { return }
                                cg.location = CGPoint(x: x, y: y)
                                let wins = NSApp.windows.filter { $0.isVisible }
                                if let w = wins.first(where: { $0.level.rawValue > 0 }) {
                                    cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(w.windowNumber))
                                    cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(w.windowNumber))
                                    if let ev = NSEvent(cgEvent: cg) { NSApp.postEvent(ev, atStart: false) }
                                }
                            }
                        }
                    }
                }
                if args.contains("--settings-page") { SettingsWindowController.shared.show() }
                // `--learn-now` reads the sessions (and, the first time, past conversations)
                // right away and prints what the profile holds.
                if args.contains("--learn-now") {
                    HatchProfile.shared.tick(sessions: Array(appState.sessions.values), force: true)
                    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                        MainActor.assumeIsolated {
                            let lines = HatchProfile.shared.facts.map { "\($0.slot.rawValue)=\($0.value) [\($0.source.rawValue) x\($0.seen)]" }
                            FileHandle.standardError.write("profile: \(lines.joined(separator: " | "))\n".data(using: .utf8)!)
                        }
                    }
                }
                // `--curio-now` prepares a curiosity right away and shows it when it's ready.
                if args.contains("--curio-now") {
                    HatchCuriosities.shared.tick(force: true)
                    let state = appState
                    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                        MainActor.assumeIsolated {
                            guard let c = HatchCuriosities.shared.take() else { return }
                            timer.invalidate()
                            FileHandle.standardError.write("curio [\(c.topic)] \(c.text)\n".data(using: .utf8)!)
                            state.showBuddySpeech(text: c.text, mood: .idle, title: "Curiosidade: \(c.topic)",
                                                     reaction: .point, duration: 8)
                        }
                    }
                    return
                }
                // `--hello` plays the launch greeting instead of opening the list.
                if args.contains("--hello") {
                    HatchCompanion.shared.greetForPreview()
                    return
                }
                if appState.surface == .collapsed {
                    withAnimation(NotchAnimation.pop) {
                        appState.surface = .sessionList
                    }
                }
            }
            return
        }
        #endif

        // Look for new releases now and every few hours; install them when nothing is going on.
        UpdateChecker.shared.startAutomaticUpdates(appState: appState)

        SoundManager.shared.playBoot()
        setupGlobalShortcut()

        // Boot animation: brief expand to confirm app is running. Hatch's hello does that
        // job when it is on, so the panel opens straight into it instead of flashing the
        // agents list first.
        let hatchGreets = UserDefaults.standard.object(forKey: SettingsKey.hatchSpontaneous) as? Bool
            ?? SettingsDefaults.hatchSpontaneous
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !hatchGreets, appState.surface == .collapsed else { return }
            withAnimation(NotchAnimation.pop) {
                appState.surface = .sessionList
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .sessionList = appState.surface {
                withAnimation(NotchAnimation.close) {
                    appState.surface = .collapsed
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookRecoveryTimer?.invalidate()
        teardownGlobalShortcut()
        appState.saveSessions()
        RemoteManager.shared.shutdown()
        MobileBridge.shared.stop()
        hookServer?.stop()
        appState.stopSessionDiscovery()
    }

    // MARK: - Global Shortcuts

    func setupGlobalShortcut() {
        teardownGlobalShortcut()

        // Collect all enabled shortcut bindings, skip duplicates (first wins)
        var bindings: [(keyCode: UInt16, mods: NSEvent.ModifierFlags, action: ShortcutAction)] = []
        var seen: Set<String> = []
        for action in ShortcutAction.allCases {
            guard action.isEnabled else { continue }
            let b = action.binding
            let key = "\(b.keyCode)-\(b.modifiers.rawValue)"
            guard seen.insert(key).inserted else { continue }
            bindings.append((b.keyCode, b.modifiers, action))
        }
        guard !bindings.isEmpty else { return }

        let handler: (NSEvent) -> Bool = { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for b in bindings where event.keyCode == b.keyCode && eventMods == b.mods {
                Task { @MainActor in self?.executeShortcut(b.action) }
                return true
            }
            return false
        }

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handler(event)
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    private func teardownGlobalShortcut() {
        if let m = globalShortcutMonitor { NSEvent.removeMonitor(m) }
        if let m = localShortcutMonitor { NSEvent.removeMonitor(m) }
        globalShortcutMonitor = nil
        localShortcutMonitor = nil
    }

    private func executeShortcut(_ action: ShortcutAction) {
        switch action {
        case .togglePanel:
            if appState.surface.isExpanded {
                withAnimation(NotchAnimation.close) { appState.surface = .collapsed }
            } else {
                withAnimation(NotchAnimation.open) {
                    appState.surface = .sessionList
                    appState.cancelCompletionQueue()
                    if appState.activeSessionId == nil {
                        appState.activeSessionId = appState.sessions.keys.sorted().first
                    }
                }
            }
        case .approve:
            appState.approvePermission()
        case .approveAlways:
            appState.approvePermission(always: true)
        case .deny:
            appState.denyPermission()
        case .skipQuestion:
            appState.skipQuestion()
        case .jumpToTerminal:
            if let id = appState.activeSessionId, let session = appState.sessions[id] {
                TerminalActivator.activate(session: session, sessionId: id)
            }
        case .createCheckpoint:
            createCheckpointForActiveSession()
        }
    }

    /// Snapshots the active session's project so the agent's next edits can be
    /// undone. Runs git off the main thread; reports the outcome as a notice.
    private func createCheckpointForActiveSession() {
        guard let id = appState.activeSessionId,
              let session = appState.sessions[id],
              let cwd = session.cwd, !cwd.isEmpty else {
            SoundManager.shared.handleEvent("PostToolUseFailure")
            Self.log.warning("Checkpoint skipped: no active session with a working directory")
            return
        }
        let projectName = (cwd as NSString).lastPathComponent
        let state = appState

        Task.detached(priority: .userInitiated) {
            do {
                let checkpoint = try CheckpointManager.createCheckpoint(
                    projectName: projectName,
                    projectDirectory: cwd
                )
                await MainActor.run {
                    Self.log.info("Checkpoint created: \(checkpoint.id)")
                    state.showBuddySpeech(
                        text: "\(L10n.shared["checkpoint_created"]) · \(checkpoint.commitHash)"
                    )
                }
            } catch {
                await MainActor.run {
                    Self.log.error("Checkpoint failed: \(error.localizedDescription)")
                    state.showBuddySpeech(text: L10n.shared["checkpoint_failed"])
                }
            }
        }
    }

    private func checkAndRepairHooks() {
        guard Date().timeIntervalSince(lastHookCheck) > 60 else { return }
        lastHookCheck = Date()
        let repaired = ConfigInstaller.verifyAndRepair()
        if !repaired.isEmpty {
            Self.log.info("Auto-repaired hooks for: \(repaired.joined(separator: ", "))")
        }
    }

}
