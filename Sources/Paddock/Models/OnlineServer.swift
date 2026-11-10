import Foundation

struct OnlineServer: Decodable, Identifiable {
    let id: String
    let host: String
    let httpPort: Int
    let name: String
    let track: String
    let carNames: [String]
    let content: ServerContent?
    let clients: Int
    let capacity: Int
    let password: Bool
    let csp: Bool
    let online: Bool
}
/// Exact IDs from INFO, independent of the directory's display names.
struct ServerContent: Decodable {
    let track: String
    let cars: [String]
    func isInstalled(in library: ContentLibrary) -> Bool {
        !cars.isEmpty && cars.allSatisfy { id in library.cars.contains { $0.id == id } } && installedTrack(in: library) != nil
    }
    func installedTrack(in library: ContentLibrary) -> (TrackAsset, TrackLayout)? {
        for asset in library.tracks {
            for layout in asset.layouts where asset.id + (layout.id.isEmpty ? "" : "-" + layout.id) == track {
                return (asset, layout)
            }
        }
        return nil
    }
}
struct OnlineDirectory: Decodable {
    let items: [OnlineServer]
    let total: Int
    let page: Int
}
struct OnlineServerDetails: Decodable {
    let host: String
    let httpPort: Int
    let racePort: Int
    let name: String
    let track: String
    let cars: [String]
    let free: [String: Int]
    let clients: Int
    let capacity: Int
    let password: Bool
    let pickup: Bool
    let csp: Bool
    let latency: Int
    var requiredCSPBuild: Int? = nil

    func cspError(paths: PaddockPaths) -> String? {
        CSPInstallation(game: paths.game, documents: paths.documents)
            .connectionError(required: csp, minimumBuild: requiredCSPBuild)
    }
    func missingCars(in library: ContentLibrary) -> [String] {
        cars.filter { model in !library.cars.contains { $0.id == model } }
    }
    func installedTrack(in library: ContentLibrary) -> (TrackAsset, TrackLayout)? {
        ServerContent(track: track, cars: cars).installedTrack(in: library)
    }
}
/// Transient only: passwords and account IDs never enter presets or history.
struct OnlineConnection {
    let server: OnlineServerDetails
    let car: String
    let player: String
    let password: String
    func validate(paths: PaddockPaths) throws {
        guard !player.trimmingCharacters(in: .whitespaces).isEmpty else { throw PaddockError("Введите имя пилота.") }
        guard [player, password].allSatisfy({ !$0.contains(where: { $0.isNewline || $0 == ";" || $0 == "\0" }) }) else {
            throw PaddockError("Имя и пароль не должны содержать переносы строк или точку с запятой.")
        }
        guard server.pickup else { throw PaddockError("Сервер требует бронирования. Пока доступны серверы со свободным входом (pickup).") }
        if let error = server.cspError(paths: paths) { throw PaddockError(error) }
        guard server.cars.contains(car), (server.free[car] ?? 0) > 0 else { throw PaddockError("Для этой машины нет свободных мест. Обновите сервер.") }
        guard !server.password || !password.isEmpty else { throw PaddockError("Введите пароль сервера.") }
    }
    func write(paths: PaddockPaths, guid: String) throws {
        try validate(paths: paths)
        guard guid.count == 17, guid.allSatisfy(\.isNumber) else { throw PaddockError("Не удалось получить Steam ID вошедшего аккаунта.") }
        let url = paths.documents.appendingPathComponent("cfg/race.ini")
        var race = INI(url: url)
        race.sections["REMOTE"] = ["ACTIVE": "1", "SERVER_IP": server.host, "SERVER_PORT": String(server.racePort),
            "SERVER_HTTP_PORT": String(server.httpPort), "SERVER_NAME": String(server.name.map { $0.isNewline || $0 == ";" || $0 == "\0" ? " " : $0 }),
            "REQUESTED_CAR": car, "GUID": guid, "PASSWORD": password, "NAME": player, "TEAM": ""]
        race["HEADER", "__CM_FEATURE_SET"] = "2"
        race["CAR_0", "DRIVER_NAME"] = player
        race["CAR_0", "SETUP"] = ""
        race["GHOST_CAR", "RECORDING"] = "0"; race["GHOST_CAR", "PLAYING"] = "0"
        try race.save(url)
    }
    static func clearCredentials(paths: PaddockPaths) {
        let url = paths.documents.appendingPathComponent("cfg/race.ini")
        var race = INI(url: url)
        guard race.sections["REMOTE"] != nil else { return }
        race["REMOTE", "PASSWORD"] = ""; race["REMOTE", "GUID"] = ""; race["REMOTE", "ACTIVE"] = "0"
        try? race.save(url)
    }
}
