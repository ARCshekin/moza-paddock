import Combine
import Foundation

final class LANBrowser: ObservableObject {
    @Published var ports = "9600-9610"
    @Published private(set) var servers: [OnlineServer] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var searched = false
    func refresh(paths: PaddockPaths) {
        guard !loading else { return }
        loading = true; error = nil
        let targets = Set(["127.0.0.1"] + ServerLANAddress.current().flatMap { [$0.ip, $0.broadcast].compactMap { $0 } }).sorted()
        let arguments = ["lan", "--ports", ports] + targets.prefix(32).flatMap { ["--target", $0] }
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<OnlineDirectory, Error> = Result { try OnlineBrowser.run(paths, arguments) }
            DispatchQueue.main.async {
                self.loading = false; self.searched = true
                switch result {
                case .success(let list): self.servers = list.items
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}
