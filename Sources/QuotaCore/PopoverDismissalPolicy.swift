import Foundation

enum PopoverDismissalPolicy {
    static func shouldClose(isGlobalEvent: Bool,
                            isPopoverWindow: Bool,
                            isStatusItemWindow: Bool) -> Bool {
        isGlobalEvent || (!isPopoverWindow && !isStatusItemWindow)
    }
}
