import Foundation
import Observation

@MainActor
@Observable
final class ConfigurationStore {
    private static let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MagicDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("configurations.json")
    }()

    private(set) var configurations: [SpaceConfiguration]
    private var saveTask: Task<Void, Never>?

    init() {
        self.configurations = Self.load()
    }

    func add(_ config: SpaceConfiguration) {
        configurations.append(config)
        scheduleSave()
    }

    func update(_ config: SpaceConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == config.id }) else { return }
        configurations[index] = config
        scheduleSave()
    }

    func remove(at offsets: IndexSet) {
        configurations.remove(atOffsets: offsets)
        scheduleSave()
    }

    func remove(id: SpaceConfiguration.ID) {
        configurations.removeAll { $0.id == id }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(configurations)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            print("Failed to save configurations: \(error)")
        }
    }

    private static func load() -> [SpaceConfiguration] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        return (try? JSONDecoder().decode([SpaceConfiguration].self, from: data)) ?? []
    }
}
