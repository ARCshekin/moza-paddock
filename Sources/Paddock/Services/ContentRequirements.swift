import Foundation

/// Read explicit requirements only; an extension folder alone does not mean CSP is mandatory.
enum ContentRequirements {
    static func minimumCSP(in description: String) -> String? {
        let pattern = #"(?i)(?:minimum\s+CSP\s+version|requires?\s+(?:CSP|Custom\s+Shaders\s+Patch)(?:\s+version)?)\s*[:v]?\s*(\d+\.\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let range = Range(match.range(at: 1), in: description) else { return nil }
        return String(description[range])
    }
    static func validate(_ car: CarAsset, game: URL) throws {
        guard let version = car.requiredCSP else { return }
        guard FileManager.default.fileExists(atPath: game.appendingPathComponent("dwrite.dll").path) else {
            throw PaddockError("Для «\(car.name)» нужен Custom Shaders Patch \(version) или новее. В выбранной копии игры CSP не установлен. Выберите машину без CSP или подготовьте отдельную совместимую среду.")
        }
    }
}
