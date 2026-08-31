# Changelog

## [v0.4.0] - 2026-08-31

### Added
- **A companion app for the phone.** Hatchling now serves its state over a
  relay, so an iOS or Android device can watch every session, read the
  conversation, answer a permission prompt or a question, send a prompt, and
  interrupt a run — from anywhere, not just from the machine the agents are
  working on. Pairing is a code shown on the Mac and typed into the phone.
- **The conversation, in the panel.** Clicking a session opens what was
  actually said, paged straight off the CLI's own transcript so nothing is
  cached and nothing goes stale. The terminal is still one click away; this is
  for reading.
- **Agent messages render as markdown.** Headings, bullets that keep their own
  numbering, fenced code, rules, and inline bold, italics and code spans.
  Tables are stacked rather than gridded — a three-column table in a panel this
  narrow is unreadable at any font size — so each row becomes a small block led
  by its first cell. What you typed stays literal.
- **Rate limits reach the phone**, so the usage bars are the same on both.

### Changed
- **The chat reads as a conversation instead of a stack of tool calls.** An
  assistant turn reaches the transcript a line per block, so a sentence and each
  tool call it made were being shown as separate turns — a column of near-empty
  cards, one per tool, each with its own speaker label. Entries that are nothing
  but a tool call now fold into the sentence that announced them, and repeated
  tools collapse into one chip with a count.

### Fixed
- **The panel stopped redrawing itself 120 times a second.** Hatchling sat at
  ~15% of a core doing nothing. Profiling found the drawing was 2% of it: the
  cost was AppKit holding the window in continuous-layout mode, which it does
  for as long as anything asks to redraw more often than every 250ms — and the
  mascots ticked every 0.03s. It is a cliff, not a slope: a 0.25s cadence
  measured 4.3% CPU, 0.26s measured 0.4%, and below the threshold the cost is
  the same whether it ticks 4 or 33 times a second. That is why drawing less,
  showing fewer mascots, and turning the animation-speed slider to zero had all
  changed nothing. The mascots now tick past the cliff, and the status shimmer
  moved to Core Animation, which the window server interpolates without waking
  the app. Measured on the running app: mean 14.9% → 4.0%, median 14.1% → 2.8%.
- **Permission and question cards never said which session was asking.**

## [v0.3.1] - 2026-07-28

### Fixed
- **The session list no longer disappears when you have a lot of sessions.**
  Above `maxVisibleSessions` (5 by default) the list is wrapped in a scroll
  view, and that scroll view had no height constraint. `NSScrollView` has no
  `intrinsicContentSize`, so SwiftUI resolved it to 0pt and the entire list
  vanished — the header, status pill and usage bar stayed, so the panel looked
  like it had found no sessions at all. With five sessions or fewer the list
  renders directly and was never affected, which is what made it look
  intermittent. Its height now tracks the content, and still stops at the cap.
- **The last session card was clipped when the list was full.** The panel
  window reserved 60pt above the list, which did not cover the notch strip,
  divider, status pill and usage bar. Raised to 140pt.
- **Answering a multiple-choice question now reaches the agent.** Answers were
  keyed by each question's `header`, but `AskUserQuestion` expects them keyed by
  the question *text* — the sibling `annotations` field is documented that way.
  Answers came back and were silently ignored.
- **The statusline wrapper never captured rate limits.** It fed the payload to
  the statusline command through a heredoc while that command was already
  reading stdin, so the two conflicted and the limits were dropped. It now reads
  the payload from the file it had just written.
- **Claude and Codex usage bars were both green**, so only the badge told them
  apart. Each CLI now keeps its own colour until usage climbs; from 70% the
  alert colour takes over.
- **The checkpoint shortcut showed its raw localisation key** in Settings.

## [v0.3.0] - 2026-07-26

### Fixed
- **The app no longer hangs on launch.** `CodexUsageLoader` read every Codex
  rollout with `String(contentsOf:)` and walked it with `enumerateLines`, on the
  main thread — a 4.4 GB rollout pulled the whole file into memory and stalled
  before the UI ever drew. Rollouts are now read from the tail backwards, in
  bounded windows, off the main thread. Same 4.4 GB file: never finished → 14 ms,
  40 MB footprint. The fallback sweep is also capped at the 8 newest rollouts
  instead of walking the entire session history.
- **Multiple-choice questions work again.** Answering one used to crash the
  client ("H.map"), which is why the feature had been switched off. A
  `PermissionRequest` hook's `updatedInput` *replaces* the tool's whole input and
  must still match its schema; we were sending only `{"answers": …}` and dropping
  `questions`, so the client mapped over an undefined array. Answers are now
  merged into the original input. There's a Settings toggle to turn the feature
  on and off without a rebuild.
- **Codex Desktop sessions are discovered.** One Electron process serves many
  VS Code workspaces and its cwd is always `/`, so rollouts are matched by their
  own `payload.cwd` instead of the process cwd.

### Added
- **Git checkpoints.** Snapshot the working tree before an agent edits it, as an
  orphan commit under `refs/hatchling-snapshots/`. Staging happens in a throwaway
  index, so your staging area, HEAD and branch list are untouched. Bindable
  shortcut, no default binding.
- **Quiet during calls.** Sounds are skipped while the default input device is in
  use, so notifications don't fire mid-meeting. On by default.
- **Sleep prevention.** The Mac won't idle-sleep while an agent is working.
- **New sound set.** Two sounds adapted from Notchy (task complete, approval
  needed) plus four chiptune pieces synthesised for this project — NES-style
  pulse waves with decay envelopes and major-scale arpeggios. Repeats are
  debounced per sound.
- **Collapse button** in the expanded panel; a force-collapsed pending question
  reopens on the next hover instead of being lost.

### Changed
- Rate-limit polling parses off the main thread and only republishes when the
  value actually changed — it used to reassign its published state every 10s and
  redraw the notch forever.
- Discovery scans memoise process metadata for the duration of one scan, instead
  of re-issuing `proc_pidpath` and `KERN_PROCARGS2` once per enabled source.
- The sleeping mascot's floating z's are drawn into its canvas rather than
  rebuilt as `Text` views 20×/s.

### Docs
- `THIRD-PARTY.md` credits what was ported from
  [`bones7456/notchy`](https://github.com/bones7456/notchy) (MIT, Adam Lyttle).
- README gains a Support section (Buy Me a Coffee, GitHub Sponsors).

## [v0.2.0] - 2026-05-09

### Added
- **Files tray.** New `FILES` tab on the expanded notch — drag files onto the
  tray to keep them handy, then drag them out into any Finder window when
  you need them. Files are copied into `~/Library/Application Support/Hatchling/tray/`,
  so renaming or moving the original doesn't break the tray.
- **Notes.** New `NOTES` tab with a horizontal carousel of sticky notes.
  Click a note to expand it inline into a full editor, right-click for color
  cycling and delete. Persisted to `~/Library/Application Support/Hatchling/notes.json`.
- **Auto-expand on file drag.** Drag a file from anywhere onto the collapsed
  notch and the panel expands straight to the `FILES` tab so you can drop it
  in one motion.

### Changed
- The old `ALL / STA / CLI` session-grouping pills were replaced by the new
  top-level `FILES / NOTES / AGENTS` tab selector. The `AGENTS` tab keeps the
  full session list view that lived behind those pills.

## [v1.0.15] - 2026-04-07

### English
- Fix apps built with libghostty (e.g. Supacode) being misidentified as Ghostty (#27)
- Fix DMG release missing app icon by pre-building icns with all sizes
- Fix settings window opaque sidebar in .app bundle (add toolbar for translucent effect)
- Build universal binary (arm64 + x86_64) for DMG releases
- Use root Info.plist for DMG builds to include all required fields

### 中文
- 修复基于 libghostty 构建的应用（如 Supacode）被误识别为 Ghostty 的问题 (#27)
- 修复 DMG 发行版缺少应用图标的问题（预置完整尺寸 icns）
- 修复 .app 版本设置窗口侧边栏不透明的问题（添加 toolbar 实现毛玻璃效果）
- DMG 发行版改为 universal binary（arm64 + x86_64）
- DMG 构建使用完整 Info.plist，包含所有必要字段

## [v1.0.8] - 2026-04-07

### English
- Add GitHub Copilot CLI support as the 9th AI tool
- Allow horizontal drag of panel along the menu bar (Settings → General)
- Horizontal-only drag with no vertical jitter, 5px threshold to prevent accidental drag
- Reset panel to center when drag toggle is turned off
- Update mascot gif backgrounds to white for better README readability

### 中文
- 新增 GitHub Copilot CLI 支持（第 9 个 AI 工具）
- 允许沿菜单栏水平拖动面板（设置 → 通用）
- 仅水平拖动无垂直抖动，5px 阈值防误触
- 关闭拖动开关时面板自动归位居中
- 更新吉祥物 gif 为白色背景，提升 README 可读性

## [v1.0.7] - 2026-04-07

### English
- Add Homebrew Cask distribution support (`brew install --cask codeisland`)
- Add in-app auto-update: download, install and relaunch without leaving the app
- Add "Check for Updates" button in Settings → About
- Detect Homebrew installs and suggest `brew upgrade` instead of auto-update
- Add GitHub Actions CI for automated release builds
- Auto-approve safe internal tools (TaskCreate, TaskUpdate, etc.) to prevent hook blocking
- Fix compact bar showing project name and tool status from different sessions
- Fix restored sessions incorrectly shown as active when CLI process is idle
- Hide project name in tool status area when no tool is running

### 中文
- 新增 Homebrew Cask 分发支持（`brew install --cask codeisland`）
- 新增 App 内自动更新：下载、安装并重启，无需离开应用
- 设置 → 关于页面新增"检查更新"按钮
- 检测 Homebrew 安装并建议使用 `brew upgrade` 更新
- 新增 GitHub Actions CI 自动构建发布
- 自动放行安全内部工具（TaskCreate、TaskUpdate 等），防止 hook 阻塞
- 修复紧凑栏项目名和工具状态来自不同会话的问题
- 修复恢复的会话在 CLI 空闲时仍显示为活跃状态
- 修复无工具运行时仍显示项目名的问题

## [v1.0.6] - 2026-04-07

### English
- Show Claude and Codex session titles in the panel
- New idle state UI with hover interaction on the notch
- Add shimmer animation when AI is thinking
- Extend animation speed slider to 0% to freeze mascot animations
- Add Codex PreToolUse/PostToolUse hook events for tool status display
- Auto-configure codex_hooks=true in ~/.codex/config.toml
- Add IDE terminal detection for smarter notification suppress
- Add cmux terminal support
- Fix user messages rendered as markdown instead of plain text
- Add processing timeout fallback: reset to idle after 60s with no tool
- Fix idle mascot not aligned with the most recently active CLI

### 中文
- Claude 和 Codex 会话现在在面板中显示标题
- 新增空闲状态 UI，支持刘海区域悬停交互
- AI 思考时显示闪烁动画效果
- 动画速度滑块可调至 0% 以冻结吉祥物动画
- 新增 Codex PreToolUse/PostToolUse hook 事件，显示工具状态
- 自动配置 ~/.codex/config.toml 中的 codex_hooks=true
- 新增 IDE 终端检测，更智能的通知抑制
- 新增 cmux 终端支持
- 修复用户消息被渲染为 markdown 而非纯文本
- 增加处理超时回退：60 秒无工具调用后重置为空闲
- 修复空闲吉祥物未对齐最近活跃的 CLI

## [v1.0.5] - 2026-04-06

### English
- Smart suppress: only suppress notifications when looking at the specific session tab
- Support iTerm2, Ghostty, Terminal.app, WezTerm, kitty, and tmux tab detection
- Fix Codex Desktop not discovered due to case-sensitive path matching
- Fix npm/Homebrew Codex not discovered
- Fix OpenCode "Always allow" not persisting
- Fix model badge not showing
- Fix session short ID collision
- Fix bridge binary replacement drop window
- Fix hook script not updating for existing users
- Fix concurrent sessions in same repo incorrectly merged

### 中文
- 智能抑制：只有当你正在看该会话的标签页时才抑制通知
- 支持 iTerm2、Ghostty、Terminal.app、WezTerm、kitty、tmux 标签页检测
- 修复 Codex Desktop 因路径大小写不匹配无法发现
- 修复 npm/Homebrew 安装的 Codex 无法发现
- 修复 OpenCode "始终允许"没有持久化
- 修复 model 标签不显示
- 修复会话短 ID 冲突
- 修复 bridge 二进制替换存在时间窗口
- 修复已安装用户的 hook 脚本不会更新
- 修复同 repo 并发会话被错误合并

## [v1.0.4] - 2026-04-06

### English
- Fix OpenCode socket deadlock
- Fix stuck session states
- Fix AskUserQuestion parsing
- Fix double-click on outside click
- Performance: cache status/primarySource/activeSessionCount, reduce observation polling
- UI: smooth hover animations, panel collapse delay, entrance transitions

### 中文
- 修复 OpenCode socket 死锁
- 修复会话状态卡住
- 修复 AskUserQuestion 解析
- 修复外部点击双击问题
- 性能优化：缓存状态属性，减少轮询频率
- UI：平滑悬停动画，面板折叠延迟，入场过渡动画

## [v1.0.3] - 2026-04-06

### English
- Update checker: auto-check on launch + manual check
- Per-CLI hook toggles
- Boot sound: 8-bit startup jingle
- Behavior animations: animated previews for each setting
- Fix release build crash, OpenCode plugin install, hook fallback socket path

### 中文
- 更新检查器：启动时自动检查 + 手动检查
- 按 CLI 独立开关 hooks
- 启动音效：8-bit 开机音
- 行为动画：每个设置项的动画预览
- 修复发布版本崩溃、OpenCode 插件安装、hook socket 路径回退

## [v1.0.1] - 2026-04-06

### English
- Fix release build crash on Mascots/Hooks pages
- Fix OpenCode plugin installation in release builds
- Fix hook script fallback socket path
- Remove redundant page titles in settings

### 中文
- 修复吉祥物和 Hooks 设置页崩溃
- 修复发布版本中 OpenCode 插件安装
- 修复 hook 脚本 socket 路径回退
- 移除设置中多余的页面标题

## [v1.0.0] - 2026-04-06

### English
- Initial release

### 中文
- 初始发布
