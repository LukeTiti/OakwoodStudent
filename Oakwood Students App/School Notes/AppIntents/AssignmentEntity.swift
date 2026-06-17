import AppIntents
import CoreLocation
import Foundation

@AppEntity(schema: .reminders.reminder)
struct AssignmentEntity: IndexedEntity {

    static let defaultQuery = AssignmentQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Assignment",
        numericFormat: "\(placeholder: .int) Assignments"
    )

    var id: Int
    var title: String
    var isCompleted: Bool
    var list: CourseEntity
    var dueDate: DateComponents?
    var note: String?
    var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var recurrence: Calendar.RecurrenceRule?
    var urls: [URL]
    var tags: Set<String>
    var locationTrigger: LocationTriggerEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(list.name)"
        )
    }

    init(assignment: Assignment, course: Course, isCompleted: Bool) {
        self.id = assignment.score_id
        self.title = assignment.assignment_description
        self.isCompleted = isCompleted
        self.list = CourseEntity(course: course)
        self.dueDate = assignment.dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day], from: $0)
        }
        self.note = assignment.assignment_notes
        self.isFlagged = nil
        self.creationDate = nil
        self.completionDate = nil
        self.recurrence = nil
        self.urls = []
        self.tags = []
        self.locationTrigger = nil
    }
}

@AppEntity(schema: .reminders.locationTrigger)
struct LocationTriggerEntity: AppEntity {
    static let defaultQuery = LocationTriggerQuery()
    var id: String
    var event: LocationTriggerEventType
    var place: CLPlacemark

    var displayRepresentation: DisplayRepresentation { .init(title: "\(id)") }

    struct LocationTriggerQuery: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [LocationTriggerEntity] { [] }
    }
}

@AppEnum(schema: .reminders.locationTriggerEvent)
enum LocationTriggerEventType: String, AppEnum {
    case arrive
    case depart
    static let caseDisplayRepresentations: [LocationTriggerEventType: DisplayRepresentation] = [
        .arrive: "Arrive",
        .depart: "Depart"
    ]
}

extension AssignmentEntity {
    struct AssignmentQuery: EntityQuery {

        func entities(for identifiers: [Int]) async throws -> [AssignmentEntity] {
            let info = await GradeStore.completionInfo()
            return await GradeStore.allPairs()
                .filter { identifiers.contains($0.assignment.score_id) }
                .map { pair in
                    AssignmentEntity(assignment: pair.assignment, course: pair.course,
                                     isCompleted: completionState(for: pair.assignment, info: info))
                }
        }

        func suggestedEntities() async throws -> [AssignmentEntity] {
            let info = await GradeStore.completionInfo()
            let now = Date()
            return await GradeStore.allPairs()
                .filter {
                    !completionState(for: $0.assignment, info: info) &&
                    ($0.assignment.dueDate ?? .distantPast) >= now
                }
                .sorted { ($0.assignment.dueDate ?? .distantFuture) < ($1.assignment.dueDate ?? .distantFuture) }
                .prefix(20)
                .map { AssignmentEntity(assignment: $0.assignment, course: $0.course, isCompleted: false) }
        }
    }
}

private func completionState(for assignment: Assignment, info: [Int: Bool]) -> Bool {
    if let explicit = info[assignment.score_id] { return explicit }
    let hasGrade = assignment.raw_score.map { !$0.isEmpty } ?? false
    let turnedIn = assignment.completion_status?.hasPrefix("Turned In") ?? false
    return hasGrade || turnedIn
}
