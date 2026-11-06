import Foundation
import CryptoKit

struct PaddockError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

enum DriveMode: String, Codable, CaseIterable, Identifiable {
    case practice, hotlap, race, drift, timeAttack
    var id: String { rawValue }
    var title: String {
        switch self {
        case .practice: return "Тренировка"
        case .hotlap: return "Быстрый круг"
        case .race: return "Гонка с AI"
        case .drift: return "Дрифт"
        case .timeAttack: return "Time Attack"
        }
    }
    var code: Int {
        switch self { case .practice: return 1; case .race: return 3; case .hotlap: return 4; case .timeAttack: return 5; case .drift: return 6 }
    }
    var spawn: String { self == .practice || self == .drift ? "PIT" : self == .hotlap ? "HOTLAP_START" : "START" }
}

struct ButtonAction: Identifiable {
    let id: String
    let name: String
    let symbol: String
    static let all: [ButtonAction] = [
        .init(id: "GEARUP", name: "Передача вверх", symbol: "plus"),
        .init(id: "GEARDN", name: "Передача вниз", symbol: "minus"),
        .init(id: "HANDBRAKE", name: "Ручной тормоз", symbol: "parkingsign.brakesignal"),
        .init(id: "ACTION_HEADLIGHTS", name: "Фары", symbol: "headlight.high.beam"),
        .init(id: "ACTION_HEADLIGHTS_FLASH", name: "Моргнуть фарами", symbol: "lightbulb"),
        .init(id: "ACTION_HORN", name: "Сигнал", symbol: "speaker.wave.2"),
        .init(id: "ACTION_CHANGE_CAMERA", name: "Сменить камеру", symbol: "camera"),
        .init(id: "GLANCELEFT", name: "Взгляд влево", symbol: "arrow.left"),
        .init(id: "GLANCERIGHT", name: "Взгляд вправо", symbol: "arrow.right"),
        .init(id: "GLANCEBACK", name: "Взгляд назад", symbol: "arrow.uturn.backward"),
        .init(id: "DRS", name: "DRS", symbol: "wind"),
        .init(id: "KERS", name: "KERS", symbol: "bolt"),
        .init(id: "TCUP", name: "TC +", symbol: "plus.circle"),
        .init(id: "TCDN", name: "TC −", symbol: "minus.circle"),
        .init(id: "ABSUP", name: "ABS +", symbol: "plus.circle"),
        .init(id: "ABSDN", name: "ABS −", symbol: "minus.circle"),
        .init(id: "BALANCEUP", name: "Баланс тормозов +", symbol: "plus.circle"),
        .init(id: "BALANCEDN", name: "Баланс тормозов −", symbol: "minus.circle")
    ]
}

struct DriveConfiguration: Codable, Equatable {
    var car = "lotus_elise_sc"
    var skin = "0_racing_green"
    var track = "magione"
    var layout = ""
    var setup = ""
    var mode = DriveMode.practice
    var angle = 900
    var gain = 1.0
    var opponents = 5
    var ai = 90
    var laps = 5
    var minutes = 30
    var weather = "4_mid_clear"
    var temperature = 26
    var hour = 13.0
    var autoClutch = true
    var autoShift = false
    var penalties = true
    var abs = 1
    var traction = 1
    var width = 1920
    var height = 1080
    var bindings: [String: Int] = ["GEARUP": 14, "GEARDN": 13] // one-based HID numbers
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct DrivePreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var configuration: DriveConfiguration
    var updated = Date()
}

struct SessionContext: Codable, Identifiable {
    var id = UUID()
    var presetID: UUID?
    var presetName: String
    var configuration: DriveConfiguration
    var carName: String
    var trackName: String
    var started = Date()
    var finished: Date?
    var bestMilliseconds: Int?
    var laps: [LapEntry] = []
    var gamePID: UInt32?
}

struct LapEntry: Codable, Identifiable {
    var id = UUID()
    var number: Int
    var milliseconds: Int
    var date = Date()
    var matchedGameBest: Bool
}

func lapText(_ milliseconds: Int?) -> String {
    guard let value = milliseconds, value > 0 else { return "—:——.———" }
    return String(format: "%d:%02d.%03d", value / 60000, value / 1000 % 60, value % 1000)
}

struct PaddockPaths {
    let project: URL
    var bottle: String
    var runtime: LaunchRuntime = .crossover
    var documentsOverride: URL? = nil
    var storeOverride: URL? = nil
    var bottleURL: URL {
        runtime == .standalone ? store.appendingPathComponent("Prefixes/assetto") :
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles/\(bottle)")
    }
    var game: URL { bottleURL.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/assettocorsa") }
    var documents: URL { documentsOverride ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Assetto Corsa") }
    var store: URL { storeOverride ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MozaPaddock") }
    static var current: PaddockPaths {
        let resource = Bundle.main.resourceURL?.appendingPathComponent("project-path.txt")
        let project = resource.flatMap { try? String(contentsOf: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? FileManager.default.currentDirectoryPath
        return .init(project: URL(fileURLWithPath: project), bottle: UserDefaults.standard.string(forKey: "paddock.bottle") ?? "Steam-3", runtime: LaunchRuntime(rawValue: UserDefaults.standard.string(forKey: "paddock.runtime") ?? "") ?? .crossover)
    }
}
