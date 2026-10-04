import AppIntents
import CoreLocation
import Foundation
import MapKit

@available(iOS 27.0, macOS 27.0, *)
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
    @Property(title: "Due Date") var dueDate: DateComponents?
    var note: String?
    @Property(title: "Flagged") var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var urls: [URL]
    var tags: Set<String>

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(list.name)",
            image: .init(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
        )
    }

    init(assignment: Assignment, course: Course, isCompleted: Bool) {
        self.id = assignment.score_id
        self.title = assignment.assignment_description
        self.isCompleted = isCompleted
        self.list = CourseEntity(course: course)
        self.dueDate = assignment.dueDate.map { due -> DateComponents in
            var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
            let classTime = GradeStore.classTime(forCourseName: course.class_name, on: due)
            components.hour = classTime.hour
            components.minute = classTime.minute
            return components
        }
        self.note = assignment.assignment_notes
        self.isFlagged = false
        self.creationDate = nil
        self.completionDate = nil
        self.urls = [URL(string: "oakwood://assignment/\(assignment.score_id)")!]
        self.tags = Set([assignment.assignment_type].compactMap { $0 })
    }
}

@available(iOS 27.0, macOS 27.0, *)
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

@available(iOS 27.0, macOS 27.0, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
enum LocationTriggerEventType: String, AppEnum {
    case arrive
    case depart
    static let caseDisplayRepresentations: [LocationTriggerEventType: DisplayRepresentation] = [
        .arrive: "Arrive",
        .depart: "Depart"
    ]
}

@available(iOS 27.0, macOS 27.0, *)
extension AssignmentEntity {
    struct AssignmentQuery: EntityPropertyQuery {
        typealias ComparatorMappingType = (AssignmentEntity) -> Bool

        // NOTE: dueDate can't get LessThan/GreaterThan-style comparators registered here —
        // those require the property's type to conform to Comparable, and DateComponents
        // (required by the .reminders.reminder schema, to allow an all-day due date with no
        // time) doesn't conform to it. @Property below still exposes it for Siri's own
        // schema-level reasoning and for SortableBy; the "only 1/3 shown" undercounting is
        // addressed instead by removing suggestedEntities()'s hardcoded prefix(20) cap, since
        // that capped, unfiltered list is what Siri actually reasons over for date-range
        // questions without a real comparator to push the filtering down into our query.
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
            SortableBy(\AssignmentEntity.$dueDate)
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
            // No cap here (used to be prefix(20)) — this is the full candidate list Siri
            // reasons over for date-range questions like "due this week", since dueDate can't
            // have a real comparator registered (see the comment on `properties` above). A
            // student realistically won't have hundreds of incomplete upcoming assignments, so
            // returning everything is safe and avoids silently truncating the real answer.
            return GradeStore.allPairs()
                .filter {
                    !completionState(for: $0.assignment, info: info) &&
                    ($0.assignment.dueDate ?? .distantPast) >= now
                }
                .sorted { ($0.assignment.dueDate ?? .distantFuture) < ($1.assignment.dueDate ?? .distantFuture) }
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
