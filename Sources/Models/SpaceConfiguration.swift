import Foundation

struct SpaceConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var desktops: [DesktopLayout]

    init(
        id: UUID = UUID(),
        name: String = "New Configuration",
        desktops: [DesktopLayout] = [DesktopLayout()]
    ) {
        self.id = id
        self.name = name
        self.desktops = desktops.isEmpty ? [DesktopLayout()] : desktops
    }

    var appLayouts: [AppLayout] {
        get {
            desktops.flatMap(\.appLayouts)
        }
        set {
            let desktopName = desktops.first?.name ?? DesktopLayout.defaultName(for: 0)
            desktops = [
                DesktopLayout(
                    id: desktops.first?.id ?? UUID(),
                    name: desktopName,
                    appLayouts: newValue
                )
            ]
        }
    }

    var totalAppCount: Int {
        desktops.reduce(into: 0) { result, desktop in
            result += desktop.appLayouts.count
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case desktops
        case appLayouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Configuration"

        if let desktops = try container.decodeIfPresent([DesktopLayout].self, forKey: .desktops),
           !desktops.isEmpty {
            self.desktops = desktops
        } else {
            let legacyAppLayouts = try container.decodeIfPresent([AppLayout].self, forKey: .appLayouts) ?? []
            self.desktops = [
                DesktopLayout(
                    name: DesktopLayout.defaultName(for: 0),
                    appLayouts: legacyAppLayouts
                )
            ]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(desktops, forKey: .desktops)
    }
}

struct DesktopLayout: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appLayouts: [AppLayout]

    init(
        id: UUID = UUID(),
        name: String = DesktopLayout.defaultName(for: 0),
        appLayouts: [AppLayout] = []
    ) {
        self.id = id
        self.name = name
        self.appLayouts = appLayouts
    }

    static func defaultName(for index: Int) -> String {
        "Desktop \(index + 1)"
    }
}

struct DisplayInfo: Codable, Equatable, Hashable {
    var uuid: String?
    var name: String
    var width: Double
    var height: Double
    var originX: Double?
    var originY: Double?
    var isBuiltIn: Bool?

    init(
        uuid: String? = nil,
        name: String,
        width: Double,
        height: Double,
        originX: Double? = nil,
        originY: Double? = nil,
        isBuiltIn: Bool? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
        self.isBuiltIn = isBuiltIn
    }

    var displayString: String {
        "\(name) (\(Int(width))×\(Int(height)))"
    }
}

struct AppLayout: Identifiable, Codable, Equatable {
    var id: UUID
    var bundleIdentifier: String
    var appName: String
    var frame: WindowFrame
    var display: DisplayInfo?

    init(
        id: UUID = UUID(),
        bundleIdentifier: String = "",
        appName: String = "",
        frame: WindowFrame = WindowFrame(),
        display: DisplayInfo? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.frame = frame
        self.display = display
    }
}

struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double = 0, y: Double = 0, width: Double = 800, height: Double = 600) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
