//
//  GradeNotificationService.swift
//  School Notes
//
//  Created by Luke Titi on 1/31/26.
//

import Foundation
#if os(iOS)
import UserNotifications
import BackgroundTasks
#endif

// MARK: - GradeNotificationService
class GradeNotificationService {
    static let shared = GradeNotificationService()
    private init() {}

    static let backgroundTaskIdentifier = "com.oakwood.gradeRefresh"
    private let storedGradesKey = "storedGrades"
    private let notifiedAssignmentsKey = "notifiedAssignments"

    #if os(iOS)
    // MARK: - Request Notification Permission
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Schedule Background Refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled")
        } catch {
            print("Could not schedule background refresh: \(error)")
        }
    }

    // MARK: - Handle Background Refresh
    func handleBackgroundRefresh(task: BGAppRefreshTask, appInfo: AppInfo) {
        scheduleBackgroundRefresh()

        let fetchTask = Task {
            await checkForNewGrades(appInfo: appInfo)
        }

        task.expirationHandler = {
            fetchTask.cancel()
        }

        Task {
            await fetchTask.value
            task.setTaskCompleted(success: true)
        }
    }
    #endif

    // MARK: - Check for New Grades (with AppInfo)
    func checkForNewGrades(appInfo: AppInfo) async {
        // Restore cookies for authentication
        await appInfo.restorePersistedCookiesIntoStores()
        await performGradeCheck()
    }

    // MARK: - Check for New Grades (Background - no AppInfo)
    func checkForNewGradesBackground() async {
        // Cookies should already be in HTTPCookieStorage from previous sessions
        await performGradeCheck()
    }

    // MARK: - Perform Grade Check
    private func performGradeCheck() async {
        // Check if notifications are enabled (default is true)
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.object(forKey: "gradeNotificationsEnabled") == nil ? true : defaults.bool(forKey: "gradeNotificationsEnabled")
        guard notificationsEnabled else {
            print("Grade notifications disabled")
            return
        }

        // Fetch current courses
        guard let courses = await fetchGrades() else {
            print("Failed to fetch grades in background")
            return
        }

        // Load set of already-notified assignment IDs
        var notifiedIDs = loadNotifiedAssignments()

        for course in courses {
            guard let enrollmentPk = course.enrollmentPk else { continue }

            if let assignments = await fetchAssignments(courseID: enrollmentPk) {
                for assignment in assignments {
                    // Only notify if: has a score, is unread, and we haven't notified yet
                    let hasScore = assignment.raw_score != nil && !assignment.raw_score!.isEmpty
                    let isUnread = assignment.is_unread == 1
                    let alreadyNotified = notifiedIDs.contains(assignment.score_id)

                    if hasScore && isUnread && !alreadyNotified {
                        let change = AssignmentGradeChange(
                            assignmentName: assignment.assignment_description,
                            score: assignment.raw_score!,
                            maxScore: assignment.maximum_score,
                            courseName: course.className,
                            courseGrade: course.grade
                        )
                        #if os(iOS)
                        await sendAssignmentNotification(for: change)
                        #endif

                        // Mark as notified
                        notifiedIDs.insert(assignment.score_id)
                    }
                }
            }
        }

        // Save updated notified IDs
        saveNotifiedAssignments(notifiedIDs)
    }

    // MARK: - Fetch Grades from Veracross
    private func fetchGrades() async -> [StoredCourse]? {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student/component/ClassListStudent/1308/load_data") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard status == 200 else { return nil }

            // Check if JSON response
            guard let firstChar = String(data: data.prefix(1), encoding: .utf8),
                  firstChar == "{" || firstChar == "[" else {
                return nil
            }

            let decoded = try JSONDecoder().decode(CoursesResponse.self, from: data)
            return decoded.courses.map { StoredCourse(from: $0) }
        } catch {
            print("Background fetch error: \(error)")
            return nil
        }
    }

    // MARK: - Fetch Assignments for a Course
    private func fetchAssignments(courseID: Int) async -> [Assignment]? {
        guard let url = URL(string: "https://portals-embed.veracross.com/oakwood/student/enrollment/\(courseID)/assignments") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard status == 200 else { return nil }

            guard let firstChar = String(data: data.prefix(1), encoding: .utf8),
                  firstChar == "{" || firstChar == "[" else {
                return nil
            }

            let decoded = try JSONDecoder().decode(AssignmentResponse.self, from: data)
            return decoded.assignments
        } catch {
            print("Failed to fetch assignments: \(error)")
            return nil
        }
    }

    #if os(iOS)
    // MARK: - Test Notification
    func sendTestNotification() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        if settings.authorizationStatus != .authorized {
            requestNotificationPermission()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Chapter 5 Test"
        content.body = "47/50 • Precalculus now at 92%"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)

        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }

    // MARK: - Local Notifications
    private func sendAssignmentNotification(for change: AssignmentGradeChange) async {
        let content = UNMutableNotificationContent()
        content.title = change.assignmentName

        var scoreText = change.score
        if let max = change.maxScore {
            scoreText = "\(change.score)/\(max)"
        }

        if let courseGrade = change.courseGrade {
            content.body = "\(scoreText) • \(change.courseName) now at \(courseGrade)%"
        } else {
            content.body = "\(scoreText) in \(change.courseName)"
        }

        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "grade-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
    #endif

    // MARK: - Grade Storage
    private func loadStoredGrades() -> [StoredCourse] {
        guard let data = UserDefaults.standard.data(forKey: storedGradesKey),
              let grades = try? JSONDecoder().decode([StoredCourse].self, from: data) else {
            return []
        }
        return grades
    }

    private func saveGrades(_ grades: [StoredCourse]) {
        if let data = try? JSONEncoder().encode(grades) {
            UserDefaults.standard.set(data, forKey: storedGradesKey)
        }
    }

    // MARK: - Notified Assignments Storage
    private func loadNotifiedAssignments() -> Set<Int> {
        let array = UserDefaults.standard.array(forKey: notifiedAssignmentsKey) as? [Int] ?? []
        return Set(array)
    }

    private func saveNotifiedAssignments(_ ids: Set<Int>) {
        UserDefaults.standard.set(Array(ids), forKey: notifiedAssignmentsKey)
    }
}

// MARK: - Storage Models
struct StoredCourse: Codable {
    let classId: String
    let className: String
    let grade: String?
    let enrollmentPk: Int?

    init(from course: Course) {
        self.classId = course.class_id
        self.className = course.class_name
        self.grade = course.ptd_grade
        self.enrollmentPk = course.enrollment_pk
    }
}

struct AssignmentGradeChange {
    let assignmentName: String
    let score: String
    let maxScore: Int?
    let courseName: String
    let courseGrade: String?
}
