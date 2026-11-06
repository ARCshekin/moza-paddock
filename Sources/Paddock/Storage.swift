import Foundation
import MozaKit

struct StoredPaddock: Codable {
    var version = 1
    var presets: [DrivePreset] = []
    var sessions: [SessionContext] = []
    var selectedPreset: UUID?
    var draft = DriveConfiguration()
}

struct PaddockStorage {
    let directory: URL
    var file: URL { directory.appendingPathComponent("paddock.json") }
    func load() throws -> StoredPaddock {
        guard FileManager.default.fileExists(atPath: file.path) else { return StoredPaddock() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredPaddock.self, from: Data(contentsOf: file))
    }
    func save(_ state: StoredPaddock) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: file, options: .atomic)
    }
}

/// A session owns an immutable config snapshot; changing the UI cannot move laps
/// into another preset. Best laps come from AC's own iBestTime, never a guess
/// that every completed lap is valid.
struct LapRecorder {
    private(set) var process: UInt32 = 0
    private var previousLap = 0
    private var pendingLap: Int?
    private var pendingSince: TimeInterval = 0
    private var lastRecorded: Int?

    mutating func consume(_ frame: PaddockGraphicFrame, now: TimeInterval, context: inout SessionContext) -> Bool {
        guard frame.pid != 0, frame.unixMilliseconds >= UInt64(context.started.timeIntervalSince1970 * 1000),
              frame.status == 2 || frame.status == 3 else { return false }
        if let expected = context.gamePID, expected != frame.pid { return false }
        if process == 0 {
            process = frame.pid; context.gamePID = frame.pid
            lastRecorded = context.laps.last?.number
            previousLap = lastRecorded ?? max(0, frame.completedLaps - 1)
        }
        guard process == frame.pid else { return false }
        if frame.completedLaps < previousLap { previousLap = frame.completedLaps; pendingLap = nil; lastRecorded = nil }
        var changed = false
        if frame.bestTime > 0, frame.bestTime < 86_400_000,
           context.bestMilliseconds == nil || frame.bestTime < context.bestMilliseconds! {
            context.bestMilliseconds = frame.bestTime; changed = true
        }
        if frame.completedLaps > previousLap {
            pendingLap = frame.completedLaps; pendingSince = now; previousLap = frame.completedLaps
        }
        if let lap = pendingLap, now - pendingSince >= 0.25, frame.lastTime > 0, frame.lastTime < 86_400_000, lastRecorded != lap {
            context.laps.append(.init(number: lap, milliseconds: frame.lastTime, matchedGameBest: frame.lastTime == frame.bestTime))
            lastRecorded = lap; pendingLap = nil; changed = true
        }
        return changed
    }
}
