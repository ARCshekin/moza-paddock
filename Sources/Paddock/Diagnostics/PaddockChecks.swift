import Foundation
import MozaKit

enum PaddockChecks {
    static func run(includeInstalledGame: Bool = true) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("paddock-check-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw PaddockError(label) }
            print("PASS \(label)")
        }
        var shaped = WheelInputSettings()
        try check(abs(shaped.steering(0.5) - 0.5) < 0.00001, "default steering remains linear")
        shaped.steeringGamma = 2; shaped.steeringDeadzone = 0.1
        try check(shaped.steering(0.05) == 0 && shaped.steering(1) == 1 && shaped.steering(-1) == -1, "steering curve respects deadzone, saturation and symmetry")
        let original = DriveConfiguration()
        let encoded = try JSONEncoder().encode(original)
        try check(!String(decoding: encoded, as: UTF8.self).contains("\"wheel\""), "legacy configurations retain record fingerprints when wheel settings are default")
        let old = try JSONDecoder().decode(DriveConfiguration.self, from: encoded)
        try check(old.wheel == nil, "old presets load with default wheel settings")
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
        configuration.wheelSettings = shaped
        configuration.bindings["BRIDGE_CLUTCH"] = 40
        configuration.bindings["BRIDGE_ESCAPE"] = 39
        configuration.bindings["__EXT_PIT_LIMITER"] = 32
        let paths = PaddockPaths(project: PaddockPaths.current.project, bottle: "Steam-3", documentsOverride: temp.appendingPathComponent("Documents"), storeOverride: temp.appendingPathComponent("Store"))
        var independent = paths; independent.runtime = .standalone
        try check(independent.bottleURL == paths.store.appendingPathComponent("Prefixes/assetto") && independent.game != paths.game && independent.documents == paths.documents, "runtime switch isolates prefix while preserving Documents")
        let invocation = WineProcess.arguments(paths: independent, arguments: ["reg", "query", "HKCU\\Software\\Valve\\Steam"])
        try check(invocation.contains("standalone") && invocation.suffix(3) == ["reg", "query", "HKCU\\Software\\Valve\\Steam"], "Wine arguments retain Windows registry paths without shell interpolation")
        try ConfigurationWriter.write(configuration, paths: paths)
        let bridgeControls = try JSONDecoder().decode(BridgeControlConfiguration.self, from: Data(contentsOf: paths.store.appendingPathComponent(WheelInputSettings.fileName)))
        try check(bridgeControls.bindings["BRIDGE_CLUTCH"] == 40 && bridgeControls.actions(pressed: [39]) == 1, "buttons 39 and 40 reach native clutch and Escape configuration")
        let cfg = paths.documents.appendingPathComponent("cfg")
        let controls = INI(url: cfg.appendingPathComponent("controls.ini"))
        let race = INI(url: cfg.appendingPathComponent("race.ini"))
        try check(race["HEADER", "VERSION"] == "2", "fresh race configuration declares the AC session format")
        try check((0..<4).allSatisfy { race.sections["CAR_\($0)"]?["MODEL_CONFIG"] == "" }, "player and AI entries include required MODEL_CONFIG even when empty")
        try check(race["CAR_0", "MODEL"] == "-", "player entry preserves AC model fallback to RACE/MODEL")
        try check(controls["GEARUP", "BUTTON"] == "13" && controls["GEARDN", "BUTTON"] == "12", "HID buttons become zero-based AC bindings")
        try check(controls["STEER", "LOCK"] == "540" && controls["ACTION_HORN", "JOY"] == "-1", "wheel angle and unassigned actions")
        try check(race["RACE", "CARS"] == "4" && race["CAR_3", "MODEL"] == configuration.car && race["SESSION_0", "TYPE"] == "3", "race mode creates AI grid")
        try check(race["CAR_0", "SETUP"] == "magione\\test.ini", "car setup ID preserves track directory in Windows form")
        configuration.mode = .hotlap
        try ConfigurationWriter.write(configuration, paths: paths)
        let hotlap = INI(url: cfg.appendingPathComponent("race.ini"))
        try check(hotlap["RACE", "CARS"] == "1" && hotlap.sections["CAR_3"] == nil && hotlap["SESSION_0", "SPAWN_SET"] == "HOTLAP_START", "mode switch clears previous grid")
        let server = OnlineServerDetails(host: "127.0.0.1", httpPort: 8081, racePort: 9600, name: "Test server", track: "magione", cars: [configuration.car], free: [configuration.car: 1], clients: 0, capacity: 1, password: true, pickup: true, csp: false, latency: 1)
        let connection = OnlineConnection(server: server, car: configuration.car, player: "Test Driver", password: "test-secret")
        try connection.write(paths: paths, guid: "76561198000000000")
        let remote = INI(url: cfg.appendingPathComponent("race.ini"))
        try check(remote["REMOTE", "SERVER_PORT"] == "9600" && remote["REMOTE", "SERVER_HTTP_PORT"] == "8081" && remote["CAR_0", "DRIVER_NAME"] == "Test Driver", "online uses TCP race port separately from HTTP discovery port")
        var rejected = false
        do { try OnlineConnection(server: server, car: configuration.car, player: "bad\n[REMOTE]", password: "").validate(paths: paths) } catch { rejected = true }
        try check(rejected, "online rejects INI injection in transient player credentials")
        OnlineConnection.clearCredentials(paths: paths)
        let cleared = INI(url: cfg.appendingPathComponent("race.ini"))
        try check(cleared["REMOTE", "PASSWORD"].isEmpty && cleared["REMOTE", "GUID"].isEmpty && cleared["REMOTE", "ACTIVE"] == "0" && cleared["RACE", "TRACK"] == configuration.track, "online cleanup removes secrets and preserves race configuration")
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
        let fixture = temp.appendingPathComponent("fixture-game")
        try fm.createDirectory(at: fixture.appendingPathComponent("content/cars/test_car/ui"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("content/cars/test_car/skins/default"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("content/tracks/test_track/ui/layout"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("content/tracks/test_track/layout/ai"), withIntermediateDirectories: true)
        for file in ["acs.exe", "content/cars/test_car/body.kn5", "content/tracks/test_track/models_layout.ini", "content/tracks/test_track/layout/ai/fast_lane.ai"] {
            try Data().write(to: fixture.appendingPathComponent(file))
        }
        try #"{"name":"Fixture Car","brand":"Fixture","class":"GT3","country":"Italy","tags":[" GT3 ","gt3","race"," "]}"#.write(to: fixture.appendingPathComponent("content/cars/test_car/ui/ui_car.json"), atomically: true, encoding: .utf8)
        try #"{"name":"Fixture Layout","length":"1000","pitboxes":"12","country":"Italy"}"#.write(to: fixture.appendingPathComponent("content/tracks/test_track/ui/layout/ui_track.json"), atomically: true, encoding: .utf8)
        let scanned = try ContentLibrary.scan(fixture)
        try check(scanned.cars.first?.name == "Fixture Car" && scanned.tracks.first?.layouts.first?.id == "layout" && scanned.tracks.first?.layouts.first?.hasAI == true, "fixture car, layout and AI scanning")
        try WorkflowChecks.run(root: temp, library: scanned, game: fixture)
        try CSPOnlineChecks.run(root: temp)
        try check(ContentRequirements.minimumCSP(in: "Minimum CSP Version: 0.2.7<br>Version: 3.2") == "0.2.7", "explicit RSS CSP requirement parsed")
        try check(ContentRequirements.minimumCSP(in: "Minimum CSP Version 0.2.7.") == "0.2.7", "RSS GT-MX CSP requirement parsed")
        try check(ContentRequirements.minimumCSP(in: "Optional CSP lighting support") == nil, "optional CSP visuals do not become a mandatory dependency")
        var dependent = scanned.cars[0]; dependent.requiredCSP = "0.2.7"
        var missingCSP = false
        do { try ContentRequirements.validate(dependent, game: fixture) } catch { missingCSP = error.localizedDescription.contains("0.2.7") }
        try check(missingCSP, "missing CSP rejected before changing Steam or live game configuration")
        try ContentRequirements.validate(scanned.cars[0], game: fixture)

        try check(scanned.cars.first?.badges == ["Fixture", "GT3", "Italy", "race"] && scanned.tracks.first?.countries == ["Italy"], "car badges deduplicate metadata and track countries come from layouts")
        let carUI = fixture.appendingPathComponent("content/cars/test_car/ui/ui_car.json")
        try "{\"description\":\"legacy\nnewline\",\"tags\":[\"GT3\",\"race\"]}".write(to: carUI, atomically: true, encoding: .utf8)
        try check(ContentLibrary.tags(carUI) == ["GT3", "race"], "legacy multiline JSON retains car tags")
        try check(ServerContent(track: "test_track-layout", cars: ["test_car"]).isInstalled(in: scanned), "installed content matches exact track layout and all cars")
        try check(!ServerContent(track: "test_track-other", cars: ["test_car"]).isInstalled(in: scanned) &&
                  !ServerContent(track: "test_track-layout", cars: ["test_car", "missing"]).isInstalled(in: scanned) &&
                  !ServerContent(track: "test_track-layout", cars: []).isInstalled(in: scanned), "missing layout, missing car and empty roster do not pass installed filter")
        let browser = OnlineBrowser(store: temp.appendingPathComponent("FilterChecks"))
        let directoryJSON = #"[{"id":"test:8081","host":"test","httpPort":8081,"name":"Fixture","track":"Display Track","carNames":["Display Car"],"content":{"track":"test_track-layout","cars":["test_car"]},"clients":0,"capacity":10,"password":false,"csp":false,"online":true},{"id":"unknown:8081","host":"unknown","httpPort":8081,"name":"Unknown","track":"Display Track","carNames":["Display Car"],"clients":0,"capacity":10,"password":false,"csp":false,"online":true}]"#
        browser.servers = try JSONDecoder().decode([OnlineServer].self, from: Data(directoryJSON.utf8))
        browser.onlyInstalled = true; browser.trackFilter = "Fixture Layout"; browser.carFilter = "Fixture Car"
        try check(browser.filteredServers(in: scanned).map(\.id) == ["test:8081"], "combined filters use local names and exclude unverified content")
        try check(browser.filteredServers(in: scanned, servers: []).isEmpty, "LAN source filtering does not fall back to internet rows")
        browser.carFilter = "other"
        try check(browser.filteredServers(in: scanned).isEmpty, "car filter excludes nonmatching servers")
        browser.onlyInstalled = false; browser.trackFilter = "display"; browser.carFilter = "display"
        try check(browser.filteredServers(in: scanned).count == 2, "directory names filter without live content checks")
        if includeInstalledGame {
            let actual = try ContentLibrary.scan(PaddockPaths.current.game)
            try check(actual.cars.contains { $0.id == "lotus_elise_sc" } && actual.tracks.contains { $0.id == "magione" }, "installed car/track metadata scanning")
            print("Library: \(actual.cars.count) cars, \(actual.tracks.count) tracks, \(actual.weather.count) weather presets")
        } else { print("SKIP installed game scan (--without-game)") }
        print("All Paddock checks passed; no live game config or hardware changed.")
    }
}
