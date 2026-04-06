import SwiftUI
import CodeIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case behavior
    case appearance
    case mascots
    case sound
    case hooks
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .behavior: return "slider.horizontal.3"
        case .appearance: return "paintbrush.fill"
        case .mascots: return "person.2.fill"
        case .sound: return "speaker.wave.2.fill"
        case .hooks: return "link.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .behavior: return .orange
        case .appearance: return .blue
        case .mascots: return .pink
        case .sound: return .green
        case .hooks: return .purple
        case .about: return .cyan
        }
    }
}

private struct SidebarGroup: Hashable {
    let title: String?
    let pages: [SettingsPage]
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: nil, pages: [.general, .behavior, .appearance, .mascots, .sound]),
    SidebarGroup(title: "CodeIsland", pages: [.hooks, .about]),
]

// MARK: - Main View

struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedPage: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(sidebarGroups, id: \.title) { group in
                    Section {
                        ForEach(group.pages) { page in
                            SidebarRow(page: page)
                                .tag(page)
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedPage {
                case .general: GeneralPage()
                case .behavior: BehaviorPage()
                case .appearance: AppearancePage()
                case .mascots: MascotsPage()
                case .sound: SoundPage()
                case .hooks: HooksPage()
                case .about: AboutPage()
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
    }
}

private struct PageHeader: View {
    let title: String
    var body: some View {
        EmptyView()
    }
}

private struct SidebarRow: View {
    @ObservedObject private var l10n = L10n.shared
    let page: SettingsPage

    var body: some View {
        Label {
            Text(l10n[page.rawValue])
                .font(.system(size: 13))
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - General Page

private struct GeneralPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.displayChoice) private var displayChoice = SettingsDefaults.displayChoice
    @State private var launchAtLogin: Bool

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
    }

    var body: some View {
        Form {
            Section {
                Picker(l10n["language"], selection: $l10n.language) {
                    Text(l10n["system_language"]).tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                Toggle(l10n["launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        SettingsManager.shared.launchAtLogin = v
                    }
                Picker(l10n["display"], selection: $displayChoice) {
                    Text(l10n["auto"]).tag("auto")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        let name = screen.localizedName
                        let isBuiltin = name.contains("Built-in") || name.contains("内置")
                        let hasNotch: Bool = {
                            if #available(macOS 12.0, *) {
                                return screen.auxiliaryTopLeftArea != nil
                            }
                            return false
                        }()
                        let label = isBuiltin ? l10n["builtin_display"] : name
                        Text(label).tag("screen_\(index)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior Page

private struct BehaviorPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.hideInFullscreen) private var hideInFullscreen = SettingsDefaults.hideInFullscreen
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.collapseOnMouseLeave) private var collapseOnMouseLeave = SettingsDefaults.collapseOnMouseLeave
    @AppStorage(SettingsKey.sessionTimeout) private var sessionTimeout = SettingsDefaults.sessionTimeout
    @AppStorage(SettingsKey.maxToolHistory) private var maxToolHistory = SettingsDefaults.maxToolHistory

    var body: some View {
        Form {
            Section(l10n["display_section"]) {
                BehaviorToggleRow(
                    title: l10n["hide_in_fullscreen"],
                    desc: l10n["hide_in_fullscreen_desc"],
                    isOn: $hideInFullscreen,
                    animation: .hideFullscreen
                )
                BehaviorToggleRow(
                    title: l10n["hide_when_no_session"],
                    desc: l10n["hide_when_no_session_desc"],
                    isOn: $hideWhenNoSession,
                    animation: .hideNoSession
                )
                BehaviorToggleRow(
                    title: l10n["smart_suppress"],
                    desc: l10n["smart_suppress_desc"],
                    isOn: $smartSuppress,
                    animation: .smartSuppress
                )
                BehaviorToggleRow(
                    title: l10n["collapse_on_mouse_leave"],
                    desc: l10n["collapse_on_mouse_leave_desc"],
                    isOn: $collapseOnMouseLeave,
                    animation: .collapseMouseLeave
                )
            }

            Section(l10n["sessions"]) {
                Picker(selection: $sessionTimeout) {
                    Text(l10n["no_cleanup"]).tag(0)
                    Text(l10n["10_minutes"]).tag(10)
                    Text(l10n["30_minutes"]).tag(30)
                    Text(l10n["1_hour"]).tag(60)
                    Text(l10n["2_hours"]).tag(120)
                } label: {
                    Text(l10n["session_cleanup"])
                    Text(l10n["session_cleanup_desc"])
                }
                Picker(selection: $maxToolHistory) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                } label: {
                    Text(l10n["tool_history_limit"])
                    Text(l10n["tool_history_limit_desc"])
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hooks Page

private struct HooksPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var cliStatuses: [String: Bool] = [:]
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = 0

    private func refreshCLIStatuses() {
        for cli in ConfigInstaller.allCLIs {
            cliStatuses[cli.source] = ConfigInstaller.isInstalled(source: cli.source)
        }
        cliStatuses["opencode"] = ConfigInstaller.isInstalled(source: "opencode")
    }

    private func statusText(installed: Bool, exists: Bool) -> String {
        installed ? l10n["activated"] : (exists ? l10n["not_installed"] : l10n["not_detected"])
    }

    var body: some View {
        Form {
            Section(l10n["cli_status"]) {
                ForEach(ConfigInstaller.allCLIs, id: \.source) { cli in
                    let installed = cliStatuses[cli.source] ?? false
                    let exists = ConfigInstaller.cliExists(source: cli.source)
                    CLIStatusRow(
                        name: cli.name,
                        source: cli.source,
                        configPath: "~/\(cli.configPath)",
                        fullPath: cli.fullPath,
                        installed: installed,
                        exists: exists
                    ) { _ in refreshCLIStatuses() }
                    .id("\(cli.source)-\(refreshKey)")
                }
                // OpenCode (plugin-based, not hooks)
                let ocInstalled = cliStatuses["opencode"] ?? false
                let ocExists = ConfigInstaller.cliExists(source: "opencode")
                CLIStatusRow(
                    name: "OpenCode",
                    source: "opencode",
                    configPath: "~/.config/opencode/config.json",
                    fullPath: NSHomeDirectory() + "/.config/opencode/config.json",
                    installed: ocInstalled,
                    exists: ocExists
                ) { _ in refreshCLIStatuses() }
                .id("opencode-\(refreshKey)")
            }

            Section(l10n["management"]) {
                HStack(spacing: 8) {
                    Button {
                        // Enable all detected CLIs before reinstalling
                        for cli in ConfigInstaller.allCLIs where ConfigInstaller.cliExists(source: cli.source) {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_\(cli.source)")
                        }
                        if ConfigInstaller.cliExists(source: "opencode") {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_opencode")
                        }
                        if ConfigInstaller.install() {
                            refreshCLIStatuses()
                            refreshKey += 1
                            statusMessage = l10n["hooks_installed"]
                            statusIsError = false
                        } else {
                            statusMessage = l10n["install_failed"]
                            statusIsError = true
                        }
                    } label: {
                        Text(l10n["reinstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        // Disable all CLIs before uninstalling
                        for cli in ConfigInstaller.allCLIs {
                            UserDefaults.standard.set(false, forKey: "cli_enabled_\(cli.source)")
                        }
                        UserDefaults.standard.set(false, forKey: "cli_enabled_opencode")
                        ConfigInstaller.uninstall()
                        refreshCLIStatuses()
                        refreshKey += 1
                        statusMessage = l10n["hooks_uninstalled"]
                        statusIsError = false
                    } label: {
                        Text(l10n["uninstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if !statusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCLIStatuses() }
    }
}

private struct CLIStatusRow: View {
    @ObservedObject private var l10n = L10n.shared
    let name: String
    let source: String
    let configPath: String
    let fullPath: String
    let installed: Bool
    let exists: Bool
    var onToggle: ((Bool) -> Void)?

    @State private var enabled: Bool

    init(name: String, source: String, configPath: String, fullPath: String,
         installed: Bool, exists: Bool, onToggle: ((Bool) -> Void)? = nil) {
        self.name = name
        self.source = source
        self.configPath = configPath
        self.fullPath = fullPath
        self.installed = installed
        self.exists = exists
        self.onToggle = onToggle
        _enabled = State(initialValue: ConfigInstaller.isEnabled(source: source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let icon = cliIcon(source: source, size: 20) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    if !exists {
                        Text(l10n["not_detected"])
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else if installed {
                        HStack(spacing: 2) {
                            Text(configPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                if exists {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .onChange(of: enabled) { _, newValue in
                            ConfigInstaller.setEnabled(source: source, enabled: newValue)
                            onToggle?(newValue)
                        }
                }
            }
        }
    }
}

// MARK: - Appearance Page

private struct AppearancePage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.maxPanelHeight) private var maxPanelHeight = SettingsDefaults.maxPanelHeight
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails

    private let minPanelHeight: Double = 300
    private var maxPanelHeightLimit: Double {
        let screenH = Double(NSScreen.main?.frame.height ?? 900)
        return min(max(screenH * 0.8, 500), 1200)
    }

    var body: some View {
        Form {
            Section(l10n["panel"]) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(l10n["max_panel_height"])
                        Spacer()
                        Text("\(maxPanelHeight)pt")
                            .foregroundStyle(.secondary)
                        Button(l10n["default"]) {
                            maxPanelHeight = SettingsDefaults.maxPanelHeight
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(maxPanelHeight) },
                            set: { maxPanelHeight = Int($0) }
                        ),
                        in: minPanelHeight...maxPanelHeightLimit,
                        step: 10
                    )
                }
            }

            Section(l10n["content"]) {
                Picker(l10n["content_font_size"], selection: $contentFontSize) {
                    Text("10pt").tag(10)
                    Text(l10n["11pt_default"]).tag(11)
                    Text("12pt").tag(12)
                    Text("13pt").tag(13)
                }
                Picker(l10n["ai_reply_lines"], selection: $aiMessageLines) {
                    Text(l10n["1_line_default"]).tag(1)
                    Text(l10n["2_lines"]).tag(2)
                    Text(l10n["3_lines"]).tag(3)
                    Text(l10n["5_lines"]).tag(5)
                    Text(l10n["unlimited"]).tag(0)
                }
                Toggle(l10n["show_agent_details"], isOn: $showAgentDetails)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Mascots Page

private struct MascotsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var previewStatus: AgentStatus = .processing

    private let mascotList: [(name: String, source: String, desc: String, color: Color)] = [
        ("Clawd", "claude", "Claude Code", Color(red: 0.871, green: 0.533, blue: 0.427)),
        ("Dex", "codex", "Codex (OpenAI)", Color(red: 0.92, green: 0.92, blue: 0.93)),
        ("Gemini", "gemini", "Gemini CLI", Color(red: 0.278, green: 0.588, blue: 0.894)),
        ("CursorBot", "cursor", "Cursor", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("QoderBot", "qoder", "Qoder", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("Droid", "droid", "Factory", Color(red: 0.835, green: 0.416, blue: 0.149)),
        ("Buddy", "codebuddy", "CodeBuddy", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("OpBot", "opencode", "OpenCode", Color(red: 0.55, green: 0.55, blue: 0.57)),
    ]

    var body: some View {
        Form {
            Section {
                Picker(l10n["preview_status"], selection: $previewStatus) {
                    Text(l10n["processing"]).tag(AgentStatus.processing)
                    Text(l10n["idle"]).tag(AgentStatus.idle)
                    Text(l10n["waiting_approval"]).tag(AgentStatus.waitingApproval)
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(mascotList, id: \.source) { mascot in
                    MascotRow(
                        name: mascot.name,
                        source: mascot.source,
                        desc: mascot.desc,
                        color: mascot.color,
                        status: previewStatus
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MascotRow: View {
    let name: String
    let source: String
    let desc: String
    let color: Color
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 56, height: 56)
                MascotView(source: source, status: status, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    if let icon = cliIcon(source: source, size: 16) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sound Page

private struct SoundPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = SettingsDefaults.soundVolume
    @AppStorage(SettingsKey.soundSessionStart) private var soundSessionStart = SettingsDefaults.soundSessionStart
    @AppStorage(SettingsKey.soundTaskComplete) private var soundTaskComplete = SettingsDefaults.soundTaskComplete
    @AppStorage(SettingsKey.soundTaskError) private var soundTaskError = SettingsDefaults.soundTaskError
    @AppStorage(SettingsKey.soundApprovalNeeded) private var soundApprovalNeeded = SettingsDefaults.soundApprovalNeeded
    @AppStorage(SettingsKey.soundPromptSubmit) private var soundPromptSubmit = SettingsDefaults.soundPromptSubmit
    @AppStorage(SettingsKey.soundBoot) private var soundBoot = SettingsDefaults.soundBoot

    var body: some View {
        Form {
            Section {
                Toggle(l10n["enable_sound"], isOn: $soundEnabled)
                if soundEnabled {
                    HStack(spacing: 8) {
                        Text(l10n["volume"])
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(soundVolume) },
                                set: { soundVolume = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(soundVolume)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            if soundEnabled {
                Section(l10n["sessions"]) {
                    SoundEventRow(title: l10n["session_start"], subtitle: l10n["new_claude_session"], soundName: "8bit_start", isOn: $soundSessionStart)
                    SoundEventRow(title: l10n["task_complete"], subtitle: l10n["ai_completed_reply"], soundName: "8bit_complete", isOn: $soundTaskComplete)
                    SoundEventRow(title: l10n["task_error"], subtitle: l10n["tool_or_api_error"], soundName: "8bit_error", isOn: $soundTaskError)
                }

                Section(l10n["interaction"]) {
                    SoundEventRow(title: l10n["approval_needed"], subtitle: l10n["waiting_approval_desc"], soundName: "8bit_approval", isOn: $soundApprovalNeeded)
                    SoundEventRow(title: l10n["task_confirmation"], subtitle: l10n["you_sent_message"], soundName: "8bit_submit", isOn: $soundPromptSubmit)
                }

                Section(l10n["system_section"]) {
                    SoundEventRow(title: l10n["boot_sound"], subtitle: l10n["boot_sound_desc"], soundName: "8bit_boot", isOn: $soundBoot)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundEventRow: View {
    let title: String
    var subtitle: String? = nil
    let soundName: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 16)
            Button {
                SoundManager.shared.preview(soundName)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

// MARK: - About Page

private struct AboutPage: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                AppLogoView(size: 100)

                VStack(spacing: 6) {
                    Text("CodeIsland")
                        .font(.system(size: 26, weight: .bold))
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(l10n["about_desc1"])
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(l10n["about_desc2"])
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    aboutLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/wxtsky/CodeIsland")
                    aboutLink("Issues", icon: "ladybug", url: "https://github.com/wxtsky/CodeIsland/issues")
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
    }

    private func aboutLink(_ title: String, icon: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Behavior Animation Previews

private enum BehaviorAnim {
    case hideFullscreen, hideNoSession, smartSuppress, collapseMouseLeave
}

private struct BehaviorToggleRow: View {
    let title: String
    let desc: String
    @Binding var isOn: Bool
    let animation: BehaviorAnim

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                BehaviorMiniAnim(animation: animation)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(desc)
                }
            }
        }
    }
}

/// Looping mini animation showing what a behavior setting does.
private struct BehaviorMiniAnim: View {
    let animation: BehaviorAnim
    private let w: CGFloat = 64
    private let h: CGFloat = 42

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { c, sz in
                draw(c, sz: sz, t: t)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func draw(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let bg = Color(nsColor: .windowBackgroundColor).opacity(0.6)
        c.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(bg))

        switch animation {
        case .hideFullscreen:   drawHideFullscreen(c, sz: sz, t: t)
        case .hideNoSession:    drawHideNoSession(c, sz: sz, t: t)
        case .smartSuppress:    drawSmartSuppress(c, sz: sz, t: t)
        case .collapseMouseLeave: drawCollapseMouseLeave(c, sz: sz, t: t)
        }
    }

    // Shared: draw a mini screen outline
    private func drawScreen(_ c: GraphicsContext, sz: CGSize, scale: CGFloat = 1.0) {
        let sw: CGFloat = 46 * scale
        let sh: CGFloat = 28 * scale
        let sx = (sz.width - sw) / 2
        let sy = (sz.height - sh) / 2 + 2
        let rect = CGRect(x: sx, y: sy, width: sw, height: sh)
        c.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.secondary.opacity(0.4)), lineWidth: 1)
        // Screen "content" lines
        for i in 0..<3 {
            let ly = sy + 8 + CGFloat(i) * 6
            let lw = sw * (i == 2 ? 0.4 : 0.65)
            c.fill(Path(CGRect(x: sx + 6, y: ly, width: lw, height: 2)),
                   with: .color(.secondary.opacity(0.15)))
        }
    }

    // Shared: draw a mini notch pill
    private func drawNotch(_ c: GraphicsContext, sz: CGSize, opacity: Double, expanded: Bool = false) {
        let nw: CGFloat = expanded ? 30 : 14
        let nh: CGFloat = expanded ? 14 : 5
        let nx = (sz.width - nw) / 2
        let ny: CGFloat = (sz.height - 28) / 2 + 2 - 1
        let rect = CGRect(x: nx, y: ny, width: nw, height: nh)
        c.fill(Path(roundedRect: rect, cornerRadius: nh / 2, style: .continuous),
               with: .color(Color.orange.opacity(opacity)))
    }

    // 1) Fullscreen: screen expands → notch fades
    private func drawHideFullscreen(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        // 0-0.3: normal, 0.3-0.5: expand, 0.5-0.8: fullscreen, 0.8-1: shrink back
        let scale: CGFloat = cycle < 0.3 ? 1.0 :
            cycle < 0.5 ? 1.0 + (cycle - 0.3) / 0.2 * 0.25 :
            cycle < 0.8 ? 1.25 :
            1.25 - (cycle - 0.8) / 0.2 * 0.25
        let notchOp = cycle < 0.3 ? 0.8 :
            cycle < 0.5 ? 0.8 - (cycle - 0.3) / 0.2 * 0.8 :
            cycle < 0.8 ? 0.0 :
            (cycle - 0.8) / 0.2 * 0.8
        drawScreen(c, sz: sz, scale: scale)
        drawNotch(c, sz: sz, opacity: notchOp)
    }

    // 2) No session: sessions blink out → notch fades
    private func drawHideNoSession(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        drawScreen(c, sz: sz)
        // Session dots
        let dotOp = cycle < 0.4 ? 1.0 : cycle < 0.6 ? 1.0 - (cycle - 0.4) / 0.2 : cycle < 0.85 ? 0.0 : (cycle - 0.85) / 0.15
        let cx = sz.width / 2
        let cy = sz.height / 2 + 4
        for i in 0..<2 {
            let dx: CGFloat = CGFloat(i) * 8 - 4
            c.fill(Path(ellipseIn: CGRect(x: cx + dx - 2, y: cy - 2, width: 4, height: 4)),
                   with: .color(.green.opacity(0.7 * dotOp)))
        }
        let notchOp = cycle < 0.5 ? 0.8 : cycle < 0.7 ? 0.8 - (cycle - 0.5) / 0.2 * 0.8 : cycle < 0.85 ? 0.0 : (cycle - 0.85) / 0.15 * 0.8
        drawNotch(c, sz: sz, opacity: notchOp)
    }

    // 3) Smart suppress: terminal tab comes forward → notch stays collapsed
    private func drawSmartSuppress(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        drawScreen(c, sz: sz)
        // Terminal window sliding forward
        let termOp = cycle < 0.2 ? 0.0 : cycle < 0.4 ? (cycle - 0.2) / 0.2 : cycle < 0.8 ? 1.0 : 1.0 - (cycle - 0.8) / 0.2
        let termY = sz.height / 2 + (1.0 - min(1, termOp)) * 5
        let tw: CGFloat = 28
        let th: CGFloat = 16
        let tx = (sz.width - tw) / 2
        let termRect = CGRect(x: tx, y: termY - 2, width: tw, height: th)
        c.fill(Path(roundedRect: termRect, cornerRadius: 2),
               with: .color(Color(white: 0.15).opacity(0.85 * min(1, termOp))))
        // >_ prompt
        if termOp > 0.3 {
            c.fill(Path(CGRect(x: tx + 4, y: termY + 3, width: 6, height: 1.5)),
                   with: .color(.green.opacity(0.7 * min(1, termOp))))
        }
        // Notch stays small (suppressed)
        drawNotch(c, sz: sz, opacity: 0.5)
    }

    // 4) Collapse on mouse leave: notch expands → mouse leaves → collapses
    private func drawCollapseMouseLeave(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        drawScreen(c, sz: sz)
        let expanded = cycle > 0.15 && cycle < 0.55
        let notchOp = 0.8
        drawNotch(c, sz: sz, opacity: notchOp, expanded: expanded)
        // Mouse cursor
        let cursorX: CGFloat = cycle < 0.1 ? sz.width / 2 :
            cycle < 0.15 ? sz.width / 2 :
            cycle < 0.5 ? sz.width / 2 :
            sz.width / 2 + (cycle - 0.5) / 0.2 * 20
        let cursorY: CGFloat = cycle < 0.1 ? sz.height / 2 + 10 :
            cycle < 0.15 ? sz.height / 2 + 10 - (cycle - 0.1) / 0.05 * 12 :
            cycle < 0.5 ? sz.height / 2 - 2 :
            sz.height / 2 - 2 + (cycle - 0.5) / 0.2 * 12
        let cursorOp = cycle < 0.05 ? cycle / 0.05 : cycle > 0.75 ? max(0, 1.0 - (cycle - 0.75) / 0.15) : 1.0
        // Arrow cursor shape
        var arrow = Path()
        arrow.move(to: CGPoint(x: cursorX, y: cursorY))
        arrow.addLine(to: CGPoint(x: cursorX, y: cursorY + 7))
        arrow.addLine(to: CGPoint(x: cursorX + 2, y: cursorY + 5))
        arrow.addLine(to: CGPoint(x: cursorX + 5, y: cursorY + 5))
        arrow.closeSubpath()
        c.fill(arrow, with: .color(.white.opacity(0.9 * cursorOp)))
    }
}

// MARK: - App Logo

struct AppLogoView: View {
    var size: CGFloat = 100
    var showBackground: Bool = true
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        Canvas { ctx, sz in
            let px = sz.width / 16
            if showBackground {
                let bgRect = CGRect(origin: .zero, size: sz)
                let bgPath = Path(roundedRect: bgRect, cornerRadius: sz.width * 0.22, style: .continuous)
                ctx.fill(bgPath, with: .color(.white))
                ctx.stroke(bgPath, with: .color(.black.opacity(0.08)), lineWidth: 1)
            }
            // Notch pill
            let pillColor = showBackground ? Color(white: 0.1) : Color(white: 0.5)
            let pillRect = CGRect(x: px * 3, y: px * 6, width: px * 10, height: px * 4)
            ctx.fill(Path(roundedRect: pillRect, cornerRadius: px * 2, style: .continuous), with: .color(pillColor))
            // Eyes
            ctx.fill(Path(CGRect(x: px * 5, y: px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            ctx.fill(Path(CGRect(x: px * 9, y: px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            // Pupils
            ctx.fill(Path(CGRect(x: px * 6, y: px * 7, width: px, height: px)), with: .color(.white))
            ctx.fill(Path(CGRect(x: px * 10, y: px * 7, width: px, height: px)), with: .color(.white))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(showBackground ? 0.15 : 0), radius: size * 0.12, y: size * 0.04)
    }
}
