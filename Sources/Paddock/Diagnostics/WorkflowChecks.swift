import Foundation
import Darwin

enum WorkflowChecks {
    static func run(root: URL, library: ContentLibrary, game: URL) throws {
        let fm = FileManager.default
        func check(_ value: @autoclosure () -> Bool, _ label: String) throws {
            guard value() else { throw PaddockError(label) }; print("PASS \(label)")
        }
        func rejects(_ label: String, _ action: () throws -> Void) throws {
            var failed = false
            do { try action() } catch { failed = true }
            try check(failed, label)
        }
        let reserved = socket(AF_INET, SOCK_STREAM, 0)
        guard reserved >= 0 else { throw PaddockError("Cannot create local port fixture") }
        defer { close(reserved) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(reserved, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(reserved, 1) == 0 else { throw PaddockError("Cannot bind local port fixture") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(reserved, $0, &length) }
        }
        let occupied = Int(UInt16(bigEndian: address.sin_port))
        try check(!ServerPorts.available(occupied, udp: false), "server detects an occupied local port")
        let suggested = ServerPorts.suggested(occupied, udp: false)
        try check(suggested != occupied && ServerPorts.available(suggested, udp: false), "server suggests another port without affecting its owner")
        var draft = HostedServerDraft(car: "test_car", track: "test_track", layout: "layout", slots: 4)
        let (cfg, entries) = try draft.configuration(library: library, adminPassword: "admin-test")
        try check(cfg["SERVER", "CONFIG_TRACK"] == "layout" && cfg["SERVER", "REGISTER_TO_LOBBY"] == "0", "hosted server retains layout and defaults to private LAN")
        try check(cfg["SERVER", "MAX_CLIENTS"] == "4" && entries.sections.count == 4 && entries["CAR_3", "SKIN"] == "default", "hosted grid matches capacity and installed skins")
        draft.password = "bad\n[SERVER]"
        try rejects("host rejects INI injection") { _ = try draft.configuration(library: library, adminPassword: "x") }
        draft.password = ""; draft.slots = 13
        try rejects("host rejects capacity exceeding track pits") { _ = try draft.configuration(library: library, adminPassword: "x") }
        draft.slots = 4; draft.httpPort = draft.racePort
        try rejects("host rejects conflicting ports") { _ = try draft.configuration(library: library, adminPassword: "x") }
        draft.httpPort = 8081
        var noPits = library
        let existing = library.tracks[0]
        noPits.tracks = [TrackAsset(id: existing.id, name: existing.name, directory: existing.directory,
            layouts: [.init(id: "layout", name: "No pits", length: "", preview: nil, outline: nil, pits: 0, hasAI: false)])]
        try rejects("host rejects zero pit metadata without trapping") { _ = try draft.configuration(library: noPits, adminPassword: "x") }
        draft.car = "missing"
        try rejects("host rejects missing content") { _ = try draft.configuration(library: library, adminPassword: "x") }
        draft.car = "test_car"
        let paths = PaddockPaths(project: root, bottle: "unused", storeOverride: root.appendingPathComponent("host-store"))
        let source = root.appendingPathComponent("server-source/acServer.exe")
        try fm.createDirectory(at: source.deletingLastPathComponent().appendingPathComponent("cfg"), withIntermediateDirectories: true)
        try Data("fixture executable".utf8).write(to: source)
        let original = source.deletingLastPathComponent().appendingPathComponent("cfg/server_cfg.ini")
        try Data("keep original".utf8).write(to: original)
        let physics = game.appendingPathComponent("content/cars/test_car/data.acd")
        try Data("fixture physics".utf8).write(to: physics)
        let surfaces = game.appendingPathComponent("content/tracks/test_track/layout/data/surfaces.ini")
        try fm.createDirectory(at: surfaces.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture surfaces".utf8).write(to: surfaces)
        let system = game.appendingPathComponent("system/data/surfaces.ini")
        try fm.createDirectory(at: system.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture shared surfaces".utf8).write(to: system)
        let folder = try ServerHost.prepare(draft, source: source, paths: paths, library: library)
        let sourceUnchanged = try String(contentsOf: original) == "keep original"
        let physicsCopied = try Data(contentsOf: folder.appendingPathComponent("content/cars/test_car/data.acd")) == Data(contentsOf: physics)
        try check(sourceUnchanged && physicsCopied, "server bundle copies checksums without overwriting source configs")
        let systemCopied = try Data(contentsOf: folder.appendingPathComponent("system/data/surfaces.ini")) == Data(contentsOf: system)
        try check(systemCopied, "server bundle retains global surface checksum validation")
        let permissions = try fm.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue == 0o700, "server bundle protects passwords with private folder permissions")
        let before = try fm.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path)
        try fm.removeItem(at: surfaces)
        try rejects("server preparation rolls back on missing track data") { _ = try ServerHost.prepare(draft, source: source, paths: paths, library: library) }
        let after = try fm.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path)
        try check(before == after, "failed server bundle leaves no partial installation")
        let store = FavoriteServersStore(directory: root.appendingPathComponent("favorites"))
        let favorite = FavoriteServer(host: "LOCALHOST", httpPort: 8081, name: "Friends")
        try store.save([favorite])
        let loaded = try store.load()
        try check(loaded == [favorite] && favorite.id == "localhost:8081", "favorite addresses persist and normalize host identity")
        let browser = OnlineBrowser(store: store.directory)
        browser.toggleFavorite(host: "localhost", port: 8081, name: "Friends")
        try check(browser.favorites.isEmpty, "favorite removal deduplicates normalized addresses")
        try Data("broken fixture".utf8).write(to: store.file)
        let blocked = OnlineBrowser(store: store.directory)
        blocked.toggleFavorite(host: "localhost", port: 8081, name: "Do not save")
        let preserved = try String(contentsOf: store.file)
        try check(blocked.favoritesError != nil && preserved == "broken fixture", "corrupt favorites remain untouched on mutation")
        let nav = Set([PaddockTab.drive] + PaddockNavigation.groups.flatMap(\.items))
        try check(nav == Set(PaddockTab.allCases), "every screen remains reachable through grouped navigation")
    }
}
