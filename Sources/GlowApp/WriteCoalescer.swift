/// Keeps one write in flight per setting, with the newest value winning. A value with
/// nothing ahead of it is sent at once; while one is in flight only the newest proposal
/// waits, and it goes the moment the write ahead of it finishes. Values that a newer one
/// overtakes are sent without a read-back. The last value of a run is always written and
/// confirmed, and only that value's outcome is reported.
@MainActor
final class WriteCoalescer<Key: Hashable, Output> {
    struct Write {
        /// Sends the value without reading it back.
        var send: @MainActor () async throws -> Void
        /// Reads back the value `send` sent, writing it again if it didn't take.
        var confirm: @MainActor () async throws -> Output
        /// The run's outcome, for its last value only.
        var finish: @MainActor (Result<Output, any Error>) -> Void
    }

    private var waiting: [Key: Write] = [:]
    /// The run each key's drain belongs to; a dropped run's drain finds itself replaced.
    private var running: [Key: UInt64] = [:]
    private var nextRun: UInt64 = 0

    /// True from a key's first proposal until its run reports.
    func isRunning(_ key: Key) -> Bool { running[key] != nil }

    func propose(_ write: Write, for key: Key) {
        waiting[key] = write
        guard running[key] == nil else { return }
        nextRun &+= 1
        let run = nextRun
        running[key] = run
        Task { await drain(key, run: run) }
    }

    /// Forgets anything waiting for `key` and stops its run from reporting. A write already
    /// in flight still reaches the display; the pipeline keeps it ahead of whatever comes next.
    func drop(_ key: Key) {
        waiting[key] = nil
        running[key] = nil
    }

    private func drain(_ key: Key, run: UInt64) async {
        defer { if running[key] == run { running[key] = nil } }
        while running[key] == run, let write = waiting.removeValue(forKey: key) {
            do {
                try await write.send()
            } catch {
                guard running[key] == run else { return }
                // A refused write ends the run: what's waiting would be refused too.
                waiting[key] = nil
                running[key] = nil
                write.finish(.failure(error))
                return
            }
            guard running[key] == run else { return }
            if waiting[key] != nil { continue }
            let result: Result<Output, any Error>
            do {
                result = .success(try await write.confirm())
            } catch {
                result = .failure(error)
            }
            guard running[key] == run else { return }
            if waiting[key] != nil { continue }
            running[key] = nil
            write.finish(result)
        }
    }
}
