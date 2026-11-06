import Foundation
import MozaKit

enum PaddockChecks {
    static func run() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("paddock-check-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw PaddockError(label) }
            print("PASS \(label)")
        }
        let input = INI("[STEER]\r\nJOY=0 ; wheel\r\nLOCK=900\n[OTHER]\nKEEP=hello=world\n")
        try check(input["STEER", "JOY"] == "0" && INI(input.text)["OTHER", "KEEP"] == "hello=world", "INI round trip and inline comments")
        try check(PaddockController.gamePIDs(in: " 123 acs.exe \n124 C:/Program Files/assettocorsa/acs.exe \n125 /winewrapper.exe --run C:/acs.exe \n126 /bin/zsh -c ps\n") == [123, 124], "game process detection accepts relative and absolute launch commands")
        var configuration = DriveConfiguration()
        let fingerprint = configuration.fingerprint
        configuration.angle = 540
        try check(configuration.fingerprint != fingerprint, "different settings have separate record keys")
        configuration.mode = .race; configuration.opponents = 3
        configuration.setup = "magione/test.ini"
        configuration.bindings = ["GEARUP": 14, "GEARDN": 13, "DRS": 2]
        let paths = PaddockPaths(project: PaddockPaths.current.project, bottle: "Steam-3", documentsOverride: temp.appendingPathComponent("Documents"), storeOverride: temp.appendingPathComponent("Store"))
        try ConfigurationWriter.write(configuration, paths: paths)
        let cfg = paths.documents.appendingPathComponent("cfg")
        let controls = INI(url: cfg.appendingPathComponent("controls.ini"))
        let race = INI(url: cfg.appendingPathComponent("race.ini"))
        try check(controls["GEARUP", "BUTTON"] == "13" && controls["GEARDN", "BUTTON"] == "12", "HID buttons become zero-based AC bindings")
        try check(controls["STEER", "LOCK"] == "540" && controls["ACTION_HORN", "JOY"] == "-1", "wheel angle and unassigned actions")
        try check(race["RACE", "CARS"] == "4" && race["CAR_3", "MODEL"] == configuration.car && race["SESSION_0", "TYPE"] == "3", "race mode creates AI grid")
        try check(race["CAR_0", "SETUP"] == "magione\\test.ini", "car setup ID preserves track directory in Windows form")
        configuration.mode = .hotlap
        try ConfigurationWriter.write(configuration, paths: paths)
        let hotlap = INI(url: cfg.appendingPathComponent("race.ini"))
        try check(hotlap["RACE", "CARS"] == "1" && hotlap.sections["CAR_3"] == nil && hotlap["SESSION_0", "SPAWN_SET"] == "HOTLAP_START", "mode switch clears previous grid")
        let storage = PaddockStorage(directory: paths.store)
        let preset = DrivePreset(name: "Test", configuration: configuration)
        try storage.save(.init(presets: [preset], sessions: [], selectedPreset: preset.id, draft: configuration))
        let loaded = try storage.load()
        try check(loaded.presets.count == 1 && loaded.draft == configuration && loaded.selectedPreset == preset.id, "presets and draft persist atomically")
        var session = SessionContext(presetID: preset.id, presetName: preset.name, configuration: configuration, carName: "Test Car", trackName: "Test Track", started: Date(timeIntervalSince1970: 100))
        func frame(pid: UInt32 = 42, lap: Int, last: Int, best: Int) -> PaddockGraphicFrame {
            var bytes = [UInt8](repeating: 0, count: 296)
            func put(_ offset: Int, _ value: Int) { for i in 0..<4 { bytes[offset+i] = UInt8(truncatingIfNeeded: UInt32(value) >> (8*i)) } }
            put(4, 2); put(132, lap); put(144, last); put(148, best)
            return PaddockGraphicFrame(pid: pid, unixMilliseconds: 110_000, bytes: bytes)!
        }
        var recorder = LapRecorder()
        _ = recorder.consume(frame(lap: 0, last: 0, best: 0), now: 0, context: &session)
        _ = recorder.consume(frame(lap: 1, last: 80_123, best: 80_123), now: 1, context: &session)
        _ = recorder.consume(frame(lap: 1, last: 80_123, best: 80_123), now: 1.4, context: &session)
        _ = recorder.consume(frame(lap: 1, last: 80_123, best: 80_123), now: 2, context: &session)
        try check(session.laps.count == 1 && session.bestMilliseconds == 80_123 && session.laps[0].matchedGameBest, "lap transition records once after settling")
        _ = recorder.consume(frame(pid: 99, lap: 2, last: 10_000, best: 10_000), now: 3, context: &session)
        try check(session.bestMilliseconds == 80_123, "another game's PID cannot contaminate records")
        var resumed = LapRecorder()
        _ = resumed.consume(frame(lap: 1, last: 80_123, best: 80_123), now: 4, context: &session)
        _ = resumed.consume(frame(lap: 1, last: 80_123, best: 80_123), now: 5, context: &session)
        try check(session.laps.count == 1, "resume does not duplicate recorded laps")
        try check(lapText(80_123) == "1:20.123", "lap formatting")
        let actual = try ContentLibrary.scan(PaddockPaths.current.game)
        try check(actual.cars.contains { $0.id == "lotus_elise_sc" } && actual.tracks.contains { $0.id == "magione" }, "installed car/track metadata scanning")
        print("Library: \(actual.cars.count) cars, \(actual.tracks.count) tracks, \(actual.weather.count) weather presets")
        print("All Paddock checks passed; no live game config or hardware changed.")
    }
}
