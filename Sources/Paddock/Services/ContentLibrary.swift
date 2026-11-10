import Foundation

struct CarSkin: Identifiable { let id: String; let name: String; let preview: URL? }
struct CarAsset: Identifiable {
    let id: String; let name: String; let brand: String; let power: String; let weight: String
    let directory: URL; let skins: [CarSkin]
    var requiredCSP: String? = nil
    var preview: URL? { skins.first?.preview }
}
struct TrackLayout: Identifiable { let id: String; let name: String; let length: String; let preview: URL?; let outline: URL?; let pits: Int; let hasAI: Bool }
struct TrackAsset: Identifiable { let id: String; let name: String; let directory: URL; let layouts: [TrackLayout] }
struct WeatherAsset: Identifiable { let id: String; let name: String }

struct ContentLibrary {
    var cars: [CarAsset] = []
    var tracks: [TrackAsset] = []
    var weather: [WeatherAsset] = []
    static func metadata(_ url: URL, key: String) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let string = object[key] as? String { return string }
        // Original Kunos JSON sometimes contains literal newlines in description.
        guard let text = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return "" }
        let raw = String(text[range])
        if let decoded = try? JSONSerialization.jsonObject(with: Data(("[\"" + raw + "\"]").utf8)) as? [String] { return decoded.first ?? raw }
        return raw
    }
    static func scan(_ game: URL) throws -> ContentLibrary {
        let fm = FileManager.default
        func folders(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        func existing(_ url: URL) -> URL? { fm.fileExists(atPath: url.path) ? url : nil }
        guard fm.fileExists(atPath: game.appendingPathComponent("acs.exe").path) else { throw PaddockError("Assetto Corsa не найдена в выбранной бутылке CrossOver.") }
        var result = ContentLibrary()
        for folder in folders(game.appendingPathComponent("content/cars")) {
            let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            guard files.contains(where: { $0.lowercased().hasSuffix(".kn5") }) else { continue }
            let ui = folder.appendingPathComponent("ui/ui_car.json")
            let id = folder.lastPathComponent
            let skins = folders(folder.appendingPathComponent("skins")).map { skin in
                let name = metadata(skin.appendingPathComponent("ui_skin.json"), key: "skinname")
                return CarSkin(id: skin.lastPathComponent, name: name.isEmpty ? skin.lastPathComponent.replacingOccurrences(of: "_", with: " ") : name,
                               preview: existing(skin.appendingPathComponent("preview.jpg")) ?? existing(skin.appendingPathComponent("preview.png")))
            }
            result.cars.append(.init(id: id, name: metadata(ui, key: "name").nonempty ?? id,
                                     brand: metadata(ui, key: "brand"), power: metadata(ui, key: "bhp"), weight: metadata(ui, key: "weight"), directory: folder, skins: skins, requiredCSP: ContentRequirements.minimumCSP(in: metadata(ui, key: "description"))))
        }
        for folder in folders(game.appendingPathComponent("content/tracks")) {
            let ui = folder.appendingPathComponent("ui")
            var layouts: [TrackLayout] = []
            let roots = [ui] + folders(ui)
            for root in roots {
                let json = root.appendingPathComponent("ui_track.json")
                guard fm.fileExists(atPath: json.path) else { continue }
                let id = root == ui ? "" : root.lastPathComponent
                let models = folder.appendingPathComponent(id.isEmpty ? "models.ini" : "models_\(id).ini")
                let hasModels = fm.fileExists(atPath: models.path) || ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(".kn5") }
                guard hasModels else { continue }
                let layoutRoot = id.isEmpty ? folder : folder.appendingPathComponent(id)
                layouts.append(.init(id: id, name: metadata(json, key: "name").nonempty ?? folder.lastPathComponent,
                                     length: metadata(json, key: "length"), preview: existing(root.appendingPathComponent("preview.png")),
                                     outline: existing(root.appendingPathComponent("outline.png")), pits: Int(metadata(json, key: "pitboxes")) ?? 1,
                                     hasAI: fm.fileExists(atPath: layoutRoot.appendingPathComponent("ai/fast_lane.ai").path)))
            }
            if !layouts.isEmpty { result.tracks.append(.init(id: folder.lastPathComponent, name: layouts.first!.name, directory: folder, layouts: layouts)) }
        }
        result.cars.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.tracks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.weather = folders(game.appendingPathComponent("content/weather")).map {
            let config = INI(url: $0.appendingPathComponent("weather.ini"))
            return WeatherAsset(id: $0.lastPathComponent, name: config["LAUNCHER", "NAME"].nonempty ?? $0.lastPathComponent.replacingOccurrences(of: "_", with: " "))
        }
        return result
    }
}

extension String { var nonempty: String? { isEmpty ? nil : self } }
