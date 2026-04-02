import Foundation

struct SpaceConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appLayouts: [AppLayout]

    init(
        id: UUID = UUID(),
        name: String = "New Configuration",
        appLayouts: [AppLayout] = []
    ) {
        self.id = id
        self.name = name
        self.appLayouts = appLayouts
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
