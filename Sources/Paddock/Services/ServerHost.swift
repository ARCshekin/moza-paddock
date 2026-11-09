import AppKit
import Combine
import Foundation
import Darwin

/// Owns only the dedicated server child, never the game's Wine processes.
final class ServerHost: ObservableObject {
    @Published var draft = HostedServerDraft()
    @Published var executable: URL?
    @Published private(set) var preparing = false
    @Published private(set) var running = false
    @Published private(set) var stopping = false
    @Published private(set) var folder: URL?
    @Published private(set) var status = "Сервер ещё не создан"
    @Published var error: String?
    private var process: Process?
    private var log: FileHandle?
    private var activeDraft: HostedServerDraft?
    private var terminationObserver: AnyCancellable?
    init() {
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stop() }
    }
    var connectionHint: String {
        let current = activeDraft ?? draft
        return "На этом Mac: 127.0.0.1:\(current.httpPort). Для друзей: IP этого Mac в локальной сети и порт \(current.httpPort). Для интернета пробросьте \(current.racePort) TCP/UDP и \(current.httpPort) TCP на роутере. При CGNAT нужен внешний IP или VPN с поддержкой входящих подключений."
    }
    func chooseExecutable() {
        let panel = NSOpenPanel(); panel.message = "Выберите acServer.exe из установленного Assetto Corsa Dedicated Server или папки игры server."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executable = url
    }
    func start(paths: PaddockPaths, library: ContentLibrary) {
        guard !running, !preparing else { return }
        let snapshot = draft
        let source = executable ?? paths.game.appendingPathComponent("server/acServer.exe")
        preparing = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.prepare(snapshot, source: source, paths: paths, library: library) }
            DispatchQueue.main.async {
                self.preparing = false
                do {
                    let destination = try result.get()
                    self.folder = destination; self.activeDraft = snapshot
                    let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                    child.arguments = [paths.project.appendingPathComponent("Scripts/paddock-server.py").path,
                                       "--root", paths.store.path, "--directory", destination.path]
                    let log = try FileHandle(forWritingTo: destination.appendingPathComponent("server.log"))
                    child.standardOutput = log; child.standardError = log
                    child.terminationHandler = { [weak self] child in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            let wasStopping = self.stopping
                            self.running = false; self.stopping = false; self.process = nil
                            try? self.log?.close(); self.log = nil
                            self.status = wasStopping ? "Сервер остановлен" : "Сервер завершился · код \(child.terminationStatus). Откройте журнал."
                        }
                    }
                    try child.run()
                    self.log = log; self.process = child; self.running = true
                    self.status = "Процесс запущен · готовность и ошибки смотрите в журнале"
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func stop() {
        guard let process, process.isRunning, !stopping else { return }
        stopping = true; status = "Останавливаю сервер…"; process.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak process] in
            guard let self, let process, self.process === process, process.isRunning else { return }
            // Only the still-owned child can be killed; never target wineserver or the game.
            kill(process.processIdentifier, SIGKILL)
        }
    }
    deinit { if process?.isRunning == true { process?.terminate() }; try? log?.close() }

    static func prepare(_ draft: HostedServerDraft, source: URL, paths: PaddockPaths, library: ContentLibrary) throws -> URL {
        let fm = FileManager.default
        let (config, entries) = try draft.configuration(library: library, adminPassword: UUID().uuidString)
        guard source.lastPathComponent.lowercased() == "acserver.exe", fm.fileExists(atPath: source.path) else {
            throw PaddockError("Не найден acServer.exe. Установите Dedicated Server через Steam или выберите существующий файл.")
        }
        let destination = paths.store.appendingPathComponent("Servers/\(UUID().uuidString)")
        try fm.createDirectory(at: destination.appendingPathComponent("cfg"), withIntermediateDirectories: true)
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
            try fm.copyItem(at: source, to: destination.appendingPathComponent("acServer.exe"))
            let siblings = try fm.contentsOfDirectory(at: source.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            for dll in siblings where dll.pathExtension.lowercased() == "dll" {
                try fm.copyItem(at: dll, to: destination.appendingPathComponent(dll.lastPathComponent))
            }
            // Dedicated servers require physics checksums, not textures or game assets.
            let car = library.cars.first { $0.id == draft.car }!
            let carTarget = destination.appendingPathComponent("content/cars/\(draft.car)")
            try fm.createDirectory(at: carTarget, withIntermediateDirectories: true)
            let packed = car.directory.appendingPathComponent("data.acd")
            if fm.fileExists(atPath: packed.path) { try fm.copyItem(at: packed, to: carTarget.appendingPathComponent("data.acd")) }
            else { throw PaddockError("Для сервера нужен data.acd выбранной машины. Выберите машину с упакованной физикой.") }
            let track = library.tracks.first { $0.id == draft.track }!
            let relative = draft.layout.isEmpty ? "data/surfaces.ini" : "\(draft.layout)/data/surfaces.ini"
            let surfaces = destination.appendingPathComponent("content/tracks/\(draft.track)/\(relative)")
            try fm.createDirectory(at: surfaces.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: track.directory.appendingPathComponent(relative), to: surfaces)
            try config.save(destination.appendingPathComponent("cfg/server_cfg.ini"))
            try entries.save(destination.appendingPathComponent("cfg/entry_list.ini"))
            for name in ["server_cfg.ini", "entry_list.ini"] {
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.appendingPathComponent("cfg/\(name)").path)
            }
            fm.createFile(atPath: destination.appendingPathComponent("server.log").path, contents: nil, attributes: [.posixPermissions: 0o600])
            return destination
        } catch { try? fm.removeItem(at: destination); throw error }
    }
}
