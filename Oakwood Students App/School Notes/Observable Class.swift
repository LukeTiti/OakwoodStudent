//
//  Observable Class.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//
import SwiftUI
import Combine
import GoogleSignIn
import WebKit
import SwiftSoup
import WidgetKit

struct GoogleLoginSnapshot: Codable {
    var isSignedIn: Bool
    var userName: String
    var userEmail: String
}

class AppInfo: ObservableObject {
    @Published var fetchedString: [String] = []
    @Published var fetchedScoopString: [String] = []
    @Published var assignmentString: String = ""
    @Published var isSignedIn: Bool = false
    @Published var userName: String = ""
    @Published var password: String = ""
    @Published var googleVM = GoogleSignInViewModel()
    @Published var approvedEmails: [String] = []
    @Published var reloadID = UUID()
    @Published var signInSheet = false
    @Published var classes: [ClassS] = []
    @Published var courses: [Course] = [] {
        didSet { saveCourses() }
    }
    @Published var fetchedGrades: [String] = []
    @Published var resourceAssignmentIds: Set<Int> = []
    @Published var personPK: Int? = nil
    @Published var personalCalendarURL: String? = nil {
        didSet {
            if let url = personalCalendarURL {
                UserDefaults.standard.set(url, forKey: "personalCalendarURL")
            }
        }
    }
    @Published var practiceCalendarURLs: [String] = [] {
        didSet {
            UserDefaults.standard.set(practiceCalendarURLs, forKey: "practiceCalendarURLs")
        }
    }

    // MARK: - Calendar State
    @Published var calendarItems: [CalendarItem] = []
    @Published var calendarScores: [String: GameScore] = [:]
    @Published var calendarMySignups: [String: [ScoreboardSignup]] = [:]
    @Published var calendarIsLoading = false
    @Published var customAssignments: [Assignment] = [] {
        didSet { saveCustomAssignments() }
    }
    private var nextCustomId: Int = -1
    @Published var info: [Int: Bool] = [:] {
        didSet {    
            saveAssignmentInfo()
        }
    }

    // MARK: Cookie persistence
    // Store cookies as property dictionaries (HTTPCookie.propertyKeys) and a timestamp
    @Published var persistedCookies: [[HTTPCookiePropertyKey: Any]] = [] {
        didSet { saveCookies() }
    }
    @Published var cookiesLastSaved: Date? {
        didSet { saveCookies() }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadCachedCourses()
        loadAssignmentInfo()
        loadCustomAssignments()
        loadCookies()
        loadGoogleLogin()
        personalCalendarURL = UserDefaults.standard.string(forKey: "personalCalendarURL")
        practiceCalendarURLs = UserDefaults.standard.stringArray(forKey: "practiceCalendarURLs") ?? []

        // If already signed in from a previous session, save FCM token now
        #if os(iOS)
        if googleVM.isSignedIn && !googleVM.userEmail.isEmpty {
            PushNotificationManager.shared.refreshTokenForCurrentUser()
        }
        #endif

        // Observe googleVM published properties and persist snapshot when they change
        googleVM.$isSignedIn
            .combineLatest(googleVM.$userName, googleVM.$userEmail)
            .sink { [weak self] isSignedIn, name, email in
                self?.saveGoogleLogin(snapshot: GoogleLoginSnapshot(isSignedIn: isSignedIn, userName: name, userEmail: email))
                // Save FCM token to Firestore now that we have the user's email
                if isSignedIn && !email.isEmpty {
                    #if os(iOS)
                    PushNotificationManager.shared.refreshTokenForCurrentUser()
                    #endif
                }
            }
            .store(in: &cancellables)
    }

    private func saveCourses() {
        if let data = try? JSONEncoder().encode(courses) {
            UserDefaults.standard.set(data, forKey: "cachedCourses")
        }
    }

    private func loadCachedCourses() {
        if let data = UserDefaults.standard.data(forKey: "cachedCourses"),
           let decoded = try? JSONDecoder().decode([Course].self, from: data) {
            courses = decoded
        }
    }

    private func saveAssignmentInfo() {
        if let encoded = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(encoded, forKey: "assignmentInfo")
        }
    }

    private func loadAssignmentInfo() {
        if let data = UserDefaults.standard.data(forKey: "assignmentInfo"),
           let decoded = try? JSONDecoder().decode([Int: Bool].self, from: data) {
            info = decoded
        }
    }

    // MARK: - Custom Assignments

    private func saveCustomAssignments() {
        if let data = try? JSONEncoder().encode(customAssignments) {
            UserDefaults.standard.set(data, forKey: "customAssignments")
        }
        UserDefaults.standard.set(nextCustomId, forKey: "nextCustomId")
    }

    private func loadCustomAssignments() {
        if let data = UserDefaults.standard.data(forKey: "customAssignments"),
           let decoded = try? JSONDecoder().decode([Assignment].self, from: data) {
            customAssignments = decoded
        }
        nextCustomId = UserDefaults.standard.object(forKey: "nextCustomId") as? Int ?? -1
    }

    func addCustomAssignment(courseName: String, description: String, dueDate: Date, type: String, notes: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let assignment = Assignment(
            score_id: nextCustomId,
            assignment_type: type,
            assignment_description: description,
            assignment_notes: notes.isEmpty ? nil : notes,
            due_date: formatter.string(from: dueDate),
            customCourseName: courseName
        )
        nextCustomId -= 1
        customAssignments.append(assignment)
        info[assignment.score_id] = false
    }

    func deleteCustomAssignment(scoreId: Int) {
        customAssignments.removeAll { $0.score_id == scoreId }
        info.removeValue(forKey: scoreId)
    }

    func markPastAssignmentsCompleted() {
        let now = Date()
        for course in courses {
            for assignment in course.assignments ?? [] {
                if let due = assignment.dueDate, due < now {
                    info[assignment.score_id] = true
                }
            }
        }
    }

    // MARK: - Google VM persistence
    private func saveGoogleLogin(snapshot: GoogleLoginSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: "googleLoginSnapshot")
        }
    }

    private func loadGoogleLogin() {
        guard let data = UserDefaults.standard.data(forKey: "googleLoginSnapshot"),
              let snap = try? JSONDecoder().decode(GoogleLoginSnapshot.self, from: data) else {
            return
        }
        // Restore into the live VM on the main thread
        DispatchQueue.main.async {
            self.googleVM.isSignedIn = snap.isSignedIn
            self.googleVM.userName = snap.userName
            self.googleVM.userEmail = snap.userEmail
        }
    }

    // Optional helper
    func toggleInfo(for id: Int) {
        info[id] = !(info[id] ?? false)
    }

    // MARK: - Cookies: Save/Load
    private func saveCookies() {
        // Convert [[HTTPCookiePropertyKey: Any]] to [[String: Any]] for UserDefaults
        let dicts: [[String: Any]] = persistedCookies.map { dict in
            var out: [String: Any] = [:]
            for (k, v) in dict {
                out[k.rawValue] = v
            }
            return out
        }
        UserDefaults.standard.set(dicts, forKey: "persistedCookies")
        if let last = cookiesLastSaved {
            UserDefaults.standard.set(last.timeIntervalSince1970, forKey: "cookiesLastSaved")
        } else {
            UserDefaults.standard.removeObject(forKey: "cookiesLastSaved")
        }
    }

    private func loadCookies() {
        guard let raw = UserDefaults.standard.array(forKey: "persistedCookies") as? [[String: Any]] else {
            persistedCookies = []
            cookiesLastSaved = nil
            return
        }
        let rebuilt: [[HTTPCookiePropertyKey: Any]] = raw.map { dict in
            var out: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in dict {
                out[HTTPCookiePropertyKey(k)] = v
            }
            return out
        }
        persistedCookies = rebuilt
        if let ts = UserDefaults.standard.value(forKey: "cookiesLastSaved") as? TimeInterval {
            cookiesLastSaved = Date(timeIntervalSince1970: ts)
        } else {
            cookiesLastSaved = nil
        }
    }

    // MARK: - Shared Veracross Helpers

    /// Fetches the Veracross portal HTML and extracts the person PK from the Sentry user config.
    func fetchPersonPK() async {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return }
        let pattern = #"id:\s*"(\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let pk = Int(html[range]) else { return }
        await MainActor.run { self.personPK = pk }
    }

    /// Fetches the Veracross calendar subscription page and stores the "All classes" iCal URL.
    func fetchPersonalCalendarURL() async {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student/calendar/subscribe/mine") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            print("[PersonalCal] Network request failed")
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[PersonalCal] Subscribe page status: \(status)")
        guard status == 200,
              let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html) else { return }

        // "All Classes" is a label in a sibling cell — walk up from it to find the webcal link in the same row
        let allElements = (try? doc.getAllElements().array()) ?? []
        for element in allElements {
            let ownText = (try? element.ownText()) ?? ""
            guard ownText.localizedCaseInsensitiveContains("all classes") else { continue }
            var container = element.parent()
            while let c = container {
                if let link = try? c.select("a[href^='webcal://api.veracross.com/oakwood/subscribe/']").first(),
                   var href = try? link.attr("href"), !href.isEmpty {
                    if href.hasPrefix("webcal://") {
                        href = "https://" + href.dropFirst("webcal://".count)
                    }
                    print("[PersonalCal] Found All Classes feed: \(href)")
                    await MainActor.run { self.personalCalendarURL = href }
                    return
                }
                container = c.parent()
            }
        }
        print("[PersonalCal] No 'All Classes' feed found")
    }

    /// Fetches the course list from Veracross and populates `self.courses`.
    /// Returns an error string on failure, or nil on success.
    func loadCourses() async -> String? {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student/component/ClassListStudent/1308/load_data") else {
            return "Invalid URL"
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard status == 200 else {
                return "Server returned status \(status)"
            }

            guard isJSONResponse(response, data: data) else {
                return "Not authenticated. Please log in."
            }

            do {
                let decoded = try JSONDecoder().decode(CoursesResponse.self, from: data)
                await MainActor.run {
                    self.courses = decoded.courses
                }
                await fetchPersonPK()
                if personalCalendarURL == nil { await fetchPersonalCalendarURL() }
                return nil
            } catch {
                let textPreview = String(data: data, encoding: .utf8) ?? "Unable to decode"
                return "Decoding error: \(error.localizedDescription)\nPreview: \(textPreview.prefix(200))"
            }
        } catch {
            return "Network error: \(error.localizedDescription)"
        }
    }

    /// Single shared implementation of JSON response detection (was triplicated).
    func isJSONResponse(_ response: URLResponse?, data: Data) -> Bool {
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("application/json") {
            return true
        }
        if let prefix = String(data: data.prefix(1), encoding: .utf8) {
            return prefix == "{" || prefix == "["
        }
        return false
    }

    /// Fetches assignments for a single course and stores them in `self.courses`.
    /// Returns an error string on failure, or nil on success.
    func loadAssignments(courseID: Int) async -> String? {
        guard let url = URL(string: "https://portals-embed.veracross.com/oakwood/student/enrollment/\(courseID)/assignments") else {
            return "Invalid URL"
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard status == 200 else {
                return "Server returned status \(status)"
            }

            guard isJSONResponse(response, data: data) else {
                return "Not authenticated. Please log in."
            }

            do {
                let decoded = try JSONDecoder().decode(AssignmentResponse.self, from: data)
                let attachmentsByID = Dictionary(grouping: decoded.attachments ?? []) { $0.assignment_id }
                var assignmentsWithAttachments = decoded.assignments
                for i in assignmentsWithAttachments.indices {
                    if let id = assignmentsWithAttachments[i].assignment_id {
                        assignmentsWithAttachments[i].attachments = attachmentsByID[id]
                    }
                }
                await MainActor.run {
                    if let idx = self.courses.firstIndex(where: { $0.enrollment_pk == courseID }) {
                        self.courses[idx].assignments = assignmentsWithAttachments
                    }
                }
                return nil
            } catch {
                let textPreview = String(data: data, encoding: .utf8) ?? "Unable to decode"
                return "Decoding error: \(error.localizedDescription)\nPreview: \(textPreview.prefix(200))"
            }
        } catch {
            return "Network error: \(error.localizedDescription)"
        }
    }

    /// Initializes completion status for assignments in a given course.
    /// Marks assignments with a raw_score as complete, and "Not Turned In" as incomplete.
    func initializeCompletionStatus(forCourseID courseID: Int) {
        guard let assignments = courses.first(where: { $0.enrollment_pk == courseID })?.assignments else { return }
        for assignment in assignments {
            if let raw = assignment.raw_score, !raw.isEmpty {
                info[assignment.score_id] = true
            } else if let status = assignment.completion_status, status.hasPrefix("Turned In") {
                info[assignment.score_id] = true
            } else if assignment.completion_status == "Not Turned In",
                      info[assignment.score_id] == nil {
                info[assignment.score_id] = false
            }
        }
        info = info // force SwiftUI to notice
    }

    /// Loads assignments for all courses, then initializes completion status.
    /// Returns a combined error string or nil on full success.
    func loadAllAssignments() async -> String? {
        var errors: [String] = []
        let courseIDs = courses.compactMap { $0.enrollment_pk }
        for courseID in courseIDs {
            if let err = await loadAssignments(courseID: courseID) {
                errors.append(err)
            } else {
                await MainActor.run {
                    initializeCompletionStatus(forCourseID: courseID)
                }
            }
        }
        await MainActor.run { saveAssignmentsForWidget() }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func saveAssignmentsForWidget() {
        let today = Calendar.current.startOfDay(for: Date())
        let cutoff = Calendar.current.date(byAdding: .day, value: 14, to: today)!

        let veracross = courses.flatMap { course in
            (course.assignments ?? []).map { (assignment: $0, courseName: course.class_name) }
        }
        let custom = customAssignments.map { (assignment: $0, courseName: $0.customCourseName ?? "Custom") }

        let events: [WidgetCalendarEvent] = (veracross + custom)
            .filter { info[$0.assignment.score_id, default: false] == false }
            .compactMap { pair in
                guard let due = pair.assignment.dueDate, due >= today, due <= cutoff else { return nil }
                return WidgetCalendarEvent(
                    id: "todo-\(pair.assignment.score_id)",
                    title: pair.assignment.assignment_description,
                    date: due,
                    timeText: "",
                    badgeLabel: pair.courseName,
                    colorName: widgetColorName(for: pair.assignment.assignment_type ?? ""),
                    location: ""
                )
            }
            .sorted { $0.date < $1.date }

        if let data = try? JSONEncoder().encode(Array(events.prefix(20))) {
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: widgetAssignmentsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func widgetColorName(for assignmentType: String) -> String {
        switch assignmentType.lowercased() {
        case "test", "exam": return "red"
        case "quiz":         return "orange"
        case "homework":     return "green"
        default:             return "purple"
        }
    }

    // MARK: - Mark Assignment as Read

    /// Fetches a Veracross HTML page and extracts the CSRF token from the meta tag.
    func fetchCSRFToken() async -> String? {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let doc = try SwiftSoup.parse(html)
            return try doc.select("meta[name=csrf-token]").first()?.attr("content")
        } catch {
            return nil
        }
    }

    /// Posts to Veracross to mark an assignment as read, then updates local state.
    func markAssignmentAsRead(scoreID: Int) async -> String? {
        guard let token = await fetchCSRFToken() else {
            return "Could not fetch CSRF token"
        }

        guard let url = URL(string: "https://portals-embed.veracross.com/oakwood/enrollment/mark_notification_read") else {
            return "Invalid URL"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
        request.httpBody = "class_assignment_person_pk=\(scoreID)".data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else {
                return "Mark as read failed with status \(status)"
            }

            await MainActor.run {
                for i in courses.indices {
                    if let assignments = courses[i].assignments {
                        for j in assignments.indices {
                            if courses[i].assignments![j].score_id == scoreID {
                                courses[i].assignments![j].is_unread = 0
                            }
                        }
                    }
                }
            }
            return nil
        } catch {
            return "Network error: \(error.localizedDescription)"
        }
    }

    // MARK: - Preload

    func preloadAll() {
        Task {
            await restorePersistedCookiesIntoStores()
            async let grades: () = preloadGrades()
            async let calendar: () = loadAllCalendarEvents()
            async let images: () = preloadScoopImages()
            await grades; await calendar; await images
        }
    }

    func preloadGrades() async {
        guard !persistedCookies.isEmpty, courses.isEmpty else { return }
        await syncCookies()
        _ = await loadCourses()
        _ = await loadAllAssignments()
    }

    // MARK: - Calendar Loading

    func loadAllCalendarEvents() async {
        guard !calendarIsLoading else { return }
        let isFirstLoad = await MainActor.run { calendarItems.isEmpty }
        if isFirstLoad { await MainActor.run { calendarIsLoading = true } }

        await fetchPersonalCalendarURL()
        async let sportsTask = loadCalendarSportsEvents()
        async let schoolTask = loadCalendarSchoolEvents()
        async let personalTask = loadPersonalCalendarEvents()
        async let practiceTask = loadPracticeCalendarEvents()
        let (sports, school, personal, practice) = await (sportsTask, schoolTask, personalTask, practiceTask)

        let combined: [CalendarItem] = sports.map { .sports($0) } + school.map { .school($0) } + personal.map { .personal($0) } + practice.map { .practice($0) }
        var seen = Set<String>()
        let unique = combined.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
        let fetchedScores = (try? await FirebaseService.shared.fetchAllGameScores()) ?? [:]
        await loadCalendarMySignups()

        await MainActor.run {
            calendarItems = unique
            calendarScores = fetchedScores
            calendarIsLoading = false
        }

        saveEventsForWidget(unique)
    }

    private func saveEventsForWidget(_ items: [CalendarItem]) {
        let today = Calendar.current.startOfDay(for: Date())
        let upcoming = items
            .filter { $0.date >= today }
            .prefix(20)
            .map { item -> WidgetCalendarEvent in
                switch item {
                case .sports(let e):
                    return WidgetCalendarEvent(id: e.id, title: e.opponent.isEmpty ? e.title : e.opponent,
                        date: e.date, timeText: e.timeText, badgeLabel: e.sportName,
                        colorName: "blue", location: e.location)
                case .school(let e):
                    return WidgetCalendarEvent(id: "school-\(e.id)", title: e.title,
                        date: e.date, timeText: e.timeText, badgeLabel: "School Event",
                        colorName: "teal", location: e.location)
                case .personal(let e):
                    return WidgetCalendarEvent(id: "personal-\(e.id)", title: e.title,
                        date: e.date, timeText: e.timeText, badgeLabel: "My Schedule",
                        colorName: "indigo", location: e.location)
                case .practice(let e):
                    return WidgetCalendarEvent(id: "practice-\(e.id)", title: e.title,
                        date: e.date, timeText: e.timeText, badgeLabel: "Practice",
                        colorName: "orange", location: e.location)
                }
            }
        if let data = try? JSONEncoder().encode(Array(upcoming)) {
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: widgetEventsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshCalendarData() async {
        async let scoresTask = FirebaseService.shared.fetchAllGameScores()
        async let practiceTask = loadPracticeCalendarEvents()
        await loadCalendarMySignups()
        let scores = (try? await scoresTask) ?? [:]
        let practice = await practiceTask
        await MainActor.run {
            calendarScores = scores
            // Merge practice events without touching existing items
            let practiceItems = practice.map { CalendarItem.practice($0) }
            let nonPractice = calendarItems.filter { if case .practice = $0 { return false }; return true }
            calendarItems = (nonPractice + practiceItems).sorted { $0.date < $1.date }
        }
    }

    func loadCalendarMySignups() async {
        let email = googleVM.userEmail
        guard !email.isEmpty else { return }
        let signups = (try? await FirebaseService.shared.fetchMySignups(userEmail: email)) ?? []
        let grouped = Dictionary(grouping: signups) { $0.eventId }
        await MainActor.run { calendarMySignups = grouped }
    }

    func loadCalendarSportsEvents() async -> [SportsEvent] {
        var allEvents: [SportsEvent] = []
        await withTaskGroup(of: [SportsEvent].self) { group in
            for cal in teamCalendars {
                group.addTask { await self.fetchCalendarSportsEvents(from: cal) }
            }
            for await events in group { allEvents.append(contentsOf: events) }
        }
        return allEvents
    }

    func fetchGradeDetail(courseID: Int, gradingPeriod: Int) async -> GradeDetailResult? {
        let urlStr = "https://documents.veracross.com/oakwood/grade_detail/\(courseID)?grading_period=\(gradingPeriod)&key=_"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpShouldHandleCookies = true
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html) else { return nil }

        let semesterTitle = (try? doc.select("#header h1").first()?.text()) ?? ""
        let gradingMethod = (try? doc.select("p.assignment_grading_method").first()?.text()) ?? ""
        let ptdGrade = (try? doc.select("span.ptd_grade").first()?.text()) ?? ""
        let letterGrade = (try? doc.select("span.letter_grade").first()?.text()) ?? ""

        let rows = (try? doc.select("#assignment_type_summary table tbody tr").array()) ?? []
        var breakdown: [GradeTypeBreakdown] = []
        for row in rows {
            guard let descCell = try? row.select("td.description").first() else { continue }
            let typeName = (try? descCell.select("strong").first()?.text()) ?? ""
            guard !typeName.isEmpty else { continue }
            let countText = (try? descCell.select("span.num_assignments").first()?.text()) ?? ""
            let count = Int(countText.filter(\.isNumber)) ?? 0
            let earned = Double((try? row.select("td.points_earned").first()?.text().trimmingCharacters(in: .whitespaces)) ?? "") ?? 0
            let possible = Double((try? row.select("td.points_possible").first()?.text().trimmingCharacters(in: .whitespaces)) ?? "") ?? 0
            let average = Double((try? row.select("td.average").first()?.text().trimmingCharacters(in: .whitespaces)) ?? "") ?? 0
            let weightText = (try? row.select("td.weight").first()?.text().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) ?? ""
            let weight = Double(weightText)
            breakdown.append(GradeTypeBreakdown(typeName: typeName, count: count, pointsEarned: earned, pointsPossible: possible, average: average, weight: weight))
        }

        return GradeDetailResult(semesterTitle: semesterTitle, gradingMethod: gradingMethod, ptdGrade: ptdGrade, letterGrade: letterGrade, breakdown: breakdown)
    }

    func loadPersonalCalendarEvents() async -> [SchoolEvent] {
        print("[PersonalCal] personalCalendarURL = \(personalCalendarURL ?? "nil")")
        guard let urlString = personalCalendarURL,
              let url = URL(string: urlString) else { return [] }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let ics = String(data: data, encoding: .utf8) else {
            print("[PersonalCal] iCal fetch failed")
            return []
        }
        print("[PersonalCal] iCal fetched, \(ics.components(separatedBy: "BEGIN:VEVENT").count - 1) events")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return parseICalRecords(ics).compactMap { record -> SchoolEvent? in
            guard let uid = record["UID"],
                  let summary = record["SUMMARY"],
                  let dtstart = record["DTSTART"] else { return nil }
            let date = parseICalDate(dtstart)
            let endDate = record["DTEND"].flatMap { parseICalDate($0) }
            let location = record["LOCATION"]?.replacingOccurrences(of: "\\,", with: ",") ?? ""
            return SchoolEvent(
                id: uid, title: summary, date: date,
                startTime: timeFormatter.string(from: date),
                endTime: endDate.map { timeFormatter.string(from: $0) } ?? "",
                location: location, description: ""
            )
        }
    }

    func loadPracticeCalendarEvents() async -> [SchoolEvent] {
        guard !practiceCalendarURLs.isEmpty else { return [] }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let results = await withTaskGroup(of: [SchoolEvent].self) { group in
            for urlString in practiceCalendarURLs {
                group.addTask {
                    guard let url = URL(string: urlString),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let ics = String(data: data, encoding: .utf8) else { return [] }
                    return self.parseICalRecords(ics).compactMap { record -> SchoolEvent? in
                        guard let uid = record["UID"], let summary = record["SUMMARY"], let dtstart = record["DTSTART"] else { return nil }
                        // TeamSnap exports local times with a Z suffix — strip it so they parse as device local time
                        let date = self.parseICalDate(dtstart.replacingOccurrences(of: "Z", with: ""))
                        let endDate = record["DTEND"].flatMap { self.parseICalDate($0.replacingOccurrences(of: "Z", with: "")) }
                        let location = record["LOCATION"]?.replacingOccurrences(of: "\\,", with: ",") ?? ""
                        return SchoolEvent(id: "practice-\(uid)", title: summary, date: date,
                            startTime: timeFormatter.string(from: date),
                            endTime: endDate.map { timeFormatter.string(from: $0) } ?? "",
                            location: location, description: "")
                    }
                }
            }
            var all: [SchoolEvent] = []
            for await batch in group { all += batch }
            return all
        }
        return results
    }

    func loadCalendarSchoolEvents() async -> [SchoolEvent] {
        guard !schoolEventsCalendarURL.isEmpty,
              let url = URL(string: schoolEventsCalendarURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ics = String(data: data, encoding: .utf8) else { return [] }
        return parseCalendarSchoolEvents(ics)
    }

    func fetchCalendarSportsEvents(from calendar: TeamCalendar) async -> [SportsEvent] {
        guard let url = URL(string: calendar.url),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ics = String(data: data, encoding: .utf8) else { return [] }
        return parseSportsICalEvents(ics, calendar: calendar)
    }

    func parseSportsICalEvents(_ ics: String, calendar: TeamCalendar) -> [SportsEvent] {
        return parseICalRecords(ics).compactMap { createSportsEvent(from: $0, calendar: calendar) }
    }

    func createSportsEvent(from data: [String: String], calendar: TeamCalendar) -> SportsEvent? {
        guard let uid = data["UID"], let summary = data["SUMMARY"], let dtstart = data["DTSTART"] else { return nil }
        let date = parseICalDate(dtstart)
        let endDate = data["DTEND"].flatMap { parseICalDate($0) }
        let location = data["LOCATION"]?.replacingOccurrences(of: "\\,", with: ",") ?? ""
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let isCancelled = summary.contains("CANCELLED") || data["STATUS"] == "CANCELLED"
        let isAway = summary.contains("(Away)") ? true : (summary.contains("(Home)") || location.lowercased().contains("oakwood")) ? false : true
        let teamName = calendar.name
            .replacingOccurrences(of: " \(calendar.sport)", with: "")
            .replacingOccurrences(of: calendar.sport, with: "")
            .trimmingCharacters(in: .whitespaces)
        return SportsEvent(
            id: uid, title: summary, date: date,
            startTime: timeFormatter.string(from: date),
            endTime: endDate.map { timeFormatter.string(from: $0) } ?? "",
            location: location, isAway: isAway, isCancelled: isCancelled,
            sportName: calendar.sport, teamName: teamName
        )
    }

    func parseCalendarSchoolEvents(_ ics: String) -> [SchoolEvent] {
        return parseICalRecords(ics).compactMap { createSchoolEvent(from: $0) }
    }

    func createSchoolEvent(from data: [String: String]) -> SchoolEvent? {
        guard let uid = data["UID"], let summary = data["SUMMARY"], let dtstart = data["DTSTART"] else { return nil }
        if summary.range(of: "^(HS|LS|MS)\\s+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)$", options: .regularExpression) != nil { return nil }
        if summary.range(of: "\\bvs\\b", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        if summary.range(of: "\\bmeet\\b", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let displayTitle = summary.localizedCaseInsensitiveContains("First Friday Schedule") ? "First Friday Late Start" : summary
        let date = parseICalDate(dtstart)
        let endDate = data["DTEND"].flatMap { parseICalDate($0) }
        let location = data["LOCATION"]?.replacingOccurrences(of: "\\,", with: ",") ?? ""
        let description = data["DESCRIPTION"]?.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\,", with: ",") ?? ""
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return SchoolEvent(
            id: uid, title: displayTitle, date: date,
            startTime: timeFormatter.string(from: date),
            endTime: endDate.map { timeFormatter.string(from: $0) } ?? "",
            location: location, description: description
        )
    }

    func parseICalRecords(_ ics: String) -> [[String: String]] {
        let unfolded = ics
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        var records: [[String: String]] = []
        var current: [String: String] = [:]
        var inEvent = false
        for line in unfolded.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if l == "BEGIN:VEVENT" { inEvent = true; current = [:] }
            else if l == "END:VEVENT" { records.append(current); inEvent = false }
            else if inEvent, let idx = l.firstIndex(of: ":") {
                let key = String(l[..<idx]).components(separatedBy: ";").first ?? ""
                current[key] = String(l[l.index(after: idx)...])
            }
        }
        return records
    }

    func parseICalDate(_ str: String) -> Date {
        let formats: [(String, TimeZone?)] = [
            ("yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC")),
            ("yyyyMMdd'T'HHmmss", nil),
            ("yyyyMMdd", nil)
        ]
        for (format, tz) in formats {
            let f = DateFormatter()
            f.dateFormat = format
            if let tz = tz { f.timeZone = tz }
            if let d = f.date(from: str) { return d }
        }
        return Date()
    }

    func loadResourceAssignmentIds() async {
        if let ids = try? await FirebaseService.shared.fetchResourceAssignmentIds() {
            await MainActor.run { resourceAssignmentIds = ids }
        }
    }

    // MARK: - Cookies: Export from storages into persistedCookies
    func captureCurrentCookies() async {
        let httpStore = HTTPCookieStorage.shared
        let wkStore = WKWebsiteDataStore.default().httpCookieStore

        // Gather cookies from both stores
        let sharedCookies = httpStore.cookies ?? []

        let wkCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            wkStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        // Merge by name+domain+path to avoid duplicates
        var merged: [String: HTTPCookie] = [:]
        let keyFor: (HTTPCookie) -> String = { "\($0.name)|\($0.domain)|\($0.path)" }
        for c in sharedCookies { merged[keyFor(c)] = c }
        for c in wkCookies { merged[keyFor(c)] = c }

        // Convert to property dictionaries
        let propertyDicts: [[HTTPCookiePropertyKey: Any]] = merged.values.compactMap { cookie in
            cookie.properties
        }

        await MainActor.run {
            self.persistedCookies = propertyDicts
            self.cookiesLastSaved = Date()
        }
    }

    // MARK: - Cookies: Restore persisted cookies back to storages
    func restorePersistedCookiesIntoStores() async {
        guard !persistedCookies.isEmpty else { return }

        let httpStore = HTTPCookieStorage.shared
        let wkStore = WKWebsiteDataStore.default().httpCookieStore

        // Recreate cookies
        let cookies = persistedCookies.compactMap { HTTPCookie(properties: $0) }

        // Insert into shared HTTPCookieStorage
        for cookie in cookies {
            httpStore.setCookie(cookie)
        }

        // Insert into WKWebView cookie store
        await withTaskGroup(of: Void.self) { group in
            for cookie in cookies {
                group.addTask {
                    await withCheckedContinuation { cont in
                        wkStore.setCookie(cookie) {
                            cont.resume()
                        }
                    }
                }
            }
        }
    }
}

struct ClassS: Identifiable {
    var id = UUID()
    var name = ""
    var grade = ""
}
