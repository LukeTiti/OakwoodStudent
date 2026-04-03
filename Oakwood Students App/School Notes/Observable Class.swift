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
                await MainActor.run {
                    if let idx = self.courses.firstIndex(where: { $0.enrollment_pk == courseID }) {
                        self.courses[idx].assignments = decoded.assignments
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
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
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
            await grades; await calendar
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
        await MainActor.run { calendarIsLoading = true }

        async let sportsTask = loadCalendarSportsEvents()
        async let schoolTask = loadCalendarSchoolEvents()
        let (sports, school) = await (sportsTask, schoolTask)

        let combined: [CalendarItem] = sports.map { .sports($0) } + school.map { .school($0) }
        var seen = Set<String>()
        let unique = combined.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
        let fetchedScores = (try? await FirebaseService.shared.fetchAllGameScores()) ?? [:]
        await loadCalendarMySignups()

        await MainActor.run {
            calendarItems = unique
            calendarScores = fetchedScores
            calendarIsLoading = false
        }
    }

    func refreshCalendarData() async {
        async let scoresTask = FirebaseService.shared.fetchAllGameScores()
        await loadCalendarMySignups()
        let scores = (try? await scoresTask) ?? [:]
        await MainActor.run { calendarScores = scores }
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
        let date = parseICalDate(dtstart)
        let endDate = data["DTEND"].flatMap { parseICalDate($0) }
        let location = data["LOCATION"]?.replacingOccurrences(of: "\\,", with: ",") ?? ""
        let description = data["DESCRIPTION"]?.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\,", with: ",") ?? ""
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return SchoolEvent(
            id: uid, title: summary, date: date,
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
