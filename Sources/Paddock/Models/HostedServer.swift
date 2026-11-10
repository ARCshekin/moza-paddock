import Foundation

enum HostedServerMode: String, CaseIterable, Identifiable {
    case practice, qualifying, race, weekend
    var id: String { rawValue }
    var title: String {
        switch self {
        case .practice: return "Тренировка"
        case .qualifying: return "Квалификация"
        case .race: return "Гонка"
        case .weekend: return "Уикенд"
        }
    }
    var sections: [String] {
        switch self {
        case .practice: return ["PRACTICE"]
        case .qualifying: return ["QUALIFY"]
        case .race: return ["RACE"]
        case .weekend: return ["PRACTICE", "QUALIFY", "RACE"]
        }
    }
}

struct HostedServerCar: Equatable, Identifiable {
    var model: String
    var slots = 4
    var skins: [Int: String] = [:]
    var id: String { model }
}

struct HostedServerDraft: Equatable {
    var name = "Мой Paddock"
    var cars: [HostedServerCar] = []
    var track = ""
    var layout = ""
    var password = ""
    var publicLobby = false
    var racePort = 9600
    var httpPort = 8081
    var mode = HostedServerMode.practice
    var minutes = 30
    var qualifyingMinutes = 10
    var laps = 5
    var waitSeconds = 60
    var slots: Int { cars.reduce(0) { $0 + $1.slots } }
    var carSummary: String { cars.map { "\($0.model) × \($0.slots)" }.joined(separator: ", ") }

    func configuration(library: ContentLibrary, adminPassword: String) throws -> (INI, INI) {
        func safe(_ value: String) -> Bool {
            !value.contains { $0.isNewline || $0.isASCII && ($0.asciiValue! < 32) || ";[]=\\/".contains($0) }
        }
        let identifiers = cars.map(\.model) + [track, layout]
        guard identifiers.allSatisfy({ $0 != "." && $0 != ".." }),
              !name.trimmingCharacters(in: .whitespaces).isEmpty,
              ([name, password, adminPassword] + identifiers).allSatisfy(safe) else {
            throw PaddockError("Проверьте имя, пароль и идентификаторы: переносы строк и ; [ ] = \\ / недопустимы.")
        }
        guard !cars.isEmpty, cars.count <= 64, Set(cars.map(\.model)).count == cars.count,
              cars.allSatisfy({ (1...64).contains($0.slots) }) else {
            throw PaddockError("Добавьте разные модели автомобилей и укажите от 1 до 64 мест для каждой.")
        }
        guard let circuit = library.tracks.first(where: { $0.id == track }),
              let variant = circuit.layouts.first(where: { $0.id == layout }) else {
            throw PaddockError("Выберите установленную конфигурацию трассы.")
        }
        guard slots <= min(64, variant.pits) else {
            throw PaddockError("Всего \(slots) мест: доступно не больше \(max(0, min(64, variant.pits))) пит-боксов. Уменьшите число мест или выберите другую трассу.")
        }
        guard (!mode.sections.contains("PRACTICE") || (1...240).contains(minutes)),
              (!mode.sections.contains("QUALIFY") || (1...240).contains(qualifyingMinutes)),
              (!mode.sections.contains("RACE") || (1...200).contains(laps) && (10...300).contains(waitSeconds)) else {
            throw PaddockError("Сессии — от 1 до 240 минут, гонка — от 1 до 200 кругов, ожидание старта — от 10 до 300 секунд.")
        }
        guard (1024...65535).contains(racePort), (1024...65535).contains(httpPort), racePort != httpPort else {
            throw PaddockError("Порты должны различаться и находиться в диапазоне 1024–65535.")
        }
        var config = INI()
        config.sections["SERVER"] = ["NAME": name, "PASSWORD": password, "ADMIN_PASSWORD": adminPassword,
            "CARS": cars.map(\.model).joined(separator: ";"), "TRACK": track, "CONFIG_TRACK": layout, "MAX_CLIENTS": "\(slots)",
            "UDP_PORT": "\(racePort)", "TCP_PORT": "\(racePort)", "HTTP_PORT": "\(httpPort)",
            "REGISTER_TO_LOBBY": publicLobby ? "1" : "0", "PICKUP_MODE_ENABLED": "1", "LOCKED_ENTRY_LIST": "0",
            "LOOP_MODE": "1", "CLIENT_SEND_INTERVAL_HZ": "18", "SLEEP_TIME": "1", "SUN_ANGLE": "16",
            "FUEL_RATE": "100", "DAMAGE_MULTIPLIER": "0", "TYRE_WEAR_RATE": "100", "ALLOWED_TYRES_OUT": "3",
            "ABS_ALLOWED": "1", "TC_ALLOWED": "1", "STABILITY_ALLOWED": "0", "AUTOCLUTCH_ALLOWED": "1",
            "TYRE_BLANKETS_ALLOWED": "1", "FORCE_VIRTUAL_MIRROR": "0", "RACE_OVER_TIME": "180", "RESULT_SCREEN_TIME": "30"]
        if mode.sections.contains("PRACTICE") {
            config.sections["PRACTICE"] = ["NAME": "Practice", "TIME": "\(minutes)", "IS_OPEN": "1"]
        }
        if mode.sections.contains("QUALIFY") {
            config.sections["QUALIFY"] = ["NAME": "Qualify", "TIME": "\(qualifyingMinutes)", "IS_OPEN": "1"]
        }
        if mode.sections.contains("RACE") {
            config.sections["RACE"] = ["NAME": "Race", "LAPS": "\(laps)", "TIME": "0", "WAIT_TIME": "\(waitSeconds)", "IS_OPEN": "1"]
        }
        config.sections["DYNAMIC_TRACK"] = ["SESSION_START": "100", "RANDOMNESS": "0", "SESSION_TRANSFER": "100", "LAP_GAIN": "10"]
        config.sections["WEATHER_0"] = ["GRAPHICS": "3_clear", "BASE_TEMPERATURE_AMBIENT": "26",
            "BASE_TEMPERATURE_ROAD": "8", "VARIATION_AMBIENT": "0", "VARIATION_ROAD": "0",
            "WIND_BASE_SPEED_MIN": "0", "WIND_BASE_SPEED_MAX": "0", "WIND_BASE_DIRECTION": "0", "WIND_VARIATION_DIRECTION": "0"]
        var entries = INI()
        var index = 0
        for selection in cars {
            guard let asset = library.cars.first(where: { $0.id == selection.model }), !asset.skins.isEmpty else {
                throw PaddockError("Не установлена машина или её скины: \(selection.model).")
            }
            guard selection.skins.allSatisfy({ slot, skin in (0..<selection.slots).contains(slot) && asset.skins.contains(where: { $0.id == skin }) }) else {
                throw PaddockError("Проверьте выбранные скины и места для \(asset.name).")
            }
            for slot in 0..<selection.slots {
                let skin = selection.skins[slot] ?? asset.skins[slot % asset.skins.count].id
                guard safe(skin) else { throw PaddockError("Некорректный идентификатор скина.") }
                entries.sections["CAR_\(index)"] = ["MODEL": selection.model, "SKIN": skin, "SPECTATOR_MODE": "0", "DRIVERNAME": "", "TEAM": "", "GUID": "", "BALLAST": "0", "RESTRICTOR": "0"]
                index += 1
            }
        }
        return (config, entries)
    }
}
