import XCTest
@testable import CodeIsland

final class CheckpointManagerTests: XCTestCase {
    private var repo: URL!

    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CheckpointTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try run("git", "init", "-q")
        // Local identity only — never touches the machine's global config.
        try run("git", "config", "user.email", "test@example.com")
        try run("git", "config", "user.name", "Test")
        try write("tracked.txt", "v1")
        try run("git", "add", "-A")
        try run("git", "commit", "-q", "-m", "initial")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    @discardableResult
    private func run(_ args: String...) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = repo
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func write(_ name: String, _ contents: String) throws {
        try contents.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(name), encoding: .utf8)
    }

    func testCreatesCheckpointCapturingTrackedAndUntrackedFiles() throws {
        try write("tracked.txt", "v2")
        try write("untracked.txt", "new file")

        let checkpoint = try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: repo.path)
        XCTAssertTrue(checkpoint.id.hasPrefix("refs/hatchling-snapshots/demo/"))

        let listed = CheckpointManager.checkpoints(for: "demo", in: repo.path)
        XCTAssertEqual(listed.count, 1)

        // Both files are in the snapshot's tree
        let tree = try run("git", "ls-tree", "--name-only", "-r", checkpoint.id)
        XCTAssertTrue(tree.contains("tracked.txt"))
        XCTAssertTrue(tree.contains("untracked.txt"))
    }

    /// The whole point of the temp index: the user's staging area must be untouched.
    func testDoesNotDisturbStagingAreaOrHead() throws {
        try write("staged.txt", "staged content")
        try run("git", "add", "staged.txt")
        let stagedBefore = try run("git", "diff", "--cached", "--name-only")
        let headBefore = try run("git", "rev-parse", "HEAD")
        let branchBefore = try run("git", "rev-parse", "--abbrev-ref", "HEAD")

        try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: repo.path)

        XCTAssertEqual(try run("git", "diff", "--cached", "--name-only"), stagedBefore)
        XCTAssertEqual(try run("git", "rev-parse", "HEAD"), headBefore)
        XCTAssertEqual(try run("git", "rev-parse", "--abbrev-ref", "HEAD"), branchBefore)
    }

    /// Snapshots stay out of the branch history and the branch list.
    ///
    /// They are *not* hidden from `git log --all`, which walks every ref
    /// including custom ones — that's inherent to storing them as refs, and is
    /// why they live under a clearly-named namespace.
    func testCheckpointStaysOutOfBranchHistory() throws {
        let branchLogBefore = try run("git", "log", "--oneline")
        let branchesBefore = try run("git", "branch", "--list")

        try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: repo.path)

        XCTAssertEqual(try run("git", "log", "--oneline"), branchLogBefore)
        XCTAssertEqual(try run("git", "branch", "--list"), branchesBefore)

        // Documents the known trade-off: --all does surface them.
        let allLog = try run("git", "log", "--oneline", "--all")
        XCTAssertTrue(allLog.contains("Hatchling checkpoint"))
    }

    func testRestoreBringsBackSnapshotContents() throws {
        try write("tracked.txt", "before checkpoint")
        let checkpoint = try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: repo.path)

        try write("tracked.txt", "agent wrecked this")
        XCTAssertEqual(try read("tracked.txt"), "agent wrecked this")

        try CheckpointManager.restoreCheckpoint(checkpoint, to: repo.path)
        XCTAssertEqual(try read("tracked.txt"), "before checkpoint")
    }

    func testDeleteAndClearRemoveRefs() throws {
        let first = try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: repo.path)
        try CheckpointManager.deleteCheckpoint(first, in: repo.path)
        XCTAssertTrue(CheckpointManager.checkpoints(for: "demo", in: repo.path).isEmpty)

        try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: repo.path)
        CheckpointManager.clearCheckpoints(for: "demo", in: repo.path)
        XCTAssertTrue(CheckpointManager.checkpoints(for: "demo", in: repo.path).isEmpty)
    }

    func testProjectNamesWithSpacesProduceValidRefs() throws {
        let checkpoint = try CheckpointManager.createCheckpoint(
            projectName: "My Project",
            projectDirectory: repo.path
        )
        XCTAssertFalse(checkpoint.id.contains(" "))
        XCTAssertEqual(CheckpointManager.checkpoints(for: "My Project", in: repo.path).count, 1)
    }

    func testThrowsOutsideAGitRepository() throws {
        let plain = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotARepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }

        XCTAssertThrowsError(
            try CheckpointManager.createCheckpoint(projectName: "demo", projectDirectory: plain.path)
        )
    }
}
