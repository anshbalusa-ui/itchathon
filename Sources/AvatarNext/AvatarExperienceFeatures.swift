import Foundation

enum AvatarExperienceFeatures {
    static var internalPilotEnabled: Bool {
        internalPilotEnabled(arguments: ProcessInfo.processInfo.arguments)
    }

    static func internalPilotEnabled(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains("-fitcheck-avatar-internal")
        #else
        false
        #endif
    }
}
