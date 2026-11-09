import Foundation

struct HostedServerDraft: Equatable {
    var name = "Мой Paddock"
    var car = ""
    var track = ""
    var layout = ""
    var slots = 4
    var password = ""
    var publicLobby = false
    var racePort = 9600
    var httpPort = 8081
    var minutes = 30

    func configuration(library: ContentLibrary, adminPassword: String) throws -> (INI, INI) {
        func safe(_ value: String) -> Bool {
            !value.contains { $0.isNewline || $0.isASCII && ($0.asciiValue! < 32) || ";[]=\\/".contains($0) }
        }
        guard [car, track, layout].allSatisfy({ $0 != "." && $0 != ".." }),
              !name.trimmingCharacters(in: .whitespaces).isEmpty,
              [name, password, adminPassword, car, track, layout].allSatisfy(safe) else {
            throw PaddockError("Проверьте имя и пароль: переносы строк, управляющие символы и ; [ ] = \\ / недопустимы.")
        }
        guard let asset = library.cars.first(where: { $0.id == car }), !asset.skins.isEmpty,
              let circuit = library.tracks.first(where: { $0.id == track }),
              let variant = circuit.layouts.first(where: { $0.id == layout }) else {
            throw PaddockError("Выберите установленную машину со скином и конфигурацию трассы.")
        }
        guard (1...64).contains(slots), slots <= variant.pits, (1...240).contains(minutes) else {
            throw PaddockError("Число мест должно учитывать пит-боксы трассы; тренировка — от 1 до 240 минут.")
        }
        guard (1024...65535).contains(racePort), (1024...65535).contains(httpPort), racePort != httpPort else {
            throw PaddockError("Порты должны различаться и находиться в диапазоне 1024–65535.")
        }
        var config = INI()
        config.sections["SERVER"] = ["NAME": name, "PASSWORD": password, "ADMIN_PASSWORD": adminPassword,
            "CARS": car, "TRACK": track, "CONFIG_TRACK": layout, "MAX_CLIENTS": "\(slots)",
            "UDP_PORT": "\(racePort)", "TCP_PORT": "\(racePort)", "HTTP_PORT": "\(httpPort)",
            "REGISTER_TO_LOBBY": publicLobby ? "1" : "0", "PICKUP_MODE_ENABLED": "1", "LOCKED_ENTRY_LIST": "0",
            "LOOP_MODE": "1", "CLIENT_SEND_INTERVAL_HZ": "18", "SLEEP_TIME": "1", "SUN_ANGLE": "16",
            "FUEL_RATE": "100", "DAMAGE_MULTIPLIER": "0", "TYRE_WEAR_RATE": "100", "ALLOWED_TYRES_OUT": "3",
            "ABS_ALLOWED": "1", "TC_ALLOWED": "1", "STABILITY_ALLOWED": "0", "AUTOCLUTCH_ALLOWED": "1",
            "TYRE_BLANKETS_ALLOWED": "1", "FORCE_VIRTUAL_MIRROR": "0", "RACE_OVER_TIME": "180", "RESULT_SCREEN_TIME": "30"]
        config.sections["PRACTICE"] = ["NAME": "Practice", "TIME": "\(minutes)", "IS_OPEN": "1"]
        config.sections["DYNAMIC_TRACK"] = ["SESSION_START": "100", "RANDOMNESS": "0", "SESSION_TRANSFER": "100", "LAP_GAIN": "10"]
        config.sections["WEATHER_0"] = ["GRAPHICS": "3_clear", "BASE_TEMPERATURE_AMBIENT": "26",
            "BASE_TEMPERATURE_ROAD": "8", "VARIATION_AMBIENT": "0", "VARIATION_ROAD": "0",
            "WIND_BASE_SPEED_MIN": "0", "WIND_BASE_SPEED_MAX": "0", "WIND_BASE_DIRECTION": "0", "WIND_VARIATION_DIRECTION": "0"]
        var entries = INI()
        for slot in 0..<slots {
            let skin = asset.skins[slot % asset.skins.count].id
            guard safe(skin) else { throw PaddockError("Некорректный идентификатор скина.") }
            entries.sections["CAR_\(slot)"] = ["MODEL": car, "SKIN": skin, "SPECTATOR_MODE": "0", "DRIVERNAME": "", "TEAM": "", "GUID": "", "BALLAST": "0", "RESTRICTOR": "0"]
        }
        return (config, entries)
    }
}
