import AppIntents

/// Marks an existing assignment completed (or not) — Siri resolves *which* assignment via
/// AssignmentEntity's own defaultQuery, the same lookup already backing "show my assignments".
/// Writes straight to the shared assignmentInfo store GradeStore/AppInfo both read, so the
/// change is visible in-app the next time it loads (no separate sync step needed here).
@available(iOS 27.0, macOS 27.0, *)
struct MarkAssignmentCompletedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Assignment Completed"
    static let description = IntentDescription("Marks an assignment as completed or not completed.")

    @Parameter(title: "Assignment")
    var assignment: AssignmentEntity

    @Parameter(title: "Completed", default: true)
    var completed: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$assignment) as \(\.$completed)")
    }

    func perform() async throws -> some IntentResult {
        GradeStore.setCompletion(scoreId: assignment.id, completed: completed)
        return .result()
    }
}

/// Adds a new custom assignment — mirrors the in-app "Add Custom Assignment" flow
/// (AppInfo.addCustomAssignment in Observable Class.swift) via GradeStore.addCustomAssignment,
/// so it shows up in the To Do list next time the app opens, same as one typed in by hand.
@available(iOS 27.0, macOS 27.0, *)
struct AddAssignmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Assignment"
    static let description = IntentDescription("Adds a new assignment with a title, course, and due date.")

    @Parameter(title: "Title")
    var assignmentTitle: String

    @Parameter(title: "Course")
    var courseName: String

    @Parameter(title: "Due Date")
    var dueDate: Date

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$assignmentTitle) for \(\.$courseName) due \(\.$dueDate)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<AssignmentEntity> {
        let scoreId = GradeStore.addCustomAssignment(
            courseName: courseName, description: assignmentTitle, dueDate: dueDate,
            type: "Custom", notes: notes ?? ""
        )
        guard let pair = GradeStore.allPairs().first(where: { $0.assignment.score_id == scoreId }) else {
            throw AddAssignmentError.saveFailed
        }
        let entity = AssignmentEntity(assignment: pair.assignment, course: pair.course, isCompleted: false)
        return .result(value: entity)
    }

    enum AddAssignmentError: Error, CustomLocalizedStringResourceConvertible {
        case saveFailed
        var localizedStringResource: LocalizedStringResource { "Couldn't save that assignment." }
    }
}
