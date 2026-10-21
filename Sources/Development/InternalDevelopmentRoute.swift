import Foundation

/// Internal entry selection only. Conflicting routes fail closed to the legacy app.
enum InternalDevelopmentRoute: Equatable {
    case legacy
    case avatar
    case catalog
    case integrated

    static var current: Self { resolve(arguments: ProcessInfo.processInfo.arguments) }

    static func resolve(arguments: [String]) -> Self {
        #if DEBUG
        var selected = Self.legacy
        for argument in arguments {
            let candidate: Self
            switch argument {
            case "-fitcheck-avatar-internal": candidate = .avatar
            case "-fitcheck-catalog-internal": candidate = .catalog
            case "-fitcheck-integrated-internal": candidate = .integrated
            default: continue
            }
            guard selected == .legacy || selected == candidate else { return .legacy }
            selected = candidate
        }
        return selected
        #else
        return .legacy
        #endif
    }
}
