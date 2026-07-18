import Foundation

enum GradeStore {

    private static let defaults = UserDefaults(suiteName: appGroupID)

    static func courses() -> [Course] {
        guard let data = defaults?.data(forKey: "cachedCourses"),
              let decoded = try? JSONDecoder().decode([Course].self, from: data) else { return [] }
        return decoded
    }

    static func completionInfo() -> [Int: Bool] {
        guard let data = defaults?.data(forKey: "assignmentInfo"),
              let decoded = try? JSONDecoder().decode([Int: Bool].self, from: data) else { return [:] }
        return decoded
    }

    static func allPairs() -> [(assignment: Assignment, course: Course)] {
        courses().flatMap { course in (course.assignments ?? []).map { ($0, course) } }
    }
}
