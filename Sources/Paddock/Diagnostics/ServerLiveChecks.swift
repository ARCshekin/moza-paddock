import Foundation

/// Opt-in integration check. Starts real Wine/server, never the game or wheel.
enum ServerLiveChecks {
    static func run() throws {
        var paths = PaddockPaths.current
        paths.runtime = .standalone
        let library = try ContentLibrary.scan(paths.game)
        let host = ServerHost()
        host.draft = HostedServerDraft(name: "Paddock integration check", car: "lotus_elise_sc", track: "magione",
                                      slots: 4, racePort: 19600, httpPort: 18081, minutes: 10)
        func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition(), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
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
        host.start(paths: paths, library: library)
        defer {
            host.stop()
            _ = wait(10, until: { !host.running && !host.preparing })
        }
        guard wait(30, until: { !host.preparing }), host.running else {
            throw PaddockError(host.error ?? host.status)
        }
        print("SERVER_FOLDER \(host.folder!.path)")
        var details: OnlineServerDetails?
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline, host.running {
            if let value = try? inspect("127.0.0.1:18081") { details = value; break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        guard let details, details.pickup, details.racePort == 19600, details.track == "magione",
              details.capacity == 4, details.free["lotus_elise_sc"] == 4 else {
            throw PaddockError("Real server did not expose expected pickup slots: \(host.status)")
        }
        guard wait(15, until: { host.status.hasPrefix("Сервер готов") }) else {
            throw PaddockError("UI readiness did not reflect real server")
        }
        let log = try String(contentsOf: host.folder!.appendingPathComponent("server.log"))
        guard log.contains("system/data/surfaces.ini="), !log.contains("client check will be disabled") else {
            throw PaddockError("Server checksum validation is incomplete")
        }
        print("PASS real Kunos server INFO + JSON slots through Paddock OnlineBrowser")
        print("PASS UI readiness and global surface checksum validation")
        if let flag = CommandLine.arguments.firstIndex(of: "--server-check-address"), CommandLine.arguments.count > flag + 1 {
            let address = CommandLine.arguments[flag + 1]
            let lan = try inspect(address + ":18081")
            guard lan.name == details.name, lan.capacity == 4 else { throw PaddockError("LAN inspection differs from loopback") }
            print("PASS real server reachable on host LAN address")
        }
        // Exercise the exact stop action used by the UI, then restart in the same prefix.
        host.stop()
        guard wait(10, until: { !host.running }) else { throw PaddockError("Server stop did not finish") }
        print("PASS UI server stop completed")
        host.start(paths: paths, library: library)
        guard wait(30, until: { !host.preparing }), host.running else { throw PaddockError(host.error ?? host.status) }
        let secondDeadline = Date().addingTimeInterval(30)
        var restarted = false
        while Date() < secondDeadline, host.running {
            if let value = try? inspect("127.0.0.1:18081"), value.capacity == 4 { restarted = true; break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        guard restarted else { throw PaddockError("Server restart failed") }
        print("PASS UI server restart with ports reused")
    }
}
