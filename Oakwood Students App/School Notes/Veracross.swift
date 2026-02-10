//
//  Veracross.swift
//  School Notes
//
//  Created by Luke Titi on 9/17/25.
//
import SwiftUI
import Charts
import WebKit

// MARK: - Data Models
struct CoursesResponse: Codable {
    let courses: [Course]
}
struct AssignmentResponse: Codable {
    let assignments: [Assignment]
}

struct Course: Codable, Identifiable {
    var id: String { class_id }

    var enrollment_pk: Int?
    var class_id: String
    var class_name: String
    var ptd_grade: String?
    var ptd_letter_grade: String?
    var assignments: [Assignment]?
}

struct Assignment: Codable, Identifiable {
    var id: String { assignment_description }

    var score_id: Int
    var assignment_type: String?
    var assignment_description: String
    var assignment_notes: String?
    var raw_score: String?
    var maximum_score: Int?
    var due_date: String?
    var completion_status: String?
    var is_unread: Int?
}

// MARK: - Assignment Helpers
extension Assignment {
    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parses the due_date string into a Date, handling "Wed, Oct 01" and "Oct 01" formats.
    var dueDate: Date? {
        guard let dateStr = due_date else { return nil }
        let cleaned = dateStr.contains(",")
            ? String(dateStr.split(separator: ",", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
            : dateStr
        guard let parsed = Self.dueDateFormatter.date(from: cleaned) else { return nil }

        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let month = cal.component(.month, from: parsed)
        let day = cal.component(.day, from: parsed)
        let year = month >= 8 ? currentYear - 1 : currentYear
        return cal.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Grade as a 0–1 fraction (raw_score / maximum_score), or nil if not graded.
    var gradePercent: Double? {
        guard let raw = raw_score, let score = Double(raw),
              let max = maximum_score, max > 0 else { return nil }
        return score / Double(max)
    }
}

// MARK: - Grade Color Helpers
func gradeColor(for percentString: String?) -> Color {
    guard let str = percentString, let value = Double(str) else { return .secondary }
    if value >= 90 { return .green }
    if value >= 80 { return .yellow }
    if value >= 70 { return .orange }
    return .red
}

func assignmentTypeColor(_ type: String) -> Color {
    switch type {
    case "Test", "Exam": return .red
    case "Quiz": return .orange
    case "Homework": return .blue
    default: return .green
    }
}

// MARK: - Grades View
enum GradesLoginState {
    case checking, needsLogin, loggedIn
}

struct VeracrossGradesView: View {
    @State private var loginState: GradesLoginState = .checking
    @State private var errorMessage: String?
    @EnvironmentObject var appInfo: AppInfo

    var body: some View {
        NavigationView {
            switch loginState {
            case .checking:
                ProgressView("Loading grades…")
            case .needsLogin:
                VeracrossLoginView(
                    url: URL(string: "https://portals.veracross.com/oakwood/student")!,
                    onLogin: {
                        Task {
                            await syncCookies()
                            await appInfo.captureCurrentCookies()
                            await loadGrades()
                        }
                        loginState = .loggedIn
                    }
                )
                .navigationTitle("Login to Veracross")
            case .loggedIn:
                NavigationStack {
                    List {
                        if let errorMessage = errorMessage {
                            Text("⚠️ \(errorMessage)")
                                .foregroundColor(.red)
                        }
                        ForEach(appInfo.courses) { course in
                            let unreadCount = (course.assignments ?? []).filter { $0.is_unread == 1 }.count
                            NavigationLink(destination: CourseView(course: course)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(course.class_name)
                                            .font(.headline)
                                            .lineLimit(2)
                                        if unreadCount > 0 {
                                            Text("\(unreadCount) unread assignment\(unreadCount == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let letter = course.ptd_letter_grade {
                                            Text(letter.trimmingCharacters(in: .whitespaces))
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundColor(gradeColor(for: course.ptd_grade))
                                        }
                                        if let grade = course.ptd_grade {
                                            Text("\(grade)%")
                                                .font(.caption)
                                                .foregroundColor(gradeColor(for: grade))
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                Task {
                                    await loadGrades()
                                    await appInfo.captureCurrentCookies()
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    .navigationTitle("Grades")
                }
            }
        }
        .onAppear {
            guard loginState == .checking else { return }
            Task {
                await appInfo.restorePersistedCookiesIntoStores()
                await syncCookies()
                await loadGrades()
                loginState = appInfo.courses.isEmpty ? .needsLogin : .loggedIn
            }
        }
    }

    func loadGrades() async {
        let err = await appInfo.loadCourses()
        await MainActor.run {
            if let err = err {
                errorMessage = err
                if err.contains("Not authenticated") { loginState = .needsLogin }
            } else {
                errorMessage = nil
            }
        }
        if err == nil {
            await appInfo.loadAllAssignments()
        }
    }
}

// MARK: - Course Detail View
struct CourseView: View {
    @State private var errorMessage: String?
    @State var course: Course?
    @EnvironmentObject var appInfo: AppInfo

    private var liveCourse: Course? {
        guard let course = course else { return nil }
        return appInfo.courses.first(where: { $0.enrollment_pk == course.enrollment_pk }) ?? course
    }

    private var assignments: [Assignment] {
        liveCourse?.assignments ?? []
    }

    private var todoCount: Int {
        assignments.filter { appInfo.info[$0.score_id, default: false] == false }.count
    }

    private var completedCount: Int {
        assignments.filter { appInfo.info[$0.score_id, default: false] == true }.count
    }

    var body: some View {
        List {
            if let errorMessage = errorMessage {
                Text("⚠️ \(errorMessage)")
                    .foregroundColor(.red)
            }

            Section {
                GradeHeaderView(course: liveCourse, assignments: assignments)
            }

            Section(header: Text("To Do (\(todoCount))")) {
                ForEach(assignments.filter { appInfo.info[$0.score_id, default: false] == false }, id: \.score_id) { assignment in
                    NavigationLink(destination: AssignmentDetailView(assignment: assignment)) {
                        ShowAssignment(assignment: assignment)
                    }
                }
            }

            Section(header: Text("Completed (\(completedCount))")) {
                ForEach(assignments.filter { appInfo.info[$0.score_id, default: false] == true }, id: \.score_id) { assignment in
                    NavigationLink(destination: AssignmentDetailView(assignment: assignment)) {
                        ShowAssignment(assignment: assignment, showGrade: true)
                    }
                }
            }
        }
        .navigationTitle(course?.class_name ?? "Unknown")
        .onAppear {
            guard let course = course else { return }
            let courseID = course.enrollment_pk ?? 0
            Task {
                await syncCookies()
                let err = await appInfo.loadAssignments(courseID: courseID)
                await MainActor.run {
                    if let err { errorMessage = err }
                    appInfo.initializeCompletionStatus(forCourseID: courseID)
                }
            }
        }
    }
}

// MARK: - Grade Header + Chart
struct GradePoint: Identifiable {
    let id = UUID()
    let date: Date
    let percent: Double
    let name: String
    let score: String
    var isSemesterStart: Bool = false
}

struct GradeHeaderView: View {
    let course: Course?
    let assignments: [Assignment]
    @State private var selectedPoint: GradePoint?

    private var gradeHistory: [GradePoint] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let semesterStart = cal.date(from: DateComponents(year: currentYear, month: 1, day: 1))!

        let graded = assignments
            .compactMap { a -> (date: Date, earned: Double, possible: Double, name: String, score: String)? in
                guard let date = a.dueDate,
                      let earned = Double(a.raw_score ?? ""),
                      let max = a.maximum_score, max > 0 else { return nil }
                return (date, earned, Double(max), a.assignment_description, "\(a.raw_score!)/\(max)")
            }
            .sorted { $0.date < $1.date }

        guard !graded.isEmpty else { return [] }

        var totalEarned = 0.0, totalPossible = 0.0
        var points: [GradePoint] = []
        var didResetSemester = false

        for item in graded {
            if !didResetSemester && item.date >= semesterStart {
                didResetSemester = true
                totalEarned = 0; totalPossible = 0
                points.append(GradePoint(date: semesterStart, percent: 100, name: "Semester 2 Start", score: "100%", isSemesterStart: true))
            }

            totalEarned += item.earned
            totalPossible += item.possible
            let pct = (totalEarned / totalPossible) * 100

            if let last = points.last, cal.isDate(last.date, inSameDayAs: item.date) {
                points[points.count - 1] = GradePoint(date: item.date, percent: pct, name: item.name, score: item.score)
            } else {
                points.append(GradePoint(date: item.date, percent: pct, name: item.name, score: item.score))
            }
        }

        if let gradeStr = course?.ptd_grade, let currentGrade = Double(gradeStr),
           let futureDate = cal.date(byAdding: .day, value: 7, to: Date()) {
            points.append(GradePoint(date: futureDate, percent: currentGrade, name: "Current Grade", score: gradeStr + "%"))
        }

        return points
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let grade = course?.ptd_grade {
                        Text("\(grade)%")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(gradeColor(for: grade))
                    } else {
                        Text("--")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                    if let letter = course?.ptd_letter_grade {
                        Text(letter.trimmingCharacters(in: .whitespaces))
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            if gradeHistory.count >= 2 {
                GradeChartView(points: gradeHistory, selectedPoint: $selectedPoint)
                    .frame(height: 150)
            } else if !assignments.isEmpty {
                Text("Not enough graded assignments to show trend")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No assignments yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Grade Chart
struct GradeChartView: View {
    let points: [GradePoint]
    @Binding var selectedPoint: GradePoint?

    var body: some View {
        let minY = (points.map(\.percent).min() ?? 50) - 2
        let maxY = (points.map(\.percent).max() ?? 100) + 2
        let semStart = Calendar.current.date(from: DateComponents(
            year: Calendar.current.component(.year, from: Date()), month: 1, day: 1
        ))!

        Chart {
            RuleMark(x: .value("Semester", semStart))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("S2").font(.caption2).foregroundColor(.secondary)
                }

            ForEach(1..<points.count, id: \.self) { i in
                let prev = points[i - 1]
                let curr = points[i]

                // Skip the segment that would cross the semester boundary
                if !curr.isSemesterStart {
                    let color = gradeColor(for: String(curr.percent))
                    LineMark(x: .value("Date", prev.date), y: .value("Grade", prev.percent), series: .value("Seg", i))
                        .foregroundStyle(color)
                    LineMark(x: .value("Date", curr.date), y: .value("Grade", curr.percent), series: .value("Seg", i))
                        .foregroundStyle(color)
                }
            }

            if let selected = selectedPoint {
                PointMark(x: .value("Date", selected.date), y: .value("Grade", selected.percent))
                    .foregroundStyle(gradeColor(for: String(selected.percent)))
                    .symbolSize(60)
                    .annotation(position: .top, spacing: 8) {
                        VStack(spacing: 2) {
                            Text(selected.name).font(.caption2).fontWeight(.semibold).lineLimit(1)
                            Text("\(selected.score) • \(String(format: "%.1f", selected.percent))%")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: minY...maxY)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(String(format: "%.0f", v))%").font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let x = drag.location.x - geo[proxy.plotAreaFrame].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selectedPoint = points.min(by: {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                })
                            }
                            .onEnded { _ in selectedPoint = nil }
                    )
            }
        }
    }
}

// MARK: - Login WebView
struct VeracrossLoginView: UIViewRepresentable {
    let url: URL
    var onLogin: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLogin: onLogin) }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onLogin: () -> Void
        init(onLogin: @escaping () -> Void) { self.onLogin = onLogin }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView.url?.absoluteString.contains("/student") == true {
                onLogin()
            }
        }
    }
}

// MARK: - Cookie Sync
func syncCookies() async {
    let cookies = await withCheckedContinuation { cont in
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            cont.resume(returning: cookies)
        }
    }
    for cookie in cookies {
        HTTPCookieStorage.shared.setCookie(cookie)
    }
}
