import SwiftUI
import CodeIslandCore

// MARK: - Preview Scenario System
//
// Usage: launch with --preview <scenario> to inject mock sessions for UI development.
//   e.g.  .build/debug/CodeIsland --preview approval
//
// Scenarios:
//   working     — single session actively running tools
//   approval    — session waiting for permission
//   question    — session with pending question
//   completion  — session just finished
//   multi       — 3 sessions in mixed states
//   busy        — heavy workload with subagents
//   claude      — Claude CLI single session
//   codex       — Codex CLI single session
//   gemini      — Gemini CLI single session
//   cursor      — Cursor CLI single session (YOLO mode)
//   qoder       — Qoder CLI single session
//   factory     — Factory/Droid CLI single session
//   codebuddy   — CodeBuddy CLI single session
//   allcli      — All CLIs running simultaneously

enum PreviewScenario: String, CaseIterable {
    case working
    case approval
    case question
    case completion
    case multi
    case busy
    // CLI-specific scenarios
    case claude
    case codex
    case gemini
    case cursor
    case qoder
    case factory
    case codebuddy
    case opencode
    case allcli
    // Special states
    case idle
    // Performance stress test
    case stress
}

@MainActor
enum DebugHarness {

    /// Check launch arguments for --preview flag, return scenario if found
    static func requestedScenario() -> PreviewScenario? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--preview"), idx + 1 < args.count else { return nil }
        return PreviewScenario(rawValue: args[idx + 1])
    }

    /// Inject mock data into appState for the given scenario
    static func apply(_ scenario: PreviewScenario, to appState: AppState) {
        switch scenario {
        case .working:
            applyWorking(to: appState)
        case .approval:
            applyApproval(to: appState)
        case .question:
            applyQuestion(to: appState)
        case .completion:
            applyCompletion(to: appState)
        case .multi:
            applyMulti(to: appState)
        case .busy:
            applyBusy(to: appState)
        case .claude: applyClaude(to: appState)
        case .codex: applyCodex(to: appState)
        case .gemini: applyGemini(to: appState)
        case .cursor: applyCursor(to: appState)
        case .qoder: applyQoder(to: appState)
        case .factory: applyFactory(to: appState)
        case .codebuddy: applyCodeBuddy(to: appState)
        case .opencode: applyOpenCode(to: appState)
        case .allcli: applyAllCLI(to: appState)
        case .idle: applyIdle(to: appState)
        case .stress: applyStress(to: appState)
        }
    }

    // MARK: - Scenarios

    private static func applyWorking(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .running
        s.cwd = "/Users/dev/my-project"
        s.model = "claude-sonnet-4-20250514"
        s.source = "claude"
        s.currentTool = "Edit"
        s.toolDescription = "src/components/App.tsx"
        s.lastUserPrompt = "Fix the login button styling"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Fix the login button styling"))
        s.recordTool("Read", description: "package.json", success: true, agentType: nil, maxHistory: 20)
        s.recordTool("Grep", description: "className.*login", success: true, agentType: nil, maxHistory: 20)
        s.termApp = "Ghostty"

        state.sessions["preview-working"] = s
        state.activeSessionId = "preview-working"
    }

    private static func applyApproval(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .waitingApproval
        s.cwd = "/Users/dev/api-server"
        s.model = "claude-opus-4-20250514"
        s.source = "claude"
        s.currentTool = "Bash"
        s.toolDescription = "npm run test -- --coverage"
        s.lastUserPrompt = "Run the test suite"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Run the test suite"))
        s.termApp = "iTerm.app"

        state.sessions["preview-approval"] = s
        state.activeSessionId = "preview-approval"
        // A real pending request, so the card draws. `--tool edit|write|read|grep|mcp`
        // picks what is being asked; two extra copies fill the queue line.
        let args = ProcessInfo.processInfo.arguments
        let kind = args.firstIndex(of: "--tool").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "bash"
        let (tool, input): (String, [String: Any]) = {
            switch kind {
            case "edit": return ("Edit", ["file_path": "/Users/dev/web/src/components/Legend.tsx",
                                          "old_string": "width: 320px;", "new_string": "width: 100%; flex-wrap: wrap;"])
            case "write": return ("Write", ["file_path": "/Users/dev/web/src/hooks/useBreakpoint.ts",
                                            "content": "export function useBreakpoint() {\n  const [w, setW] = useState(window.innerWidth)\n  useEffect(() => {\n    const onResize = () => setW(window.innerWidth)"])
            case "read": return ("Read", ["file_path": "/Users/dev/.ssh/config", "offset": 0, "limit": 40])
            case "grep": return ("Grep", ["pattern": "TODO|FIXME", "path": "src/"])
            case "mcp": return ("mcp__github__create_issue", ["title": "Legenda cortada no mobile", "repo": "mikael/dashboard",
                                                              "body": "O gráfico corta a legenda no celular"])
            default: return ("Bash", ["command": "npm run test -- --coverage"])
            }
        }()
        let json: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "preview-approval",
                                   "tool_name": tool, "tool_input": input]
        if let data = try? JSONSerialization.data(withJSONObject: json), let event = HookEvent(from: data) {
            for _ in 0..<3 {
                Task { @MainActor in
                    _ = await withCheckedContinuation { (c: CheckedContinuation<Data, Never>) in
                        state.permissionQueue.append(PermissionRequest(event: event, continuation: c))
                    }
                }
            }
        }
        state.surface = .approvalCard(sessionId: "preview-approval")
    }

    private static func applyQuestion(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .waitingQuestion
        s.cwd = "/Users/dev/web-app"
        s.model = "claude-sonnet-4-20250514"
        s.source = "claude"
        s.lastUserPrompt = "Refactor the auth module"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Refactor the auth module"))

        state.sessions["preview-question"] = s
        state.activeSessionId = "preview-question"

        // Inject a mock question payload for UI preview
        state.previewQuestionPayload = QuestionPayload(
            question: "Which approach do you prefer?",
            options: ["Extract service class", "Use middleware pattern", "Inline helpers"],
            descriptions: [
                "Create a dedicated AuthService class with dependency injection",
                "Add Express-style middleware for auth checks",
                "Keep auth logic inline with helper functions"
            ]
        )
        state.surface = .questionCard(sessionId: "preview-question")
    }

    private static func applyCompletion(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .idle
        s.cwd = "/Users/dev/cli-tool"
        s.model = "claude-sonnet-4-20250514"
        s.source = "claude"
        s.lastUserPrompt = "Add --verbose flag"
        s.lastAssistantMessage = "Done. Added the --verbose flag to the CLI parser with short alias -v. It enables detailed logging output throughout the pipeline."
        s.addRecentMessage(ChatMessage(isUser: true, text: "Add --verbose flag"))
        s.addRecentMessage(ChatMessage(isUser: false, text: "Done. Added the --verbose flag to the CLI parser with short alias -v."))
        s.recordTool("Read", description: "src/cli.rs", success: true, agentType: nil, maxHistory: 20)
        s.recordTool("Edit", description: "src/cli.rs", success: true, agentType: nil, maxHistory: 20)
        s.recordTool("Edit", description: "src/logger.rs", success: true, agentType: nil, maxHistory: 20)
        s.recordTool("Bash", description: "cargo test", success: true, agentType: nil, maxHistory: 20)
        s.termApp = "Ghostty"

        state.sessions["preview-completion"] = s
        state.activeSessionId = "preview-completion"
        state.surface = .completionCard(sessionId: "preview-completion")
    }

    private static func applyMulti(to state: AppState) {
        // Session 1: Claude working
        var s1 = SessionSnapshot()
        s1.status = .running
        s1.cwd = "/Users/dev/frontend"
        s1.model = "claude-sonnet-4-20250514"
        s1.source = "claude"
        s1.currentTool = "Write"
        s1.toolDescription = "src/pages/Dashboard.tsx"
        s1.lastUserPrompt = "Build the dashboard page"
        s1.addRecentMessage(ChatMessage(isUser: true, text: "Build the dashboard page"))
        s1.termApp = "Ghostty"

        // Session 2: Codex idle
        var s2 = SessionSnapshot()
        s2.status = .idle
        s2.cwd = "/Users/dev/backend"
        s2.model = "o3"
        s2.source = "codex"
        s2.lastUserPrompt = "Optimize the query planner"
        s2.lastAssistantMessage = "Refactored the query planner to use a cost-based optimizer."
        s2.addRecentMessage(ChatMessage(isUser: true, text: "Optimize the query planner"))
        s2.addRecentMessage(ChatMessage(isUser: false, text: "Refactored the query planner."))

        // Session 3: Cursor processing
        var s3 = SessionSnapshot()
        s3.status = .processing
        s3.cwd = "/Users/dev/mobile"
        s3.source = "cursor"
        s3.lastUserPrompt = "Fix the scroll jank"
        s3.addRecentMessage(ChatMessage(isUser: true, text: "Fix the scroll jank"))

        state.sessions["preview-multi-1"] = s1
        state.sessions["preview-multi-2"] = s2
        state.sessions["preview-multi-3"] = s3
        state.activeSessionId = "preview-multi-1"
    }

    private static func applyBusy(to state: AppState) {
        // Main Claude session with subagents
        var s1 = SessionSnapshot()
        s1.status = .running
        s1.cwd = "/Users/dev/monorepo"
        s1.model = "claude-opus-4-20250514"
        s1.source = "claude"
        s1.currentTool = "Agent"
        s1.toolDescription = "general-purpose"
        s1.lastUserPrompt = "Migrate the entire codebase to TypeScript 5.5"
        s1.addRecentMessage(ChatMessage(isUser: true, text: "Migrate the entire codebase to TypeScript 5.5"))
        s1.subagents["agent-1"] = SubagentState(agentId: "agent-1", agentType: "general-purpose")
        s1.subagents["agent-2"] = SubagentState(agentId: "agent-2", agentType: "general-purpose")
        s1.subagents["agent-3"] = SubagentState(agentId: "agent-3", agentType: "Explore")
        // Mark one as completed
        s1.subagents["agent-3"]?.status = .idle
        s1.recordTool("Bash", description: "find . -name '*.ts'", success: true, agentType: nil, maxHistory: 20)
        s1.recordTool("Read", description: "tsconfig.json", success: true, agentType: nil, maxHistory: 20)
        s1.recordTool("Edit", description: "tsconfig.json", success: true, agentType: nil, maxHistory: 20)
        s1.recordTool("Bash", description: "tsc --noEmit", success: false, agentType: nil, maxHistory: 20)
        s1.recordTool("Edit", description: "src/index.ts", success: true, agentType: "general-purpose", maxHistory: 20)
        s1.termApp = "Ghostty"

        // Gemini session
        var s2 = SessionSnapshot()
        s2.status = .processing
        s2.cwd = "/Users/dev/data-pipeline"
        s2.model = "gemini-2.5-pro"
        s2.source = "gemini"
        s2.lastUserPrompt = "Profile the ETL bottleneck"
        s2.addRecentMessage(ChatMessage(isUser: true, text: "Profile the ETL bottleneck"))

        // Codex session waiting approval
        var s3 = SessionSnapshot()
        s3.status = .waitingApproval
        s3.cwd = "/Users/dev/infra"
        s3.model = "o3"
        s3.source = "codex"
        s3.currentTool = "Bash"
        s3.toolDescription = "terraform apply"
        s3.lastUserPrompt = "Deploy the staging env"
        s3.addRecentMessage(ChatMessage(isUser: true, text: "Deploy the staging env"))

        state.sessions["preview-busy-1"] = s1
        state.sessions["preview-busy-2"] = s2
        state.sessions["preview-busy-3"] = s3
        state.activeSessionId = "preview-busy-1"
    }

    // MARK: - CLI-Specific Scenarios

    private static func applyClaude(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .running
        s.cwd = "/tmp/demo-claude"
        s.model = "claude-opus-4-20250514"
        s.source = "claude"
        s.currentTool = "Edit"
        s.toolDescription = "src/main.swift"
        s.lastUserPrompt = "Refactor the networking layer"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Refactor the networking layer"))
        s.addRecentMessage(ChatMessage(isUser: false, text: "I'll start by reading the current implementation..."))
        s.recordTool("Read", description: "src/Network.swift", success: true, agentType: nil, maxHistory: 20)
        s.recordTool("Grep", description: "URLSession", success: true, agentType: nil, maxHistory: 20)
        s.subagents["agent-1"] = SubagentState(agentId: "agent-1", agentType: "Explore")
        s.termApp = "Ghostty"
        state.sessions["preview-claude"] = s
        state.activeSessionId = "preview-claude"
    }

    private static func applyCodex(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .running
        s.cwd = "/tmp/demo-codex"
        s.model = "o3"
        s.source = "codex"
        s.currentTool = "Bash"
        s.toolDescription = "npm test"
        s.lastUserPrompt = "Fix the failing unit tests"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Fix the failing unit tests"))
        s.termApp = "Terminal"
        state.sessions["preview-codex"] = s
        state.activeSessionId = "preview-codex"
    }

    private static func applyGemini(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .processing
        s.cwd = "/tmp/demo-gemini"
        s.model = "gemini-2.5-pro"
        s.source = "gemini"
        s.lastUserPrompt = "Analyze the performance bottleneck"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Analyze the performance bottleneck"))
        s.addRecentMessage(ChatMessage(isUser: false, text: "Looking at the profiling data..."))
        s.termApp = "iTerm.app"
        state.sessions["preview-gemini"] = s
        state.activeSessionId = "preview-gemini"
    }

    private static func applyCursor(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .running
        s.cwd = "/tmp/demo-cursor"
        s.source = "cursor"
        s.isYoloMode = true
        s.currentTool = "Edit"
        s.toolDescription = "src/App.tsx"
        s.lastUserPrompt = "Add dark mode toggle"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Add dark mode toggle"))
        s.recordTool("Read", description: "src/App.tsx", success: true, agentType: nil, maxHistory: 20)
        s.recordTool("Edit", description: "src/theme.ts", success: true, agentType: nil, maxHistory: 20)
        state.sessions["preview-cursor"] = s
        state.activeSessionId = "preview-cursor"
    }

    private static func applyQoder(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .idle
        s.cwd = "/tmp/demo-qoder"
        s.model = "claude-sonnet-4-20250514"
        s.source = "qoder"
        s.lastUserPrompt = "Generate API documentation"
        s.lastAssistantMessage = "Documentation generated for all 12 endpoints."
        s.addRecentMessage(ChatMessage(isUser: true, text: "Generate API documentation"))
        s.addRecentMessage(ChatMessage(isUser: false, text: "Documentation generated for all 12 endpoints."))
        state.sessions["preview-qoder"] = s
        state.activeSessionId = "preview-qoder"
    }

    private static func applyFactory(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .running
        s.cwd = "/tmp/demo-factory"
        s.model = "claude-sonnet-4-20250514"
        s.source = "droid"
        s.currentTool = "Write"
        s.toolDescription = "tests/integration.py"
        s.lastUserPrompt = "Write integration tests"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Write integration tests"))
        s.recordTool("Read", description: "src/api.py", success: true, agentType: nil, maxHistory: 20)
        state.sessions["preview-factory"] = s
        state.activeSessionId = "preview-factory"
    }

    private static func applyCodeBuddy(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .processing
        s.cwd = "/tmp/demo-codebuddy"
        s.model = "claude-sonnet-4-20250514"
        s.source = "codebuddy"
        s.lastUserPrompt = "Optimize database queries"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Optimize database queries"))
        state.sessions["preview-codebuddy"] = s
        state.activeSessionId = "preview-codebuddy"
    }

    private static func applyOpenCode(to state: AppState) {
        var s = SessionSnapshot()
        s.status = .running
        s.cwd = "/tmp/demo-opencode"
        s.model = "gpt-4.1"
        s.source = "opencode"
        s.currentTool = "Bash"
        s.toolDescription = "npm test"
        s.lastUserPrompt = "Run the test suite"
        s.addRecentMessage(ChatMessage(isUser: true, text: "Run the test suite"))
        s.termApp = "Ghostty"
        state.sessions["preview-opencode"] = s
        state.activeSessionId = "preview-opencode"
    }

    private static func applyAllCLI(to state: AppState) {
        var s1 = SessionSnapshot()
        s1.status = .running
        s1.cwd = "/tmp/demo-claude"
        s1.model = "claude-opus-4-20250514"
        s1.source = "claude"
        s1.currentTool = "Agent"
        s1.toolDescription = "general-purpose"
        s1.lastUserPrompt = "Migrate to TypeScript"
        s1.addRecentMessage(ChatMessage(isUser: true, text: "Migrate to TypeScript"))
        s1.subagents["agent-1"] = SubagentState(agentId: "agent-1", agentType: "general-purpose")
        s1.termApp = "Ghostty"

        var s2 = SessionSnapshot()
        s2.status = .running
        s2.cwd = "/tmp/demo-codex"
        s2.model = "o3"
        s2.source = "codex"
        s2.currentTool = "Bash"
        s2.toolDescription = "cargo build"
        s2.lastUserPrompt = "Build the Rust project"
        s2.addRecentMessage(ChatMessage(isUser: true, text: "Build the Rust project"))

        var s3 = SessionSnapshot()
        s3.status = .processing
        s3.cwd = "/tmp/demo-gemini"
        s3.model = "gemini-2.5-pro"
        s3.source = "gemini"
        s3.lastUserPrompt = "Review the PR"
        s3.addRecentMessage(ChatMessage(isUser: true, text: "Review the PR"))

        var s4 = SessionSnapshot()
        s4.status = .processing
        s4.cwd = "/tmp/demo-cursor"
        s4.source = "cursor"
        s4.isYoloMode = true
        s4.lastUserPrompt = "Refactor components"
        s4.addRecentMessage(ChatMessage(isUser: true, text: "Refactor components"))

        var s5 = SessionSnapshot()
        s5.status = .waitingApproval
        s5.cwd = "/tmp/demo-qoder"
        s5.model = "claude-sonnet-4-20250514"
        s5.source = "qoder"
        s5.currentTool = "Bash"
        s5.toolDescription = "rm -rf node_modules"
        s5.lastUserPrompt = "Clean up dependencies"
        s5.addRecentMessage(ChatMessage(isUser: true, text: "Clean up dependencies"))

        var s6 = SessionSnapshot()
        s6.status = .idle
        s6.cwd = "/tmp/demo-factory"
        s6.model = "claude-sonnet-4-20250514"
        s6.source = "droid"
        s6.lastUserPrompt = "Done with migration"
        s6.lastAssistantMessage = "Migration complete."
        s6.addRecentMessage(ChatMessage(isUser: true, text: "Done with migration"))
        s6.addRecentMessage(ChatMessage(isUser: false, text: "Migration complete."))

        var s7 = SessionSnapshot()
        s7.status = .idle
        s7.cwd = "/tmp/demo-codebuddy"
        s7.model = "claude-sonnet-4-20250514"
        s7.source = "codebuddy"
        s7.interrupted = true
        s7.lastUserPrompt = "Fix the login flow"
        s7.addRecentMessage(ChatMessage(isUser: true, text: "Fix the login flow"))

        var s8 = SessionSnapshot()
        s8.status = .running
        s8.cwd = "/tmp/demo-opencode"
        s8.model = "gpt-4.1"
        s8.source = "opencode"
        s8.currentTool = "Bash"
        s8.toolDescription = "npm test"
        s8.lastUserPrompt = "Run test suite"
        s8.addRecentMessage(ChatMessage(isUser: true, text: "Run test suite"))
        s8.termApp = "Ghostty"

        state.sessions["preview-allcli-1"] = s1
        state.sessions["preview-allcli-2"] = s2
        state.sessions["preview-allcli-3"] = s3
        state.sessions["preview-allcli-4"] = s4
        state.sessions["preview-allcli-5"] = s5
        state.sessions["preview-allcli-6"] = s6
        state.sessions["preview-allcli-7"] = s7
        state.sessions["preview-allcli-8"] = s8
        state.activeSessionId = "preview-allcli-1"
        state.surface = .approvalCard(sessionId: "preview-allcli-5")
    }

    // MARK: - Idle (no sessions)

    private static func applyIdle(to state: AppState) {
        // Clear any discovered sessions, stop discovery, and block new events
        state.stopSessionDiscovery()
        state.sessions.removeAll()
        state.activeSessionId = nil
        state.surface = .collapsed
        // Continuously clear sessions to block hook events during preview
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if !state.sessions.isEmpty {
                    state.sessions.removeAll()
                    state.activeSessionId = nil
                    state.surface = .collapsed
                }
            }
        }
    }

    // MARK: - Stress Test (30 sessions)

    private static func applyStress(to state: AppState) {
        let sources = ["claude", "codex", "gemini", "cursor", "copilot", "qoder", "droid", "codebuddy", "opencode"]
        let statuses: [AgentStatus] = [.running, .processing, .idle, .waitingApproval, .waitingQuestion]
        let tools = ["Edit", "Read", "Bash", "Write", "Grep", "Agent"]
        let projects = ["frontend", "backend", "api", "mobile", "infra", "docs", "cli", "sdk", "web", "core"]

        for i in 0..<30 {
            var s = SessionSnapshot()
            s.status = statuses[i % statuses.count]
            s.cwd = "/tmp/stress-\(projects[i % projects.count])-\(i)"
            s.model = i % 3 == 0 ? "claude-opus-4-20250514" : "claude-sonnet-4-20250514"
            s.source = sources[i % sources.count]
            s.lastUserPrompt = "Task #\(i): work on \(projects[i % projects.count])"
            s.addRecentMessage(ChatMessage(isUser: true, text: "Task #\(i): work on \(projects[i % projects.count])"))
            s.addRecentMessage(ChatMessage(isUser: false, text: "Working on it. Reading files and analyzing the codebase..."))
            if s.status == .running || s.status == .processing {
                s.currentTool = tools[i % tools.count]
                s.toolDescription = "src/module\(i).swift"
            }
            for j in 0..<(i % 5) {
                s.recordTool(tools[j % tools.count], description: "file\(j).ts", success: j % 4 != 0, agentType: nil, maxHistory: 20)
            }
            if i % 7 == 0 {
                s.subagents["agent-\(i)-1"] = SubagentState(agentId: "agent-\(i)-1", agentType: "general-purpose")
            }
            s.termApp = "Ghostty"
            s.lastActivity = Date().addingTimeInterval(Double(-i * 30))
            state.sessions["preview-stress-\(i)"] = s
        }
        state.activeSessionId = "preview-stress-0"
    }
}

#if DEBUG
// MARK: - Mascot sheet
//
// `--mascot-sheet` opens a plain window with the Hatchling mascot drawn large in every mood,
// so the character can be reviewed (and captured by window id) without touching the notch.
@MainActor
enum MascotSheet {
    private static var window: NSWindow?

    static func showIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--mascot-sheet") else { return }
        let poses: [(String, HatchPose)] = [("parado", .rest), ("acenando", .wave), ("mãos pra cima", .handsUp), ("dormindo", .asleep)]
        let cast: [(String, AgentStatus, String)] = [
            ("claude", .idle, "parado"), ("codex", .running, "trabalhando"), ("gemini", .processing, "pensando"),
        ]
        let grid = VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 40) {
                ForEach(poses, id: \.0) { name, pose in
                    VStack(spacing: 12) {
                        HatchlingMascotView(source: "claude", status: .idle, size: 84, pose: pose)
                            .frame(width: 84, height: 84)
                        Text(name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            Text("Ao vivo: acenam e comemoram a cada 3 s; as mãos seguem o corpo com atraso")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 56) {
                VStack(spacing: 12) {
                    HatchlingMascotView(source: "claude", status: .idle, size: 120, global: true, pocket: true)
                        .frame(width: 120, height: 120)
                    Text("bandeja de arquivos").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                ForEach(cast, id: \.0) { source, status, label in
                    VStack(spacing: 12) {
                        HatchlingMascotView(source: source, status: status, size: 120, global: true)
                            .frame(width: 120, height: 120)
                        Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(.leading, 18)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        // `--sheet-drop` rehearses a file drop on a loop: slot opens, the file falls in.
        if ProcessInfo.processInfo.arguments.contains("--sheet-drop") {
            Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
                HatchReaction.catchStart.post()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    HatchReaction.catchEnd.post()
                    HatchReaction.swallow.post()
                }
            }
        } else {
            var flip = false
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                flip.toggle()
                (flip ? HatchReaction.wave : HatchReaction.cheer).post()
            }
        }
        let host = NSHostingView(rootView: grid)
        let w = NSWindow(contentRect: NSRect(x: 80, y: 120, width: 760, height: 620),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Mascot sheet"
        w.contentView = host
        w.setContentSize(NSSize(width: max(760, host.fittingSize.width), height: max(620, host.fittingSize.height)))
        w.orderFrontRegardless()
        window = w
    }
}
#endif
