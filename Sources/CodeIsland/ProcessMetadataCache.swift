import Foundation

/// Memoizes process metadata for the duration of a single discovery scan.
///
/// A scan asks every enabled source to filter the same few hundred pids, and each
/// filter independently re-issued `proc_pidpath` — and, for the sources that match
/// on argv, the far pricier `KERN_PROCARGS2` sysctl — for every pid. With ~650
/// processes and a dozen argv-matching sources that is thousands of redundant
/// syscalls every few seconds. Scoping a cache to one scan collapses it to one
/// lookup per pid.
///
/// Deliberately scan-scoped rather than time-based: a stale entry would resurrect
/// a dead process, and pid reuse across scans would be a correctness bug.
final class ProcessMetadataCache: @unchecked Sendable {
    private var paths: [pid_t: String?] = [:]
    private var args: [pid_t: [String]?] = [:]
    private let lock = NSLock()

    func path(for pid: pid_t, compute: (pid_t) -> String?) -> String? {
        lock.lock()
        if let cached = paths[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let value = compute(pid)

        lock.lock()
        paths[pid] = value
        lock.unlock()
        return value
    }

    func args(for pid: pid_t, compute: (pid_t) -> [String]?) -> [String]? {
        lock.lock()
        if let cached = args[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let value = compute(pid)

        lock.lock()
        args[pid] = value
        lock.unlock()
        return value
    }
}

/// Task-local handle so the cache reaches the `nonisolated static` scan helpers
/// without threading a parameter through every `find*Pids` signature. Nil outside
/// a scan, where callers fall back to querying the kernel directly.
enum ProcessScan {
    @TaskLocal static var cache: ProcessMetadataCache?

    /// Runs `body` with a fresh cache that dies with the scan.
    static func withCache<T>(_ body: () throws -> T) rethrows -> T {
        try $cache.withValue(ProcessMetadataCache(), operation: body)
    }
}
