import AppKit
import Combine
import Foundation
import MozaKit
import Darwin

struct ModPlanItem: Codable, Identifiable {
    let id: String
    let kind: String
    let destination: String
    let replaces: Bool
}

final class WheelLiveState: ObservableObject {
    @Published var steering = 0.0
    @Published var throttle = 0.0
    @Published var brake = 0.0
    @Published var pressed = Set<Int>()
}
final class SessionLiveState: ObservableObject {
    @Published var current: Int?
    @Published var best: Int?
}

final class PaddockController: ObservableObject {
    @Published var configuration = DriveConfiguration()
    @Published var library = ContentLibrary()
    @Published var presets: [DrivePreset] = []
    @Published var sessions: [SessionContext] = []
    @Published var selectedPreset: UUID?
    @Published var presetName = "Мой заезд"
    @Published var operation: String?
    @Published var message = ""
    @Published var error: String?
    @Published var connected = false
    let live = WheelLiveState()
    var steering: Double { live.steering }
    var throttle: Double { live.throttle }
    var brake: Double { live.brake }
    var pressed: Set<Int> { live.pressed }
    @Published var pendingBinding: String?
    @Published var gameRunning = false
    let timing = SessionLiveState()
    var liveLap: Int? { timing.current }
    var liveBest: Int? { timing.best }
    @Published var modSource: URL?
    @Published var modPlan: [ModPlanItem] = []
    @Published var runtime: LaunchRuntime
    @Published var runtimeStatus: RuntimeStatus?
    @Published var bottle: String
    let pathsBase: PaddockPaths
    var paths: PaddockPaths { .init(project: pathsBase.project, bottle: bottle, runtime: runtime, documentsOverride: pathsBase.documentsOverride, storeOverride: pathsBase.storeOverride) }
    var storage: PaddockStorage { .init(directory: paths.store) }
    var car: CarAsset? { library.cars.first { $0.id == configuration.car } }
    var track: TrackAsset? { library.tracks.first { $0.id == configuration.track } }
    var layout: TrackLayout? { track?.layouts.first { $0.id == configuration.layout } }
    var activePreset: DrivePreset? { presets.first { $0.id == selectedPreset } }
    var dirty: Bool { activePreset.map { $0.configuration != configuration } ?? true }
    var currentBest: Int? { sessions.filter { $0.configuration.fingerprint == configuration.fingerprint }.compactMap(\.bestMilliseconds).min() }
    var bottles: [String] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }
    var setups: [String] {
        let root = paths.documents.appendingPathComponent("setups/\(configuration.car)")
        return [configuration.track, "generic"].flatMap { directory in
            ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)) ?? [])
                .filter { $0.lowercased().hasSuffix(".ini") }.map { "\(directory)/\($0)" }
        }.sorted()
    }
    private let hid = MozaHIDInput()
    private var shared: SharedBridge?
    private var timer: Timer?
    private var previousButtons = Set<Int>()
    private var bindingDeadline = Date.distantPast
    private var ticks = 0
    private var activeSessionID: UUID?
    private var recorder = LapRecorder()
    private var launcher: Process?
    private var launcherLog: FileHandle?
    private var storageBlocked = false

    init(paths: PaddockPaths = .current) {
        pathsBase = paths; bottle = paths.bottle; runtime = paths.runtime
        do {
            let state = try PaddockStorage(directory: paths.store).load()
            configuration = state.draft; presets = state.presets; sessions = state.sessions; selectedPreset = state.selectedPreset
            presetName = presets.first { $0.id == selectedPreset }?.name ?? "Мой заезд"
        } catch {
            storageBlocked = true
            self.error = "Не удалось прочитать сохранения. Исходный файл оставлен без изменений: \(error.localizedDescription)"
        }
        // Recover the currently configured buttons on the first run.
        if presets.isEmpty {
            let controls = INI(url: paths.documents.appendingPathComponent("cfg/controls.ini"))
            for action in ButtonAction.all {
                if controls[action.id, "JOY"] == "0", let button = Int(controls[action.id, "BUTTON"]), button >= 0, button < 34 {
                    configuration.bindings[action.id] = button + 1
                }
            }
            if let angle = Int(controls["STEER", "LOCK"]), (90...2700).contains(angle) { configuration.angle = angle }
        }
        try? hid.start(productID: 4)
        shared = try? SharedBridge()
        gameRunning = !Self.runningGamePIDs().isEmpty
        // Resume recording only if the persisted game PID still owns fresh data.
        if let frame = shared?.readGraphics(), SharedBridge.nowMilliseconds() >= frame.unixMilliseconds,
           SharedBridge.nowMilliseconds() - frame.unixMilliseconds < 2000,
           let session = sessions.last(where: { $0.finished == nil && $0.gamePID == frame.pid }) {
            activeSessionID = session.id
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
        refreshRuntimeStatus(); reload()
    }
    deinit { timer?.invalidate(); hid.stop() }

    func reload() {
        guard operation == nil else { return }
        let game = paths.game
        operation = "Читаю библиотеку…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ContentLibrary.scan(game) }
            DispatchQueue.main.async {
                self.operation = nil
                switch result {
                case .success(let library): self.library = library; self.normalizeSelection(); self.persist()
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func normalizeSelection() {
        if car == nil, let first = library.cars.first { configuration.car = first.id }
        if car?.skins.contains(where: { $0.id == configuration.skin }) != true { configuration.skin = car?.skins.first?.id ?? "" }
        if track == nil, let first = library.tracks.first { configuration.track = first.id }
        if layout == nil { configuration.layout = track?.layouts.first?.id ?? "" }
        if !library.weather.contains(where: { $0.id == configuration.weather }) { configuration.weather = library.weather.first?.id ?? "4_mid_clear" }
        if !setups.contains(configuration.setup) { configuration.setup = "" }
    }

    func persist() {
        guard !storageBlocked else { return }
        do { try storage.save(.init(presets: presets, sessions: sessions, selectedPreset: selectedPreset, draft: configuration)) }
        catch { self.error = "Не удалось сохранить данные: \(error.localizedDescription)" }
    }

    func savePreset(asNew: Bool = false) {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Введите название пресета."; return }
        if !asNew, let index = presets.firstIndex(where: { $0.id == selectedPreset }) {
            presets[index].name = name; presets[index].configuration = configuration; presets[index].updated = Date()
        } else {
            let preset = DrivePreset(name: name, configuration: configuration)
            presets.append(preset); selectedPreset = preset.id
        }
        persist(); message = "Пресет «\(name)» сохранён. Результаты прежних настроек останутся в истории."
    }
    func loadPreset(_ preset: DrivePreset) {
        selectedPreset = preset.id; configuration = preset.configuration; presetName = preset.name
        normalizeSelection(); persist(); message = "Загружен пресет «\(preset.name)»."
    }
    func deletePreset(_ preset: DrivePreset) {
        presets.removeAll { $0.id == preset.id }
        if selectedPreset == preset.id { selectedPreset = nil }
        persist(); message = "Пресет удалён. История заездов сохранена."
    }
    func beginBinding(_ action: String) {
        pendingBinding = action; previousButtons = Set(hid.buttons()); bindingDeadline = Date().addingTimeInterval(15)
    }
    func unbind(_ action: String) { configuration.bindings.removeValue(forKey: action); pendingBinding = nil; persist() }

    private func poll() {
        ticks += 1
        if ticks % 40 == 0 {
            let present = hid.isConnected()
            if connected != present { connected = present }
            if !connected { hid.stop(); try? hid.start(productID: 4); connected = hid.isConnected() }
            let running = !Self.runningGamePIDs().isEmpty
            if gameRunning && !running { finishSession() }
            if gameRunning != running { gameRunning = running }
        }
        let present = hid.isConnected()
        if connected != present { connected = present }
        let position = hid.steering()?.normalized ?? 0
        if abs(live.steering - position) > 0.001 { live.steering = position }
        func pedal(_ usage: UInt32) -> Double { (hid.axes().first { $0.usage == usage }?.normalized ?? -1) / 2 + 0.5 }
        let gas = pedal(0x32), braking = pedal(0x35), buttons = Set(hid.buttons())
        if abs(live.throttle - gas) > 0.001 { live.throttle = gas }
        if abs(live.brake - braking) > 0.001 { live.brake = braking }
        if live.pressed != buttons { live.pressed = buttons }
        if let action = pendingBinding {
            if Date() > bindingDeadline { pendingBinding = nil; message = "Назначение отменено: кнопка не нажата." }
            else if let button = pressed.subtracting(previousButtons).sorted().first {
                if button > 34 { error = "Мост поддерживает кнопки 1–34; выберите другую кнопку." }
                else {
                    for (other, assigned) in configuration.bindings where assigned == button && other != action {
                        configuration.bindings.removeValue(forKey: other)
                    }
                    configuration.bindings[action] = button; if action == "BRIDGE_CLUTCH" { configuration.autoClutch = false }; message = "Назначена кнопка \(button)."; persist()
                }
                pendingBinding = nil
            }
        }
        previousButtons = pressed
        if ticks % 5 == 0 { readLap() }
    }

    private func readLap() {
        guard let frame = shared?.readGraphics(), frame.unixMilliseconds <= SharedBridge.nowMilliseconds(),
              SharedBridge.nowMilliseconds() - frame.unixMilliseconds < 2000 else {
            if timing.current != nil { timing.current = nil }
            if timing.best != nil { timing.best = nil }
            return
        }
        if timing.current != frame.currentTime { timing.current = frame.currentTime }
        if timing.best != frame.bestTime { timing.best = frame.bestTime }
        guard let id = activeSessionID, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var context = sessions[index]
        let before = context.gamePID
        if recorder.consume(frame, now: ProcessInfo.processInfo.systemUptime, context: &context) || before != context.gamePID {
            sessions[index] = context; persist()
        }
    }

    private func finishSession() {
        readLap()
        if let id = activeSessionID, let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].finished = Date(); persist()
        }
        activeSessionID = nil
    }

    func applyWheel() {
        guard !gameRunning else { error = "Завершите заезд перед изменением угла и назначений."; return }
        let snapshot = configuration; let paths = self.paths
        work("Применяю настройки руля…") {
            try Self.setWheelAngle(snapshot.angle)
            try ConfigurationWriter.write(snapshot, paths: paths)
            return "Угол \(snapshot.angle)° и назначения сохранены для следующего заезда."
        }
    }

    static func setWheelAngle(_ angle: Int) throws {
        guard (90...2700).contains(angle), angle % 2 == 0 else { throw PaddockError("Недопустимый угол поворота.") }
        let device = try MozaDevice.discover(); defer { device.close() }
        device.writesEnabled = true
        let results = try device.setRotationAngle(degrees: angle)
        guard results.allSatisfy({ $0.verified == true }) else { throw PaddockError("База не подтвердила угол поворота.") }
    }

    func launch() {
        guard operation == nil else { return }
        guard launcher?.isRunning != true else { error = "Предыдущий сеанс ещё закрывается. Подождите завершения Steam."; return }
        guard Self.runningGamePIDs().isEmpty else { error = "Заезд уже идёт. Нажмите «Завершить заезд», чтобы выбрать другой."; return }
        normalizeSelection()
        guard let car, track != nil, let layout else { error = "Выберите установленную машину и трассу."; return }
        if configuration.mode == .race {
            guard layout.hasAI else { error = "В этой конфигурации трассы нет AI-линии. Выберите тренировку или другую трассу."; return }
            configuration.opponents = min(configuration.opponents, max(0, layout.pits - 1))
        }
        let snapshot = configuration, paths = self.paths
        let context = SessionContext(presetID: selectedPreset, presetName: activePreset?.name ?? "Без пресета", configuration: snapshot, carName: car.name, trackName: layout.name)
        operation = "Готовлю заезд…"; persist()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if paths.runtime == .standalone {
                    let statusData = try Self.command("/usr/bin/python3", [paths.project.appendingPathComponent("Scripts/paddock-runtime.py").path, "--root", paths.store.path, "status"])
                    let status = try JSONDecoder().decode(RuntimeStatus.self, from: statusData)
                    guard status.installed, status.prepared, status.gameInstalled else { throw PaddockError("Подготовьте Wine и перенесите игру на вкладке «Запуск».") }
                }
                try Self.ensureSteam(paths: paths)
                try Self.setWheelAngle(snapshot.angle)
                try ConfigurationWriter.write(snapshot, paths: paths)
                // Update game-local DLL only while the simulator is closed.
                let source = paths.project.appendingPathComponent("Bridge/build/dinput8.dll")
                let destination = paths.game.appendingPathComponent("dinput8.dll")
                let data = try Data(contentsOf: source)
                if (try? Data(contentsOf: destination)) != data { try data.write(to: destination, options: .atomic) }
                _ = try Self.wineCommand(paths, ["reg", "add", "HKCU\\Software\\Wine\\AppDefaults\\acs.exe\\DllOverrides", "/v", "dinput8", "/t", "REG_SZ", "/d", "native,builtin", "/f"])
                // A fresh bridge applies this preset's gain. Hardware effects expire on termination.
                Self.stopBridges()
                Thread.sleep(forTimeInterval: 0.25)
                DispatchQueue.main.async {
                    do {
                        self.sessions.append(context); self.activeSessionID = context.id; self.recorder = LapRecorder(); self.persist()
                        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                        process.arguments = [paths.project.appendingPathComponent("Scripts/play-assetto.command").path]
                        var environment = ProcessInfo.processInfo.environment
                        environment["MOZA_AC_GAIN"] = String(snapshot.gain)
                        environment["MOZA_AC_BOTTLE"] = paths.bottle
                        environment["MOZA_AC_RUNTIME"] = paths.runtime.rawValue
                        environment["MOZA_AC_ROOT"] = paths.store.path
                        environment["MOZA_AC_KEEP_VIDEO"] = "1"
                        process.environment = environment
                        let log = paths.store.appendingPathComponent("launcher.log")
                        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
                        let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd()
                        process.standardOutput = handle; process.standardError = handle
                        process.terminationHandler = { [weak self] process in
                            DispatchQueue.main.async {
                                guard let self else { return }
                                if process.terminationStatus != 0 {
                                    if process.terminationStatus == 99 {
                                        self.error = "Assetto Corsa аварийно завершилась (код 99). Проверьте совместимость выбранного мода. Журнал игры: \(paths.documents.appendingPathComponent("logs/log.txt").path)"
                                    } else {
                                        self.error = "Игра завершилась с кодом \(process.terminationStatus). Проверьте Steam и подключение внешнего экрана. Журнал: \(log.path)"
                                    }
                                }
                                if self.activeSessionID == context.id { self.finishSession() }
                                guard self.launcher === process else { return }
                                self.launcher = nil
                                try? self.launcherLog?.close(); self.launcherLog = nil
                                DispatchQueue.global(qos: .utility).async {
                                    _ = try? Self.command("/usr/bin/python3", [paths.project.appendingPathComponent("Scripts/paddock-runtime.py").path,
                                                                           "--root", paths.store.path, "cleanup-logs"])
                                }
                            }
                        }
                        self.launcherLog = handle; self.launcher = process
                        try process.run(); self.operation = nil
                        self.message = "Заезд запускается на внешнем экране. Круги будут сохранены в историю автоматически."
                    } catch { self.operation = nil; self.error = error.localizedDescription; self.finishSession() }
                }
            } catch { DispatchQueue.main.async { self.operation = nil; self.error = error.localizedDescription } }
        }
    }

    func stopGame() {
        readLap()
        for pid in Self.runningGamePIDs() { Darwin.kill(pid, SIGTERM) }
        finishSession(); gameRunning = false; message = "Заезд завершён. Результаты сохранены."
    }

    func emergencyStop() { Self.stopBridges(); message = "Мост и отдача остановлены. Для управления заново запустите заезд." }

    func chooseMod() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.message = "Выберите ZIP, 7z, RAR или папку с автомобилями / трассами."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspectMod(url)
    }
    func inspectMod(_ url: URL) {
        guard operation == nil else { return }
        modSource = url; modPlan = []
        let paths = self.paths
        operation = "Проверяю и распаковываю мод…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.modCommand("inspect", source: url, paths: paths) }
            DispatchQueue.main.async {
                self.operation = nil
                switch result { case .success(let plan): self.modPlan = plan
                case .failure(let error): self.error = error.localizedDescription }
            }
        }
    }
    func installMod() {
        guard !gameRunning else { error = "Завершите игру перед установкой модов."; return }
        guard let source = modSource, !modPlan.isEmpty else { return }
        let paths = self.paths
        work("Устанавливаю моды и сохраняю резервные копии…", completion: { self.modPlan = []; self.modSource = nil; self.reload() }) {
            let plan = try Self.modCommand("install", source: source, paths: paths)
            return "Установлено пакетов: \(plan.count). Предыдущие версии сохранены в ModBackups."
        }
    }
    static func modCommand(_ action: String, source: URL, paths: PaddockPaths) throws -> [ModPlanItem] {
        let data = try command("/usr/bin/python3", [paths.project.appendingPathComponent("Scripts/paddock-mods.py").path, action, source.path, "--game", paths.game.path, "--store", paths.store.path], allowFailureJSON: true)
        struct Response: Decodable { var items: [ModPlanItem]?; var error: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error { throw PaddockError(error) }
        return response.items ?? []
    }

    func exportRecords() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Assetto-Corsa-records.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(sessions).write(to: url, options: .atomic); message = "История экспортирована." }
        catch { self.error = error.localizedDescription }
    }

    func work(_ title: String, completion: (() -> Void)? = nil, operation: @escaping () throws -> String) {
        guard self.operation == nil else { return }
        self.operation = title
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.operation = nil
                switch result { case .success(let text): self.message = text; completion?()
                case .failure(let error): self.error = error.localizedDescription }
            }
        }
    }

    static func command(_ executable: String, _ arguments: [String], allowFailureJSON: Bool = false) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        if process.terminationStatus != 0 && !allowFailureJSON {
            throw PaddockError(String(data: data, encoding: .utf8) ?? "Операция завершилась с ошибкой.")
        }
        return data
    }
    static func ensureSteam(paths: PaddockPaths) throws {
        func loggedIn() -> Bool {
            // C: paths look identical across providers. Match the loaded file
            // in this prefix so another running Steam cannot satisfy this check.
            let steamFile = paths.bottleURL.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            guard let owners = try? command("/usr/sbin/lsof", ["-Fpc", steamFile.path]),
                  String(data: owners, encoding: .utf8)?.lowercased().components(separatedBy: .newlines).contains("csteam.exe") == true else { return false }
            // The client clears ActiveUser on sign-out. Query Wine's live
            // registry, not a potentially unflushed user.reg on disk.
            guard let data = try? wineCommand(paths, ["reg", "query", "HKCU\\Software\\Valve\\Steam\\ActiveProcess", "/v", "ActiveUser"]),
                  let text = String(data: data, encoding: .utf8),
                  let regex = try? NSRegularExpression(pattern: "REG_DWORD\\s+0x([0-9a-fA-F]+)"),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return false }
            return (UInt64(text[range], radix: 16) ?? 0) != 0
        }
        if loggedIn() { return }
        let steam = WineProcess.make(paths: paths, arguments: ["C:/Program Files (x86)/Steam/steam.exe", "-silent"])
        steam.standardOutput = FileHandle.nullDevice; steam.standardError = FileHandle.nullDevice
        try steam.run()
        for _ in 0..<25 {
            Thread.sleep(forTimeInterval: 1)
            if loggedIn() { return }
        }
        throw PaddockError("Steam открыт, но вход ещё не завершён. Войдите в Steam и повторите запуск заезда.")
    }
    static func runningGamePIDs() -> [pid_t] {
        let data = try? command("/bin/ps", ["ax", "-o", "pid=,command="])
        return gamePIDs(in: String(data: data ?? Data(), encoding: .utf8) ?? "")
    }
    static func gamePIDs(in processes: String) -> [pid_t] {
        processes.components(separatedBy: .newlines).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { return nil }
            let executable = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !executable.contains("winewrapper"),
                  executable == "acs.exe" || executable.hasSuffix("/acs.exe") || executable.hasSuffix("\\acs.exe") else { return nil }
            return Int32(parts[0])
        }
    }
    static func stopBridges() {
        let data = try? command("/bin/ps", ["ax", "-o", "pid=,command="])
        for line in String(data: data ?? Data(), encoding: .utf8)?.components(separatedBy: .newlines) ?? [] {
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = Int32(parts[0]), let executable = parts[1].split(separator: " ").first,
                  executable.hasSuffix("/moza-ac-bridge") else { continue }
            Darwin.kill(pid, SIGTERM)
        }
    }
}
