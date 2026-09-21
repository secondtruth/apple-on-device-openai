import Logging

enum LogBootstrap {
    /// swift-log accepts one bootstrap per process, while the server can be
    /// started and stopped many times within it.
    static func once() {
        _ = bootstrapped
    }

    private static let bootstrapped: Void = {
        LoggingSystem.bootstrap { label in
            // stderr serves a launch from the terminal; the unified log serves a
            // launch from Finder, where stderr goes nowhere. Read it with:
            //   log stream --predicate 'subsystem == "apple-on-device-openai"'
            MultiplexLogHandler([
                StreamLogHandler.standardError(label: label),
                UnifiedLogHandler(label: label),
            ])
        }
    }()
}
