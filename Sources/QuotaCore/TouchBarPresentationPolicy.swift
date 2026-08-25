import Foundation

enum TouchBarPresentationPlan: Equatable {
    case modalWithControlStrip
    case modalWithPlacement
    case unavailable
}

enum TouchBarPresentationPolicy {
    static let placementSelector =
        "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"
    static let legacySelector =
        "presentSystemModalTouchBar:systemTrayItemIdentifier:"

    static func select(availableSelectors: Set<String>) -> TouchBarPresentationPlan {
        if availableSelectors.contains(legacySelector) {
            return .modalWithControlStrip
        }
        if availableSelectors.contains(placementSelector) {
            return .modalWithPlacement
        }
        return .unavailable
    }
}

enum TouchBarPresentationModePolicy {
    static let desiredMode = "appWithControlStrip"

    static func originalModeToStore(currentMode: String,
                                    storedOriginalMode: String?) -> String? {
        if let storedOriginalMode { return storedOriginalMode }
        return currentMode == desiredMode ? nil : currentMode
    }

    static func presentationDelays(modeChanged: Bool) -> [TimeInterval] {
        modeChanged ? [1.5, 3.5, 7.0] : [0.5, 3.0]
    }
}
