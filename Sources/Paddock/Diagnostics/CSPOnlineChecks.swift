import Foundation

/// Offline preflight and INI checks; never starts Wine, Steam or a game.
enum CSPOnlineChecks {
    static func run(root: URL) throws {
        let fm = FileManager.default
        var paths = PaddockPaths(project: root, bottle: "fixture", documentsOverride: root.appendingPathComponent("CSPDocuments"), storeOverride: root.appendingPathComponent("CSPStore"))
        paths.runtime = .standalone
        let gameConfig = paths.game.appendingPathComponent("extension/config")
        let userConfig = paths.documents.appendingPathComponent("cfg/extension")
        try fm.createDirectory(at: gameConfig, withIntermediateDirectories: true)
        try fm.createDirectory(at: userConfig, withIntermediateDirectories: true)
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw PaddockError(label) }
            print("PASS \(label)")
        }
        var server = OnlineServerDetails(host: "127.0.0.1", httpPort: 8081, racePort: 9600, name: "CSP fixture", track: "spa", cars: ["test_car"], free: ["test_car": 1], clients: 0, capacity: 1, password: false, pickup: true, csp: true, latency: 1, requiredCSPBuild: 3000)
        func connect(_ server: OnlineServerDetails) -> OnlineConnection {
            OnlineConnection(server: server, car: "test_car", player: "Driver", password: "")
        }
        try check(server.cspError(paths: paths)?.contains("не установлен") == true, "CSP server reports missing patch instead of unsupported app version")
        try Data([0x4d, 0x5a]).write(to: paths.game.appendingPathComponent("dwrite.dll"))
        try "[BASIC]\nENABLED=1 ; active\n".write(to: gameConfig.appendingPathComponent("general.ini"), atomically: true, encoding: .utf8)
        let manifest = gameConfig.appendingPathComponent("data_manifest.ini")
        try "[VERSION]\nSHADERS_PATCH=0.2.11\nSHADERS_PATCH_BUILD=3465\n".write(to: manifest, atomically: true, encoding: .utf8)
        try check(server.cspError(paths: paths) == nil, "installed active CSP meeting server build enables connection")
        try connect(server).validate(paths: paths)
        try connect(server).write(paths: paths, guid: "76561198000000000")
        let race = INI(url: paths.documents.appendingPathComponent("cfg/race.ini"))
        try check(race["REMOTE", "ACTIVE"] == "1" && race["REMOTE", "SERVER_PORT"] == "9600" && race["HEADER", "__CM_FEATURE_SET"] == "2", "CSP online writes standard REMOTE configuration and launcher feature set")
        server.requiredCSPBuild = 3465
        try check(server.cspError(paths: paths) == nil, "equal CSP build satisfies server requirement")
        server.requiredCSPBuild = 3466
        try check(server.cspError(paths: paths)?.contains("3466") == true, "newer server build reports actionable CSP update requirement")
        var rejected = false
        do { try connect(server).write(paths: paths, guid: "76561198000000000") } catch { rejected = true }
        try check(rejected, "CSP mismatch is revalidated before writing connection credentials")
        server.requiredCSPBuild = 3000
        let override = userConfig.appendingPathComponent("general.ini")
        try "[BASIC]\nENABLED=0\n".write(to: override, atomically: true, encoding: .utf8)
        try check(server.cspError(paths: paths)?.contains("отключён") == true, "user CSP disable overrides enabled game defaults")
        try "[BASIC]\nENABLED=0\n".write(to: gameConfig.appendingPathComponent("general.ini"), atomically: true, encoding: .utf8)
        try "[BASIC]\nENABLED=1\n".write(to: override, atomically: true, encoding: .utf8)
        try check(server.cspError(paths: paths) == nil, "user CSP enable overrides disabled game defaults")
        try "[VERSION]\nSHADERS_PATCH_BUILD=invalid\n".write(to: manifest, atomically: true, encoding: .utf8)
        try check(server.cspError(paths: paths)?.contains("определить сборку") == true, "unknown CSP build does not silently pass validation")
        server = OnlineServerDetails(host: server.host, httpPort: server.httpPort, racePort: server.racePort, name: server.name, track: server.track, cars: server.cars, free: server.free, clients: 0, capacity: 1, password: false, pickup: true, csp: false, latency: 1, requiredCSPBuild: 999999)
        try check(server.cspError(paths: paths)?.contains("отключить CSP") == true, "reserved no-CSP server version rejects active patch")
        try "[BASIC]\nENABLED=0\n".write(to: override, atomically: true, encoding: .utf8)
        try check(server.cspError(paths: paths) == nil, "no-CSP server permits a disabled patch")
        let ordinary = OnlineServerDetails(host: server.host, httpPort: server.httpPort, racePort: server.racePort, name: "Ordinary", track: server.track, cars: server.cars, free: server.free, clients: 0, capacity: 1, password: false, pickup: true, csp: false, latency: 1)
        try fm.removeItem(at: paths.game.appendingPathComponent("dwrite.dll"))
        try connect(ordinary).validate(paths: paths)
        try check(ordinary.cspError(paths: paths) == nil, "ordinary pickup server remains available without CSP")
    }
}
