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
        let real = courses().flatMap { course in (course.assignments ?? []).map { ($0, course) } }
        let custom = customAssignments().map { assignment in
            (assignment, Course(class_id: "custom-\(assignment.score_id)", class_name: assignment.customCourseName ?? "Custom"))
        }
        return real + custom
    }

    // MARK: - Writes (Siri "mark completed" / "add assignment" actions)
    // Mirrors AppInfo's own persistence in Observable Class.swift exactly — same UserDefaults
    // suites and keys — so a change made here shows up in the main app the next time it reads
    // this state (on launch, or next load), and a change made in-app is what this already reads.

    static func customAssignments() -> [Assignment] {
        guard let data = UserDefaults.standard.data(forKey: "customAssignments"),
              let decoded = try? JSONDecoder().decode([Assignment].self, from: data) else { return [] }
        return decoded
    }

    static func setCompletion(scoreId: Int, completed: Bool) {
        var info = completionInfo()
        info[scoreId] = completed
        if let encoded = try? JSONEncoder().encode(info) {
            defaults?.set(encoded, forKey: "assignmentInfo")
        }
    }

    /// Mirrors AppInfo.addCustomAssignment(courseName:description:dueDate:type:notes:) field-for-field
    /// (including its due-date formatting rationale — see that function's comment in Observable
    /// Class.swift) since this runs outside any live AppInfo instance and has to reconstruct the
    /// same on-disk shape by hand. Returns the new assignment's score_id.
    @discardableResult
    static func addCustomAssignment(courseName: String, description: String, dueDate: Date, type: String, notes: String) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "MM/dd/yyyy"
        fullFormatter.locale = Locale(identifier: "en_US_POSIX")

        var assignments = customAssignments()
        var nextCustomId = (UserDefaults.standard.object(forKey: "nextCustomId") as? Int) ?? -1

        let assignment = Assignment(
            score_id: nextCustomId,
            assignment_type: type,
            assignment_description: description,
            assignment_notes: notes.isEmpty ? nil : notes,
            due_date: formatter.string(from: dueDate),
            _date: fullFormatter.string(from: dueDate),
            customCourseName: courseName
        )
        nextCustomId -= 1
        assignments.append(assignment)

        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: "customAssignments")
        }
        UserDefaults.standard.set(nextCustomId, forKey: "nextCustomId")
        setCompletion(scoreId: assignment.score_id, completed: false)

        return assignment.score_id
    }
}
