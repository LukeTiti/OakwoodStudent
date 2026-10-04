import AppIntents

/// Quick-logs a community service entry by voice/Shortcut — mirrors the in-app "Log Hours"
/// sheet (Community Service.swift), not a full form submission. Reflections and a supervisor's
/// name/email are part of the actual submitted form and aren't something Siri can reasonably
/// collect, so this only ever adds to "Logged Hours"; the student still finishes the real
/// submission in the app when they're ready.
@available(iOS 27.0, macOS 27.0, *)
struct LogServiceHoursIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Community Service Hours"
    static let description = IntentDescription("Quickly logs a community service entry to review and submit later in the app's Service tab.")

    @Parameter(title: "Hours")
    var hours: Double

    @Parameter(title: "Activity")
    var activity: String

    @Parameter(title: "Outside Community Service", default: false)
    var isOutsideService: Bool

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$hours) hours of \(\.$activity)")
    }

    func perform() async throws -> some IntentResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        ServiceStore.addServiceEntry(
            date: formatter.string(from: date ?? Date()),
            description: isOutsideService ? "Outside Community Service" : "Oakwood Service",
            notes: activity,
            hours: hours
        )
        return .result()
    }
}
