import Foundation

/// Reads the selected game's CSP manifest and effective BASIC/ENABLED setting.
/// A folder or an installer receipt alone is not evidence of an active patch.
struct CSPInstallation {
    let installed: Bool
    let enabled: Bool
    let version: String
    let build: Int?

    init(game: URL, documents: URL) {
        installed = FileManager.default.fileExists(atPath: game.appendingPathComponent("dwrite.dll").path)
        let manifest = INI(url: game.appendingPathComponent("extension/config/data_manifest.ini"))
        version = manifest["VERSION", "SHADERS_PATCH"]
        build = Int(manifest["VERSION", "SHADERS_PATCH_BUILD"]).flatMap { $0 > 0 ? $0 : nil }
        let defaults = INI(url: game.appendingPathComponent("extension/config/general.ini"))
        let user = INI(url: documents.appendingPathComponent("cfg/extension/general.ini"))
        let setting = user["BASIC", "ENABLED"].nonempty ?? defaults["BASIC", "ENABLED"]
        enabled = ["1", "true", "yes", "on"].contains(setting.lowercased())
    }

    func connectionError(required: Bool, minimumBuild: Int?) -> String? {
        // CSP's reserved version ID means that the server explicitly forbids CSP.
        if minimumBuild == 999999 {
            return installed && enabled ? "Этот сервер требует отключить CSP. Выберите сервер с поддержкой CSP или отключите патч в выбранной игре." : nil
        }
        guard required else { return nil }
        guard installed else { return "Сервер требует CSP. В выбранной копии игры CSP не установлен." }
        guard enabled else { return "Сервер требует CSP, но патч отключён. Включите CSP в выбранной игре." }
        guard let build else { return "Не удалось определить сборку CSP: проверьте extension/config/data_manifest.ini в выбранной игре." }
        let minimum = max(1061, minimumBuild ?? 1061)
        guard build >= minimum else { return "Сервер требует CSP build \(minimum) или новее; установлен build \(build). Обновите CSP." }
        return nil
    }

    var title: String {
        "CSP" + (version.isEmpty ? "" : " \(version)") + (build.map { " · build \($0)" } ?? "")
    }
}
