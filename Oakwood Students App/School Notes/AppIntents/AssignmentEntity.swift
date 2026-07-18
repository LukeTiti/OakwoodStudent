import AppIntents
import CoreLocation
import Foundation
import MapKit

@AppEntity(schema: .reminders.reminder)
struct AssignmentEntity: IndexedEntity {
    @DeferredProperty
    var locationTrigger: LocationTriggerEntity? { get async { nil } }
    @DeferredProperty
    var recurrence: Calendar.RecurrenceRule? { get async { nil } }
    static let defaultQuery = AssignmentQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Assignment",
        numericFormat: "\(placeholder: .int) Assignments"
    )

    var id: Int
    @Property(title: "Title") var title: String
    @Property(title: "Completed") var isCompleted: Bool
    var list: CourseEntity
    var dueDate: DateComponents?
    var note: String?
    @Property(title: "Flagged") var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var urls: [URL]
    var tags: Set<String>

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
        self.isFlagged = false
        self.creationDate = nil
        self.completionDate = nil
        self.urls = [URL(string: "oakwood://assignment/\(assignment.score_id)")!]
        self.tags = Set([assignment.assignment_type].compactMap { $0 })
        print(self.dueDate)
    }
}

@AppEntity(schema: .reminders.locationTrigger)
struct LocationTriggerEntity: AppEntity {
    static let defaultQuery = LocationTriggerQuery()
    var id: String
    var event: LocationTriggerEventType

    @DeferredProperty
    var place: CLPlacemark { get async { MKPlacemark(coordinate: .init(latitude: 0, longitude: 0)) } }

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
    struct AssignmentQuery: EntityPropertyQuery {
        typealias ComparatorMappingType = (AssignmentEntity) -> Bool

        static var properties = EntityQueryProperties<AssignmentEntity, (AssignmentEntity) -> Bool> {
            Property(\AssignmentEntity.$isCompleted) {
                EqualToComparator { v in { $0.isCompleted == v } }
            }
            Property(\AssignmentEntity.$isFlagged) {
                EqualToComparator { v in { $0.isFlagged == v } }
            }
        }

        static var sortingOptions = SortingOptions {
            SortableBy(\AssignmentEntity.$title)
        }

        func entities(for identifiers: [Int]) async throws -> [AssignmentEntity] {
            let info = GradeStore.completionInfo()
            return GradeStore.allPairs()
                .filter { identifiers.contains($0.assignment.score_id) }
                .map { pair in
                    AssignmentEntity(assignment: pair.assignment, course: pair.course,
                                     isCompleted: completionState(for: pair.assignment, info: info))
                }
        }

        func suggestedEntities() async throws -> [AssignmentEntity] {
            let info = GradeStore.completionInfo()
            let now = Date()
            return GradeStore.allPairs()
                .filter {
                    !completionState(for: $0.assignment, info: info) &&
                    ($0.assignment.dueDate ?? .distantPast) >= now
                }
                .sorted { ($0.assignment.dueDate ?? .distantFuture) < ($1.assignment.dueDate ?? .distantFuture) }
                .prefix(20)
                .map { AssignmentEntity(assignment: $0.assignment, course: $0.course, isCompleted: false) }
        }

        func entities(matching comparators: [(AssignmentEntity) -> Bool], mode: EntityQueryComparatorMode, sortedBy: [EntityQuerySort<AssignmentEntity>], limit: Int?) async throws -> [AssignmentEntity] {
            let info = GradeStore.completionInfo()
            var results = GradeStore.allPairs().map { pair in
                AssignmentEntity(assignment: pair.assignment, course: pair.course,
                                 isCompleted: completionState(for: pair.assignment, info: info))
            }
            for f in comparators { results = results.filter(f) }
            if let limit { results = Array(results.prefix(limit)) }
            return results
        }
    }
}

private func completionState(for assignment: Assignment, info: [Int: Bool]) -> Bool {
    if let explicit = info[assignment.score_id] { return explicit }
    let hasGrade = assignment.raw_score.map { !$0.isEmpty } ?? false
    let turnedIn = assignment.completion_status?.hasPrefix("Turned In") ?? false
    return hasGrade || turnedIn
}
