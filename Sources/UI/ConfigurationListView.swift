import SwiftUI

struct ConfigurationListView: View {
    @Bindable var store: ConfigurationStore
    @State private var selection: SpaceConfiguration.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.configurations) { config in
                    NavigationLink(value: config.id) {
                        VStack(alignment: .leading) {
                            Text(config.name)
                                .font(.headline)
                            Text("\(config.appLayouts.count) app(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    selection = nil
                    store.remove(at: offsets)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(action: deleteSelection) {
                        Label("Delete", systemImage: "minus")
                    }
                    .disabled(selection == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addConfiguration) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .contextMenu(forSelectionType: SpaceConfiguration.ID.self) { ids in
                Button("Delete", role: .destructive) {
                    selection = nil
                    for id in ids { store.remove(id: id) }
                }
            }
        } detail: {
            if let id = selection,
               store.configurations.contains(where: { $0.id == id }) {
                ConfigurationEditorView(
                    config: Binding(
                        get: {
                            let idx = store.configurations.firstIndex(where: { $0.id == id })
                                ?? store.configurations.startIndex
                            return store.configurations.indices.contains(idx)
                                ? store.configurations[idx]
                                : SpaceConfiguration()
                        },
                        set: { store.update($0) }
                    ),
                    slotIndex: store.configurations.firstIndex(where: { $0.id == id }) ?? 0
                )
                .id(id)
            } else {
                Text("Select or create a configuration")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addConfiguration() {
        let config = SpaceConfiguration()
        store.add(config)
        selection = config.id
    }

    private func deleteSelection() {
        guard let id = selection else { return }
        selection = nil
        store.remove(id: id)
    }
}
