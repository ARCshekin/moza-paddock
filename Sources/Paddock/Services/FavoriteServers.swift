import Foundation

struct FavoriteServer: Codable, Identifiable, Equatable {
    let host: String
    let httpPort: Int
    let name: String
    var id: String { "\(host.lowercased()):\(httpPort)" }
}

struct FavoriteServersStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("favorite-servers.json") }
    func load() throws -> [FavoriteServer] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([FavoriteServer].self, from: Data(contentsOf: file))
    }
    func save(_ values: [FavoriteServer]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
    }
}
