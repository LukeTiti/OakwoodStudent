import AppIntents

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

@AppEnum(schema: .reminders.listType)
enum CourseListType: String, AppEnum {
    case standard
    case custom
    static let caseDisplayRepresentations: [CourseListType: DisplayRepresentation] = [
        .standard: "Standard",
        .custom: "Custom"
    ]
}

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
