import AppIntents

@available(iOS 27.0, macOS 27.0, *)
@AppEntity(schema: .reminders.list)
struct CourseEntity: IndexedEntity {

    static let defaultQuery = CourseQuery()
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Course",
        numericFormat: "\(placeholder: .int) Courses"
    )

    var id: String
    var name: String
    var type: CourseListType

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(course: Course) {
        self.id = course.class_id
        self.name = course.class_name
        self.type = .custom
    }
}

@available(iOS 27.0, macOS 27.0, *)
@AppEnum(schema: .reminders.listType)
enum CourseListType: String, AppEnum {
    case standard
    case custom
    static let caseDisplayRepresentations: [CourseListType: DisplayRepresentation] = [
        .standard: "Standard",
        .custom: "Custom"
    ]
}

@available(iOS 27.0, macOS 27.0, *)
extension CourseEntity {
    struct CourseQuery: EntityQuery {
        func entities(for identifiers: [String]) async throws -> [CourseEntity] {
            GradeStore.courses()
                .filter { identifiers.contains($0.class_id) }
                .map(CourseEntity.init)
        }

        func suggestedEntities() async throws -> [CourseEntity] {
            GradeStore.courses().map(CourseEntity.init)
        }
    }
}
