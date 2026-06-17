import Foundation

enum GradeStore {

    @MainActor
    static func courses() -> [Course] {
        guard let data = UserDefaults.standard.data(forKey: "cachedCourses"),
              let decoded = try? JSONDecoder().decode([Course].self, from: data) else { return [] }
        return decoded
    }

    @MainActor
    static func completionInfo() -> [Int: Bool] {
        guard let data = UserDefaults.standard.data(forKey: "assignmentInfo"),
              let decoded = try? JSONDecoder().decode([Int: Bool].self, from: data) else { return [:] }
        return decoded
    }

    @MainActor
    static func allPairs() -> [(assignment: Assignment, course: Course)] {
        courses().flatMap { course in
            (course.assignments ?? []).map { ($0, course) }
        }
    }
}
