import Foundation

/// Opt-in checks use a fresh server prefix. Installed game files are read only.
enum ServerLiveChecks {
    static func run() throws {
        let fm = FileManager.default
        var source = PaddockPaths.current; source.runtime = .standalone
        let root = source.store.appendingPathComponent("ServerChecks/\(UUID().uuidString)")
        let paths = PaddockPaths(project: source.project, bottle: source.bottle, runtime: .standalone, storeOverride: root)
        try fm.createDirectory(at: paths.game.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: paths.game, withDestinationURL: source.game)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Runtimes"), withDestinationURL: source.store.appendingPathComponent("Runtimes"))
        let library = try ContentLibrary.scan(paths.game)
        let host = ServerHost()
        let multi = CommandLine.arguments.contains("--server-multi-check")
        let cars: [HostedServerCar] = multi ? [.init(model: "lotus_elise_sc", slots: 2), .init(model: "bmw_m3_e30", slots: 2)] : [.init(model: "lotus_elise_sc", slots: 4)]
        let racePort = ServerPorts.suggested(19600, udp: true), httpPort = ServerPorts.suggested(18081, udp: false)
        let modes = multi ? HostedServerMode.allCases : [.practice]
        print("ISOLATED_SERVER_ROOT \(root.path)")
        func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return condition()
        }
        func inspect(_ address: String) throws -> OnlineServerDetails {
            var result: Result<OnlineServerDetails, Error>?
            DispatchQueue.global(qos: .userInitiated).async {
                let value: Result<OnlineServerDetails, Error> = Result { try OnlineBrowser.run(paths, ["inspect", "--address", address]) }
                DispatchQueue.main.async { result = value }
            }
            guard wait(15, until: { result != nil }) else { throw PaddockError("Server inspection timed out") }
            return try result!.get()
        }
        func sessions() throws -> [Int] {
            var result: Result<[Int], Error>?
            URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(httpPort)/INFO")!) { data, _, error in
                let value = Result { () throws -> [Int] in
                    if let error { throw error }
                    guard let data, let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let types = info["sessiontypes"] as? [Int] else { throw PaddockError("INFO has no sessiontypes") }
                    return types
                }
                DispatchQueue.main.async { result = value }
            }.resume()
            guard wait(15, until: { result != nil }) else { throw PaddockError("Session inspection timed out") }
            return try result!.get()
        }
        defer {
            host.stop(); _ = wait(10, until: { !host.running && !host.preparing })
            // Only this diagnostic's new server prefix; never the game/Steam prefix.
            let runtime = source.store.appendingPathComponent("Runtimes")
            if let version = try? fm.contentsOfDirectory(at: runtime, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent == "wine-11.21" }) {
                let child = Process(); child.executableURL = version.appendingPathComponent("Wine Staging.app/Contents/Resources/wine/bin/wineserver")
                child.arguments = ["-k"]
                var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("WINE") && !$0.key.hasPrefix("CX_") && !$0.key.hasPrefix("DYLD_") }
                env["WINEPREFIX"] = root.appendingPathComponent("Prefixes/server").path
                child.environment = env; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
                if (try? child.run()) != nil { child.waitUntilExit() }
            }
        }
        for mode in modes {
            host.draft = HostedServerDraft(name: "Paddock check \(mode.rawValue)", cars: cars, track: "magione",
                                          racePort: racePort, httpPort: httpPort, mode: mode, minutes: 10)
            host.start(paths: paths, library: library)
            guard wait(30, until: { !host.preparing }), host.running else { throw PaddockError(host.error ?? host.status) }
            print("SERVER_FOLDER \(host.folder!.path)")
            var details: OnlineServerDetails?
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline, host.running {
                if let value = try? inspect("127.0.0.1:\(httpPort)"), value.name == host.draft.name { details = value; break }
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            }
            guard let details, details.pickup, details.racePort == racePort, details.track == "magione", details.capacity == 4,
                  Set(details.cars) == Set(cars.map(\.model)), cars.allSatisfy({ details.free[$0.model] == $0.slots }) else {
                throw PaddockError("Real server did not expose expected mixed pickup grid: \(host.status)")
            }
            guard wait(15, until: { host.status.hasPrefix("Сервер готов") }) else { throw PaddockError("UI readiness did not reflect real server") }
            let expected = mode.sections.map { ["PRACTICE": 1, "QUALIFY": 2, "RACE": 3][$0]! }
            guard try sessions() == expected else { throw PaddockError("Real server session types differ for \(mode.rawValue)") }
            let log = try String(contentsOf: host.folder!.appendingPathComponent("server.log"))
            guard log.contains("system/data/surfaces.ini="), !log.contains("client check will be disabled") else { throw PaddockError("Server checksum validation is incomplete") }
            guard let connection = host.connectionDetails, connection.localAddress == "127.0.0.1:\(httpPort)", connection.configuration.cars == cars else {
                throw PaddockError("Connection card does not match real server grid")
            }
            if let flag = CommandLine.arguments.firstIndex(of: "--server-check-address"), CommandLine.arguments.count > flag + 1 {
                let lan = try inspect(CommandLine.arguments[flag + 1] + ":\(httpPort)")
                guard lan.name == details.name else { throw PaddockError("LAN inspection differs from loopback") }
            }
            if mode == .practice {
                let lan: OnlineDirectory = try OnlineBrowser.run(paths, ["lan", "--ports", String(racePort), "--target", "127.0.0.1"])
                guard lan.items.contains(where: { $0.name == details.name && $0.httpPort == httpPort }) else {
                    throw PaddockError("LAN discovery did not find the isolated real server")
                }
                print("PASS real Kunos server discovered through LAN UDP query")
            }
            print("PASS real \(mode.rawValue): INFO sessions, JSON models/free slots, UI readiness, checksums and invitation snapshot")
            host.stop()
            guard wait(10, until: { !host.running }) else { throw PaddockError("Server stop did not finish") }
        }
        print("PASS isolated server lifecycle and reused ports; game prefix and hardware untouched")
    }
}
