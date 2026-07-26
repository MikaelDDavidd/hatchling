import XCTest
@testable import CodeIsland

final class TranscriptTailTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TranscriptTailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ contents: String, name: String = "transcript.jsonl") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func marker(_ line: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let value = json["mark"] as? String else { return nil }
        return value
    }

    func testReturnsNewestMatchScanningBackwards() throws {
        let url = try write([
            #"{"mark":"first"}"#,
            #"{"mark":"second"}"#,
            #"{"mark":"third"}"#
        ].joined(separator: "\n"))

        XCTAssertEqual(TranscriptTail.scanBackwards(url: url, transform: marker), "third")
    }

    func testSkipsUnparseableAndNonMatchingLines() throws {
        let url = try write([
            #"{"mark":"wanted"}"#,
            "not-json",
            #"{"other":"field"}"#,
            ""
        ].joined(separator: "\n"))

        XCTAssertEqual(TranscriptTail.scanBackwards(url: url, transform: marker), "wanted")
    }

    /// The whole point of the helper: a match near the end must be found without
    /// the window ever covering the (arbitrarily large) head of the file.
    func testFindsMatchInTailWithoutReadingWholeFile() throws {
        let filler = String(repeating: #"{"mark":null,"pad":"\#(String(repeating: "x", count: 512))"}"# + "\n", count: 400)
        let url = try write(filler + #"{"mark":"tail"}"#)

        // 4 KB window: far smaller than the ~200 KB file.
        XCTAssertEqual(
            TranscriptTail.scanBackwards(url: url, steps: [4 * 1024], transform: marker),
            "tail"
        )
    }

    /// A window that starts mid-file opens on a truncated line — it must be
    /// dropped rather than fed to the parser or crashing the UTF-8 decode.
    func testDropsTruncatedFirstLineOfWindow() throws {
        let head = #"{"mark":"head","pad":"\#(String(repeating: "y", count: 4096))"}"#
        let url = try write(head + "\n" + #"{"mark":"tail"}"#)

        XCTAssertEqual(
            TranscriptTail.scanBackwards(url: url, steps: [64], transform: marker),
            "tail"
        )
    }

    /// Multi-byte characters straddling the window boundary must not corrupt
    /// the lines that follow.
    func testHandlesMultiByteCharactersAtWindowBoundary() throws {
        let head = #"{"mark":"head","pad":"\#(String(repeating: "日本語", count: 500))"}"#
        let url = try write(head + "\n" + #"{"mark":"café ☕"}"#)

        // Sweep window sizes so several land inside the multi-byte run. The last
        // line is 20 bytes, so windows start at 21 — anything smaller can't reach
        // the newline that delimits it and correctly asks for a wider window.
        for step in stride(from: UInt64(21), through: UInt64(60), by: 1) {
            XCTAssertEqual(
                TranscriptTail.scanBackwards(url: url, steps: [step], transform: marker),
                "café ☕",
                "failed at window size \(step)"
            )
        }
    }

    /// When the first window misses, the helper widens instead of giving up.
    func testWidensWindowUntilMatchFound() throws {
        let filler = String(repeating: #"{"other":"x"}"# + "\n", count: 2000)
        let url = try write(#"{"mark":"deep"}"# + "\n" + filler + #"{"other":"last"}"#)

        XCTAssertNil(TranscriptTail.scanBackwards(url: url, steps: [128], transform: marker))
        XCTAssertEqual(
            TranscriptTail.scanBackwards(url: url, steps: [128, 1024 * 1024], transform: marker),
            "deep"
        )
    }

    func testReturnsNilForEmptyOrMissingFile() throws {
        let empty = try write("")
        XCTAssertNil(TranscriptTail.scanBackwards(url: empty, transform: marker))
        XCTAssertNil(
            TranscriptTail.scanBackwards(url: tempDir.appendingPathComponent("nope.jsonl"), transform: marker)
        )
    }
}
