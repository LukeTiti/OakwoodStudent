import AppIntents

/// Without this, Siri has no built-in trigger phrase for these intents — they only show up if
/// the student manually finds them in the Shortcuts app first. Registering phrases here is what
/// lets "Hey Siri, log service hours in Oakwood Students" actually reach LogServiceHoursIntent
/// instead of falling through to Siri's generic Notes/Reminders handling.
@available(iOS 27.0, macOS 27.0, *)
struct OakwoodAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogServiceHoursIntent(),
            phrases: [
                "Log service hours in \(.applicationName)",
                "Log community service hours in \(.applicationName)",
                "Log community service in \(.applicationName)"
            ],
            shortTitle: "Log Service Hours",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: MarkAssignmentCompletedIntent(),
            phrases: [
                "Mark an assignment complete in \(.applicationName)",
                "Mark an assignment done in \(.applicationName)"
            ],
            shortTitle: "Mark Assignment Complete",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: AddAssignmentIntent(),
            phrases: [
                "Add an assignment in \(.applicationName)"
            ],
            shortTitle: "Add Assignment",
            systemImageName: "plus.circle"
        )
    }
}
