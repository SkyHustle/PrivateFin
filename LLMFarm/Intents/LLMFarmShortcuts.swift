import SwiftUI
import AppIntents

struct LLMFarmShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LLMQueryIntent(),
            phrases: [
                "Ask ${applicationName}"
            ],
            shortTitle: "Create query to local LLM model",
            systemImageName: "brain.filled.head.profile"
        )
    }
}
