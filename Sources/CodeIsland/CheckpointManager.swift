import Foundation

/// A working-tree snapshot stored as an orphan git commit under a custom ref.
struct Checkpoint: Identifiable, Equatable {
    let id: String          // full ref name
    let date: Date
    let commitHash: String

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum CheckpointError: LocalizedError {
    case gitFailed(String)
    case notAGitRepo

    var errorDescription: String? {
        switch self {
        case .gitFailed(let msg): return "Git error: \(msg)"
        case .notAGitRepo: return "Directory is not a git repository"
        }
    }
}

/// Snapshots a project's working tree before an agent edits it.
///
/// Nothing the user can see is touched: staging happens in a throwaway index
/// (`GIT_INDEX_FILE`), the snapshot is an orphan commit (no parent, not on any
/// branch), and it lives under `refs/hatchling-snapshots/…` — so `git log`,
/// branches and the staging area all stay exactly as they were.
///
/// Ported from Notchy (MIT, Copyright (c) 2026 Adam Lyttle) —
/// https://github.com/bones7456/notchy
enum CheckpointManager {
    private static let refPrefix = "refs/hatchling-snapshots"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    @discardableResult
    private static func git(
        _ args: [String],
        in directory: String,
        environment: [String: String]? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        if let environment {
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        // Read before waiting: a pipe that fills up would deadlock the child.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            throw CheckpointError.gitFailed(errOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    static func isGitRepository(_ directory: String) -> Bool {
        (try? git(["rev-parse", "--git-dir"], in: directory)) != nil
    }

    /// Captures the full working tree, including untracked files.
    @discardableResult
    static func createCheckpoint(projectName: String, projectDirectory: String) throws -> Checkpoint {
        guard isGitRepository(projectDirectory) else { throw CheckpointError.notAGitRepo }

        let now = Date()
        let timestamp = dateFormatter.string(from: now)
        let refName = "\(refPrefix)/\(sanitize(projectName))/\(timestamp)"

        let tempIndex = NSTemporaryDirectory() + "hatchling-index-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempIndex) }
        let env = ["GIT_INDEX_FILE": tempIndex]

        try git(["add", "-A"], in: projectDirectory, environment: env)

        let tree = try git(["write-tree"], in: projectDirectory, environment: env)
        guard !tree.isEmpty else { throw CheckpointError.gitFailed("write-tree produced no output") }

        // `commit-tree` needs an author identity. Supply our own so the snapshot
        // works in repos where the user never set user.name/user.email, without
        // writing anything into their git config.
        let identity = [
            "GIT_AUTHOR_NAME": "Hatchling",
            "GIT_AUTHOR_EMAIL": "hatchling@localhost",
            "GIT_COMMITTER_NAME": "Hatchling",
            "GIT_COMMITTER_EMAIL": "hatchling@localhost",
        ]
        let commit = try git(
            ["commit-tree", tree, "-m", "Hatchling checkpoint \(timestamp)"],
            in: projectDirectory,
            environment: identity
        )
        guard !commit.isEmpty else { throw CheckpointError.gitFailed("commit-tree produced no output") }

        try git(["update-ref", refName, commit], in: projectDirectory)
        return Checkpoint(id: refName, date: now, commitHash: String(commit.prefix(7)))
    }

    /// Newest first.
    static func checkpoints(for projectName: String, in projectDirectory: String) -> [Checkpoint] {
        let refPattern = "\(refPrefix)/\(sanitize(projectName))/"
        guard let output = try? git(
            ["for-each-ref", "--format=%(refname) %(objectname:short)", refPattern],
            in: projectDirectory
        ), !output.isEmpty else {
            return []
        }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let refName = String(parts[0])
            let hash = String(parts[1])
            guard let lastSlash = refName.lastIndex(of: "/") else { return nil }
            let timestamp = String(refName[refName.index(after: lastSlash)...])
            guard let date = dateFormatter.date(from: timestamp) else { return nil }
            return Checkpoint(id: refName, date: date, commitHash: hash)
        }
        .sorted { $0.date > $1.date }
    }

    /// Overwrites the working tree with the snapshot's contents.
    static func restoreCheckpoint(_ checkpoint: Checkpoint, to projectDirectory: String) throws {
        try git(["checkout", checkpoint.commitHash, "--", "."], in: projectDirectory)
    }

    static func deleteCheckpoint(_ checkpoint: Checkpoint, in projectDirectory: String) throws {
        try git(["update-ref", "-d", checkpoint.id], in: projectDirectory)
    }

    static func clearCheckpoints(for projectName: String, in projectDirectory: String) {
        for checkpoint in checkpoints(for: projectName, in: projectDirectory) {
            _ = try? git(["update-ref", "-d", checkpoint.id], in: projectDirectory)
        }
    }

    /// Ref components can't contain spaces or the other characters git rejects.
    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: " ~^:?*[\\@{")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "project" : cleaned
    }
}
