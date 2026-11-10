import Combine
import Foundation

private struct OnlineFailure: Decodable { let error: String? }

final class OnlineBrowser: ObservableObject {
    @Published var query = ""
    @Published var directAddress = ""
    @Published var servers: [OnlineServer] = []
    @Published var total = 0
    @Published var page = 1
    @Published var loading = false
    @Published var detail: OnlineServerDetails?
    @Published var car = ""
    @Published var player = "Driver"
    @Published var password = ""
    @Published var error: String?
    @Published var onlyAvailable = false
    @Published private(set) var favorites: [FavoriteServer] = []
    @Published private(set) var favoritesError: String?
    private let favoritesStore: FavoriteServersStore
    private var favoritesBlocked = false
    private var request = UUID()

    init(store: URL = PaddockPaths.current.store) {
        favoritesStore = FavoriteServersStore(directory: store)
        do { favorites = try favoritesStore.load() }
        catch { favoritesBlocked = true; favoritesError = "Не удалось прочитать избранное. Файл сохранён без изменений: \(error.localizedDescription)" }
    }
    func isFavorite(host: String, port: Int) -> Bool {
        favorites.contains { $0.id == FavoriteServer(host: host, httpPort: port, name: "").id }
    }
    func toggleFavorite(host: String, port: Int, name: String) {
        guard !favoritesBlocked else { return }
        let value = FavoriteServer(host: host, httpPort: port, name: name)
        var next = favorites
        if let index = next.firstIndex(where: { $0.id == value.id }) { next.remove(at: index) }
        else { next.append(value) }
        do { try favoritesStore.save(next); favorites = next; favoritesError = nil }
        catch { favoritesError = error.localizedDescription }
    }

    static func run<T: Decodable>(_ paths: PaddockPaths, _ arguments: [String]) throws -> T {
        let data = try PaddockController.command("/usr/bin/python3", [paths.serverTool("paddock-online.py").path] + arguments, allowFailureJSON: true)
        if let failure = try? JSONDecoder().decode(OnlineFailure.self, from: data), let error = failure.error { throw PaddockError(error) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func refresh(paths: PaddockPaths, page: Int = 1) {
        guard !loading else { return }
        loading = true; error = nil
        let query = self.query
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<OnlineDirectory, Error> = Result { try Self.run(paths, ["list", "--query", query, "--page", String(page)]) }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let list): self.servers = list.items; self.total = list.total; self.page = list.page
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
    func inspect(_ address: String, paths: PaddockPaths, library: ContentLibrary) {
        guard !loading else { return }
        let id = UUID(); request = id
        loading = true; error = nil; detail = nil; password = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<OnlineServerDetails, Error> = Result { try Self.run(paths, ["inspect", "--address", address]) }
            DispatchQueue.main.async {
                guard self.request == id else { return }
                self.loading = false
                switch result {
                case .success(let server):
                    self.detail = server
                    self.car = server.cars.first(where: { model in library.cars.contains { $0.id == model } && (server.free[model] ?? 0) > 0 }) ?? ""
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}
