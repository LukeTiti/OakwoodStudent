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
struct Attachment: Codable, Identifiable {
    var id: Int { file_pk }
    let assignment_id: Int
    let file_pk: Int
    let type: String
    let description: String
    let url: String
}

struct AssignmentResponse: Codable {
    let assignments: [Assignment]
    let attachments: [Attachment]?
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
    var assignment_id: Int?
    var assignment_type: String?
    var assignment_description: String
    var assignment_notes: String?
    var raw_score: String?
    var maximum_score: Int?
    var due_date: String?
    var completion_status: String?
    var is_unread: Int?
    var customCourseName: String?
    var attachments: [Attachment]?
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
    @State private var showStats = false
    @EnvironmentObject var appInfo: AppInfo

    var body: some View {
        NavigationStack {
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
                List {
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
                                VStack(alignment: .center, spacing: 2) {
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
                            .macRowPadding()
                        }
                    }
                }
                .refreshable {
                    await loadGrades()
                    await appInfo.captureCurrentCookies()
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            showStats = true
                        } label: {
                            Image(systemName: "chart.bar.fill")
                        }
                    }
                }
                .navigationTitle("Grades")
                .macInsetListStyle()
                .sheet(isPresented: $showStats) {
                    StatsSheet()
                        .environmentObject(appInfo)
                }
            }
        }
        .onAppear {
            guard loginState == .checking else { return }
            if !appInfo.courses.isEmpty {
                loginState = .loggedIn
                Task {
                    await appInfo.restorePersistedCookiesIntoStores()
                    await syncCookies()
                }
                return
            }
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
    @State private var showGradeDetail = false
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
            Section {
                GradeHeaderView(course: liveCourse, assignments: assignments)
            }

            Section(header: Text("To Do (\(todoCount))")) {
                ForEach(assignments.filter { appInfo.info[$0.score_id, default: false] == false }, id: \.score_id) { assignment in
                    NavigationLink(destination: AssignmentDetailView(assignment: assignment, courseName: course?.class_name ?? "")) {
                        ShowAssignment(assignment: assignment)
                    }
                }
            }

            Section(header: Text("Completed (\(completedCount))")) {
                ForEach(assignments.filter { appInfo.info[$0.score_id, default: false] == true }, id: \.score_id) { assignment in
                    NavigationLink(destination: AssignmentDetailView(assignment: assignment, courseName: course?.class_name ?? "")) {
                        ShowAssignment(assignment: assignment, showGrade: true)
                    }
                }
            }
        }
        .navigationTitle(course?.class_name ?? "Unknown")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showGradeDetail = true
                } label: {
                    Image(systemName: "chart.bar.fill")
                }
            }
        }
        .sheet(isPresented: $showGradeDetail) {
            if let c = liveCourse {
                CourseGradeDetailSheet(course: c)
                    .environmentObject(appInfo)
            }
        }
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
                await appInfo.loadResourceAssignmentIds()
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
        var lastItemDate: Date? = nil
        var sameDayCount = 0

        for item in graded {
            if !didResetSemester && item.date >= semesterStart {
                didResetSemester = true
                totalEarned = 0; totalPossible = 0
                points.append(GradePoint(date: semesterStart, percent: 100, name: "Semester 2 Start", score: "100%", isSemesterStart: true))
            }

            totalEarned += item.earned
            totalPossible += item.possible
            let pct = (totalEarned / totalPossible) * 100

            if let last = lastItemDate, cal.isDate(last, inSameDayAs: item.date) {
                sameDayCount += 1
            } else {
                sameDayCount = 0
            }
            lastItemDate = item.date

            let plotDate = sameDayCount > 0
                ? (cal.date(byAdding: .day, value: sameDayCount * 2, to: item.date) ?? item.date)
                : item.date

            points.append(GradePoint(date: plotDate, percent: pct, name: item.name, score: item.score))
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
                HStack {
                    if let sel = selectedPoint {
                        Text(sel.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        let parts = sel.score.split(separator: "/")
                        let individualPct: String? = parts.count == 2
                            ? Double(parts[0]).flatMap { e in Double(parts[1]).map { m in String(format: "%.0f%%", e / m * 100) } }
                            : nil
                        Text(individualPct != nil
                             ? "\(sel.score) (\(individualPct!)) · \(String(format: "%.1f", sel.percent))%"
                             : "\(sel.score) · \(String(format: "%.1f", sel.percent))%")
                            .font(.caption)
                            .foregroundColor(gradeColor(for: String(sel.percent)))
                    } else {
                        let gradedCount = gradeHistory.filter { $0.score.contains("/") }.count
                        Text("\(gradedCount) graded assignment\(gradedCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .frame(height: 18)
                .animation(.easeInOut(duration: 0.1), value: selectedPoint?.name)

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
        let semStart = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1))!

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

class VeracrossLoginCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var onLogin: () -> Void
    init(onLogin: @escaping () -> Void) { self.onLogin = onLogin }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        if url.contains("/student") {
            onLogin()
        } else if url.contains("portals.veracross.com") {
            // Scroll the login form into view so the username/password fields are visible
            webView.evaluateJavaScript("document.querySelector('form input[type=\"text\"], form input[type=\"email\"], form')?.scrollIntoView({block:'start'});")
        }
    }

    // Prevent macOS from redirecting navigations to associated apps (e.g. Dock web apps)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        #if os(macOS)
        if let policy = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) {
            decisionHandler(policy, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
        #else
        decisionHandler(.allow, preferences)
        #endif
    }

    // Handle popup windows (e.g. Google/SAML OAuth) by creating a child WebView
    // that shares the session via the provided configuration
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        #if os(macOS)
        popup.autoresizingMask = [.width, .height]
        #else
        popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        webView.addSubview(popup)
        return popup
    }

    // Remove the popup when the page calls window.close()
    func webViewDidClose(_ webView: WKWebView) {
        webView.removeFromSuperview()
    }
}

#if os(iOS)
struct VeracrossLoginView: UIViewRepresentable {
    let url: URL; var onLogin: () -> Void
    func makeCoordinator() -> VeracrossLoginCoordinator { VeracrossLoginCoordinator(onLogin: onLogin) }
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
struct VeracrossLoginView: NSViewRepresentable {
    let url: URL; var onLogin: () -> Void
    func makeCoordinator() -> VeracrossLoginCoordinator { VeracrossLoginCoordinator(onLogin: onLogin) }
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

private extension VeracrossLoginView {
    func makeWebView(coordinator: VeracrossLoginCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
}

// MARK: - Grade Share Card
struct GradeShareCard: View {
    let assignment: Assignment
    let courseName: String

    private var hasGrade: Bool { assignment.gradePercent != nil }

    private var percent: Double {
        (assignment.gradePercent ?? 0) * 100
    }

    private var cardColor: Color {
        hasGrade ? gradeColor(for: String(percent)) : .blue
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(assignment.assignment_description)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if hasGrade {
                VStack(spacing: 4) {
                    Text("\(assignment.raw_score ?? "--") / \(assignment.maximum_score ?? 0)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    Text(String(format: "%.1f%%", percent))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }

                Text(courseName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                if let due = assignment.due_date, !due.isEmpty {
                    Text("Due \(due)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(courseName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                if let notes = assignment.assignment_notes, !notes.isEmpty {
                    Text(notes)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 8) {
                if let type = assignment.assignment_type, !type.isEmpty {
                    Text(type)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(.white.opacity(0.8))

            Text("Oakwood Students")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(24)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [cardColor.opacity(0.8), cardColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Share Helpers
struct IdentifiableImage: Identifiable {
    let id = UUID()
    #if os(iOS)
    let image: UIImage
    #elseif os(macOS)
    let image: NSImage
    #endif
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// MARK: - Stats Sheet
struct StatsSheet: View {
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss

    private func letterToPoints(_ letter: String) -> Double? {
        switch letter.trimmingCharacters(in: .whitespaces) {
        case "A":   return 4.0
        case "A-":  return 3.7
        case "B+":  return 3.3
        case "B":   return 3.0
        case "B-":  return 2.7
        case "C+":  return 2.3
        case "C":   return 2.0
        case "C-":  return 1.7
        case "D+":  return 1.3
        case "D":   return 1.0
        case "D-":  return 0.7
        case "F":   return 0.0
        default:    return nil
        }
    }

    private func gpaColor(_ points: Double) -> Color {
        if points >= 3.7 { return .green }
        if points >= 3.0 { return .yellow }
        if points >= 2.0 { return .orange }
        return .red
    }

    private func isWeighted(_ courseName: String) -> Bool {
        let lower = courseName.lowercased()
        return lower.contains("honors") || lower.contains("ap ")
    }

    private struct CourseGPAEntry {
        let name: String
        let letter: String
        let percent: String?
        let points: Double
        let weighted: Bool
    }

    private var entries: [CourseGPAEntry] {
        appInfo.courses.compactMap { course in
            let nameLower = course.class_name.lowercased()
            guard !nameLower.contains("independent pe"),
                  !nameLower.contains("community meeting"),
                  !nameLower.contains("assembly") else { return nil }
            let weighted = isWeighted(course.class_name)
            let hasAssignments = !(course.assignments ?? []).isEmpty

            let letter: String
            var pts: Double

            if let l = course.ptd_letter_grade,
               !l.trimmingCharacters(in: .whitespaces).isEmpty,
               let p = letterToPoints(l) {
                // Has a real grade — use it
                letter = l.trimmingCharacters(in: .whitespaces)
                pts = p
            } else if !hasAssignments {
                // No assignments yet — assume A (100%)
                letter = "A"
                pts = 4.0
            } else {
                // Has assignments but no letter grade yet — skip
                return nil
            }

            if weighted { pts += 1 }
            return CourseGPAEntry(name: course.class_name, letter: letter, percent: course.ptd_grade, points: pts, weighted: weighted)
        }
    }

    private var weightedGPA: Double? {
        guard !entries.isEmpty else { return nil }
        return entries.map(\.points).reduce(0, +) / Double(entries.count)
    }

    private var unweightedGPA: Double? {
        guard !entries.isEmpty else { return nil }
        let unweightedPoints = entries.map { $0.weighted ? $0.points - 1 : $0.points }
        return unweightedPoints.reduce(0, +) / Double(entries.count)
    }

    var body: some View {
        NavigationStack {
            List {
                if let weighted = weightedGPA, let unweighted = unweightedGPA {
                    Section {
                        HStack(spacing: 0) {
                            Spacer()
                            VStack(spacing: 4) {
                                Text(weighted, format: .number.precision(.fractionLength(2)))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundColor(gpaColor(weighted))
                                Text("Weighted")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Divider()
                            Spacer()
                            VStack(spacing: 4) {
                                Text(unweighted, format: .number.precision(.fractionLength(2)))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundColor(gpaColor(unweighted))
                                Text("Unweighted")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        Text("No grade data yet. Grades load from Veracross.")
                            .foregroundColor(.secondary)
                    }
                }

                if !entries.isEmpty {
                    Section("Courses") {
                        ForEach(entries, id: \.name) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.body)
                                    if entry.weighted {
                                        Text("Weighted")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(entry.letter)
                                        .fontWeight(.semibold)
                                        .foregroundColor(gpaColor(entry.points))
                                    let unweightedPts = entry.weighted ? entry.points - 1 : entry.points
                                    if entry.weighted {
                                        HStack(spacing: 8) {
                                            Text("W: \(entry.points, format: .number.precision(.fractionLength(1)))")
                                                .foregroundColor(gpaColor(entry.points))
                                            Text("UW: \(unweightedPts, format: .number.precision(.fractionLength(1)))")
                                                .foregroundColor(gpaColor(unweightedPts))
                                        }
                                        .font(.subheadline)
                                    } else {
                                        Text(entry.points, format: .number.precision(.fractionLength(1)))
                                            .font(.subheadline)
                                            .foregroundColor(gpaColor(entry.points))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Grade Detail Models
struct GradeTypeBreakdown: Identifiable {
    let id = UUID()
    let typeName: String
    let count: Int
    let pointsEarned: Double
    let pointsPossible: Double
    let average: Double
    let weight: Double?  // only present for "Weighting by Assignment Type and Points"
}

struct GradeDetailResult {
    let semesterTitle: String
    let gradingMethod: String
    let ptdGrade: String
    let letterGrade: String
    let breakdown: [GradeTypeBreakdown]
}

// MARK: - Grade Detail Sheet
struct CourseGradeDetailSheet: View {
    let course: Course
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPeriod = 6  // 6 = S2 (current), 2 = S1
    @State private var result: GradeDetailResult? = nil
    @State private var isLoading = false

    private var enrollmentPK: Int { course.enrollment_pk ?? 0 }

    var body: some View {
        NavigationStack {
            List {
                Picker("Semester", selection: $selectedPeriod) {
                    Text("Semester 1").tag(2)
                    Text("Semester 2").tag(6)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.horizontal)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let result {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.semesterTitle).font(.headline)
                                Text(result.gradingMethod).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(result.letterGrade).font(.title2.bold())
                                if let pct = Double(result.ptdGrade) {
                                    Text(String(format: "%.1f%%", pct))
                                        .font(.caption)
                                        .foregroundColor(gradeColor(for: result.ptdGrade))
                                }
                            }
                        }
                    }

                    Section(header: Text("By Assignment Type")) {
                        ForEach(result.breakdown) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(row.typeName).fontWeight(.semibold)
                                    if let w = row.weight {
                                        Text(String(format: "%.0f%% of grade", w))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f%%", row.average))
                                        .foregroundColor(gradeColor(for: String(row.average)))
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("\(row.count) assignment\(row.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f / %.1f pts", row.pointsEarned, row.pointsPossible))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    Text("No data available for this period.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Grade Breakdown")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedPeriod) { _ in load() }
            .onAppear { load() }
        }
    }

    private func load() {
        guard enrollmentPK > 0 else { return }
        isLoading = true
        result = nil
        Task {
            await syncCookies()
            let fetched = await appInfo.fetchGradeDetail(courseID: enrollmentPK, gradingPeriod: selectedPeriod)
            await MainActor.run {
                result = fetched
                isLoading = false
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
