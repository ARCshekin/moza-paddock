import Foundation

enum ServerConfigurationChecks {
    static func run(root: URL, library: ContentLibrary) throws {
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw PaddockError(label) }; print("PASS \(label)")
        }
        func rejects(_ label: String, _ action: () throws -> Void) throws {
            var rejected = false
            do { try action() } catch { rejected = true }
            try check(rejected, label)
        }
        var content = library
        let second = CarAsset(id: "second_car", name: "Second Car", brand: "Fixture", power: "", weight: "",
                              directory: root.appendingPathComponent("second-car"),
                              skins: [.init(id: "default", name: "Default", preview: nil), .init(id: "alternate", name: "Alternate", preview: nil)])
        content.cars.append(second)
        var draft = HostedServerDraft(cars: [.init(model: "test_car", slots: 2), .init(model: second.id, slots: 2, skins: [0: "alternate"])],
                                      track: "test_track", layout: "layout", mode: .weekend)
        let (config, entries) = try draft.configuration(library: content, adminPassword: "fixture")
        let encoded = INI(config.text, inlineComments: false)
        try check(encoded["SERVER", "CARS"] == "test_car;second_car" && encoded["SERVER", "MAX_CLIENTS"] == "4", "all models survive server INI semicolon serialization")
        try check(entries["CAR_0", "MODEL"] == "test_car" && entries["CAR_2", "MODEL"] == "second_car" && entries["CAR_2", "SKIN"] == "alternate", "mixed grid assigns each model and explicit skin to its slots")
        let invite = ServerConnectionDetails(configuration: draft, addresses: []).invitation(ip: "127.0.0.1")
        try check(invite.contains("test_car × 2") && invite.contains("second_car × 2") && invite.contains("Уикенд"), "invitation lists every model, capacity and session mode")
        for mode in HostedServerMode.allCases {
            draft.mode = mode
            let (ini, _) = try draft.configuration(library: content, adminPassword: "fixture")
            let active = Set(ini.sections.keys).intersection(["PRACTICE", "QUALIFY", "RACE"])
            try check(active == Set(mode.sections), "\(mode.rawValue) emits only its configured sessions")
            if mode.sections.contains("RACE") { try check(ini["RACE", "LAPS"] == "5" && ini["RACE", "WAIT_TIME"] == "60", "race preserves lap count and start wait") }
        }
        let valid = draft
        draft.cars = []
        try rejects("server rejects an empty grid") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        draft = valid; draft.cars.append(draft.cars[0])
        try rejects("server rejects duplicate model rows") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        draft = valid; draft.cars[1].slots = 12
        try rejects("server limits combined model slots to track pits") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        draft = valid; draft.cars[1].skins[0] = "missing"
        try rejects("server rejects a skin missing from its model") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        draft = valid; draft.cars[1].model = "second;injected"
        try rejects("model IDs cannot inject extra server models") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        draft = valid; draft.mode = .race; draft.laps = 0
        try rejects("race requires a positive lap count") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        draft = valid; draft.mode = .qualifying; draft.qualifyingMinutes = 0
        try rejects("qualifying requires a positive duration") { _ = try draft.configuration(library: content, adminPassword: "fixture") }
        // The second car exists in the library but lacks physics. Preparation
        // must remove the already copied first car and the rest of the bundle.
        let paths = PaddockPaths(project: root, bottle: "fixture", storeOverride: root.appendingPathComponent("mixed-host"))
        let executable = root.appendingPathComponent("server-source/acServer.exe")
        try rejects("failure preparing the second car rolls back the whole mixed grid") {
            _ = try ServerHost.prepare(valid, source: executable, paths: paths, library: content)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: paths.store.appendingPathComponent("Servers").path)) ?? []
        try check(leftovers.isEmpty, "failed mixed grid leaves no partially prepared server")
    }
}
