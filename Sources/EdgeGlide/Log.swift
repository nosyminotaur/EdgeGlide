import os

/// Loggers for every subsystem. View them with:
/// `log show --last 5m --info --predicate 'subsystem == "com.edgeglide.app"'`
enum Log {
    static let subsystem = "com.edgeglide.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let touch = Logger(subsystem: subsystem, category: "touch")
    static let volume = Logger(subsystem: subsystem, category: "volume")
    static let brightness = Logger(subsystem: subsystem, category: "brightness")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let haptics = Logger(subsystem: subsystem, category: "haptics")
}
