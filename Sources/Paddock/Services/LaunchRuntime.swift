import AppKit
import Foundation

enum LaunchRuntime: String, CaseIterable, Identifiable {
    case standalone, crossover
    var id: String { rawValue }
    var title: String { self == .standalone ? "Wine · бесплатно" : "CrossOver" }
}

struct RuntimeStatus: Decodable {
    let version: String
    let installed: Bool
    let prepared: Bool
    let gameInstalled: Bool
    let prefix: String
    let wine: String
    let game: String
}

enum WineProcess {
    static func arguments(paths: PaddockPaths, arguments: [String]) -> [String] {
        [paths.project.appendingPathComponent("Scripts/paddock-runtime.py").path, "--root", paths.store.path,
         "wine", "--provider", paths.runtime.rawValue, "--bottle", paths.bottle, "--"] + arguments
    }
    static func make(paths: PaddockPaths, arguments: [String]) -> Process {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = self.arguments(paths: paths, arguments: arguments)
        return process
    }
}

extension PaddockController {
    static func wineCommand(_ paths: PaddockPaths, _ arguments: [String]) throws -> Data {
        try command("/usr/bin/python3", WineProcess.arguments(paths: paths, arguments: arguments))
    }
    func refreshRuntimeStatus() {
        let paths = self.paths
        DispatchQueue.global(qos: .utility).async {
            let result = try? Self.command("/usr/bin/python3", [paths.serverTool("paddock-runtime.py").path,
                                                             "--root", paths.store.path, "status"])
            let status = result.flatMap { try? JSONDecoder().decode(RuntimeStatus.self, from: $0) }
            DispatchQueue.main.async { self.runtimeStatus = status }
        }
    }
    func selectRuntime() {
        guard !gameRunning, operation == nil else { return }
        UserDefaults.standard.set(runtime.rawValue, forKey: "paddock.runtime")
        refreshRuntimeStatus()
        // Empty destination must not normalize away the user's saved selection.
        if FileManager.default.fileExists(atPath: paths.game.appendingPathComponent("acs.exe").path) { reload() }
        else { library = ContentLibrary(); message = "Подготовьте выбранную среду на вкладке «Запуск»." }
    }
    func installRuntime() {
        guard !gameRunning else { error = "Сначала завершите заезд."; return }
        let paths = self.paths
        work("Устанавливаю Wine · загрузка около 230 МБ…", completion: { self.refreshRuntimeStatus() }) {
            try Self.runtimeTask(paths, arguments: ["install"])
            return "Wine установлен. Теперь перенесите Steam с игрой."
        }
    }
    func prepareRuntime(chooseSource: Bool = false) {
        guard !gameRunning, operation == nil else { return }
        var source = PaddockPaths(project: pathsBase.project, bottle: bottle).bottleURL
            .appendingPathComponent("drive_c/Program Files (x86)/Steam")
        if chooseSource || !FileManager.default.fileExists(atPath: source.appendingPathComponent("steam.exe").path) {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
            panel.message = "Выберите папку Windows Steam с установленной Assetto Corsa."
            guard panel.runModal() == .OK, let url = panel.url else { return }; source = url
        }
        let paths = self.paths, sourcePath = source.path
        work("Готовлю отдельную среду и копию игры…", completion: {
            self.runtime = .standalone; self.selectRuntime()
        }) {
            try Self.runtimeTask(paths, arguments: ["prepare", "--source-steam", sourcePath])
            return "Среда Wine готова. Откройте Steam и проверьте вход в аккаунт."
        }
    }
    func diagnoseRuntime() {
        let paths = self.paths
        work("Проверяю Direct3D 11 и экраны…") {
            let probe = paths.project.appendingPathComponent("Bridge/build/moza-runtime-probe.exe")
            guard FileManager.default.fileExists(atPath: probe.path) else { throw PaddockError("Соберите Windows-мост скриптом build-ac-bridge.sh.") }
            try FileManager.default.createDirectory(at: paths.store, withIntermediateDirectories: true)
            let log = paths.store.appendingPathComponent("graphics-check.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
            let process = WineProcess.make(paths: paths, arguments: ["Z:" + probe.path.replacingOccurrences(of: "/", with: "\\")])
            process.standardOutput = handle; process.standardError = handle
            try process.run(); process.waitUntilExit()
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            guard process.terminationStatus == 0, text.contains("D3D11 HRESULT=0x00000000") else { throw PaddockError("Direct3D 11 не прошёл проверку. Журнал: \(log.path)") }
            let count = text.components(separatedBy: "Monitor count=0x").last?.prefix(8)
            let monitors = count.flatMap { Int($0, radix: 16) } ?? 0
            return "Direct3D 11 работает. Экранов в Wine: \(monitors). Журнал: graphics-check.log."
        }
    }
    func openSteam() {
        guard operation == nil else { return }
        let process = WineProcess.make(paths: paths, arguments: ["C:/Program Files (x86)/Steam/steam.exe"])
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); message = "Steam запускается в выбранной среде." }
        catch { self.error = error.localizedDescription }
    }
    private static func runtimeTask(_ paths: PaddockPaths, arguments: [String]) throws {
        try FileManager.default.createDirectory(at: paths.store, withIntermediateDirectories: true)
        let logURL = paths.store.appendingPathComponent("runtime-setup.log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: logURL); defer { try? handle.close() }; try handle.seekToEnd()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [paths.project.appendingPathComponent("Scripts/paddock-runtime.py").path, "--root", paths.store.path] + arguments
        process.standardOutput = handle; process.standardError = handle
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PaddockError("Не удалось подготовить Wine. Подробности: \(logURL.path)") }
    }
}
