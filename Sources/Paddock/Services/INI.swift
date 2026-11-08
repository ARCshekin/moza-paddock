import Foundation

struct INI {
    var sections: [String: [String: String]] = [:]
    init(_ text: String = "") {
        var section = ""
        for line in text.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix(";") || value.hasPrefix("#") || value.isEmpty { continue }
            if value.hasPrefix("["), let end = value.firstIndex(of: "]") {
                section = String(value[value.index(after: value.startIndex)..<end]); continue
            }
            guard let equal = value.firstIndex(of: "=") else { continue }
            let key = value[..<equal].trimmingCharacters(in: .whitespaces)
            let raw = String(value[value.index(after: equal)...])
            sections[section, default: [:]][key] = raw.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
        }
    }
    init(url: URL) { self.init((try? String(contentsOf: url)) ?? "") }
    subscript(_ section: String, _ key: String) -> String {
        get { sections[section]?[key] ?? "" }
        set { sections[section, default: [:]][key] = newValue }
    }
    var text: String {
        sections.keys.sorted().map { section in
            "[\(section)]\n" + (sections[section] ?? [:]).keys.sorted().map { "\($0)=\(sections[section]![$0]!)" }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }
    func save(_ url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
}

enum ConfigurationWriter {
    static func write(_ c: DriveConfiguration, paths: PaddockPaths) throws {
        let fm = FileManager.default
        let cfg = paths.documents.appendingPathComponent("cfg")
        try fm.createDirectory(at: cfg, withIntermediateDirectories: true)
        let backup = paths.store.appendingPathComponent("Backups/\(UUID().uuidString)")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in ["race.ini", "controls.ini", "video.ini", "assists.ini"] {
            let file = cfg.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) { try fm.copyItem(at: file, to: backup.appendingPathComponent(name)) }
        }
        var controls = INI(url: cfg.appendingPathComponent("controls.ini"))
        controls["HEADER", "INPUT_METHOD"] = "WHEEL"
        controls["CONTROLLERS", "CON0"] = "MOZA R5 Bridge"
        controls["CONTROLLERS", "PGUID0"] = "0004346E-0000-0000-0000-504944564944"
        for (key, value) in ["JOY": "0", "AXLE": "0", "LOCK": "\(c.angle)", "FF_GAIN": "1", "STEER_GAMMA": "1", "SCALE": "1", "STEER_FILTER": "0", "SPEED_SENSITIVITY": "0"] { controls["STEER", key] = value }
        for (section, axle) in [("THROTTLE", 1), ("BRAKES", 5)] {
            controls[section, "JOY"] = "0"; controls[section, "AXLE"] = "\(axle)"
            controls[section, "MIN"] = "-1"; controls[section, "MAX"] = "1"
        }
        controls["BRAKES", "GAMMA"] = "1"
        controls["FF_TWEAKS", "MIN_FF"] = "0"
        for action in ButtonAction.all {
            let button = c.bindings[action.id]
            controls[action.id, "JOY"] = button == nil ? "-1" : "0"
            controls[action.id, "BUTTON"] = button.map { "\($0 - 1)" } ?? "-1"
        }
        try controls.save(cfg.appendingPathComponent("controls.ini"))
        var race = INI(url: cfg.appendingPathComponent("race.ini"))
        for key in Array(race.sections.keys) where key.hasPrefix("SESSION_") || key.hasPrefix("CAR_") { race.sections.removeValue(forKey: key) }
        let count = c.mode == .race ? c.opponents + 1 : 1
        for (key, value) in ["TRACK": c.track, "CONFIG_TRACK": c.layout, "MODEL": c.car, "MODEL_CONFIG": "", "SKIN": c.skin, "CARS": "\(count)", "AI_LEVEL": "\(c.ai)", "RACE_LAPS": "\(c.laps)", "PENALTIES": c.penalties ? "1" : "0", "DRIFT_MODE": c.mode == .drift ? "1" : "0"] { race["RACE", key] = value }
        for i in 0..<count {
            race["CAR_\(i)", "MODEL"] = i == 0 ? "-" : c.car
            race["CAR_\(i)", "MODEL_CONFIG"] = ""
            race["CAR_\(i)", "SKIN"] = c.skin
            race["CAR_\(i)", "DRIVER_NAME"] = i == 0 ? "Driver" : "AI \(i)"
            race["CAR_\(i)", "AI_LEVEL"] = "\(c.ai)"
        }
        // AC IDs include the track (or generic) folder, as in Content Manager.
        race["CAR_0", "SETUP"] = c.setup.replacingOccurrences(of: "/", with: "\\")
        for (key, value) in ["NAME": c.mode.title, "TYPE": "\(c.mode.code)", "SPAWN_SET": c.mode.spawn, "DURATION_MINUTES": "\(c.minutes)", "LAPS": "\(c.laps)", "STARTING_POSITION": "\(count)"] { race["SESSION_0", key] = value }
        race["REMOTE", "ACTIVE"] = "0"; race["REPLAY", "ACTIVE"] = "0"
        race["WEATHER", "NAME"] = c.weather
        race["TEMPERATURE", "AMBIENT"] = "\(c.temperature)"; race["TEMPERATURE", "ROAD"] = "\(c.temperature + 6)"
        race["LIGHTING", "SUN_ANGLE"] = "\(Int((c.hour - 13) * 15))"
        race["GHOST_CAR", "RECORDING"] = "1"; race["GHOST_CAR", "PLAYING"] = c.mode == .hotlap ? "1" : "0"
        race["LAP_INVALIDATOR", "ALLOWED_TYRES_OUT"] = "2"
        var assists = INI(url: cfg.appendingPathComponent("assists.ini"))
        for (key, value) in ["AUTO_CLUTCH": c.autoClutch ? "1" : "0", "AUTO_SHIFTER": c.autoShift ? "1" : "0", "AUTO_BLIP": "1", "ABS": "\(c.abs)", "TRACTION_CONTROL": "\(c.traction)", "STABILITY_CONTROL": "0", "DAMAGE": "0", "IDEAL_LINE": "0"] {
            race["ASSISTS", key] = value; assists["ASSISTS", key] = value
        }
        try race.save(cfg.appendingPathComponent("race.ini"))
        try assists.save(cfg.appendingPathComponent("assists.ini"))
        var video = INI(url: cfg.appendingPathComponent("video.ini"))
        video["VIDEO", "FULLSCREEN"] = "0"; video["VIDEO", "WIDTH"] = "\(c.width)"; video["VIDEO", "HEIGHT"] = "\(c.height)"
        try video.save(cfg.appendingPathComponent("video.ini"))
    }
}
