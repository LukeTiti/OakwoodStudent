//
//  Veracross.swift
//  School Notes
//
//  Created by Luke Titi on 9/17/25.
//
import SwiftUI
import WebKit

// MARK: - Grades View

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
                    .unreadRowBackground(assignment.is_unread)
                }
            }

            Section(header: Text("Completed (\(completedCount))")) {
                ForEach(assignments.filter { appInfo.info[$0.score_id, default: false] == true }, id: \.score_id) { assignment in
                    NavigationLink(destination: AssignmentDetailView(assignment: assignment, courseName: course?.class_name ?? "")) {
                        ShowAssignment(assignment: assignment, showGrade: true)
                    }
                    .unreadRowBackground(assignment.is_unread)
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
            guard let course = course, !appInfo.isBundledMode else { return }
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


// MARK: - Document Web View (zoomable, shares Veracross cookie store)

#if os(iOS)
struct DocumentWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 5.0
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
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
            let sportsAndNonAcademic = ["independent pe", "community meeting", "assembly",
                "study period", "volleyball", "basketball", "tennis", "badminton",
                "soccer", "swimming", "track", "cross country"]
            guard !sportsAndNonAcademic.contains(where: { nameLower.contains($0) }),
                  !(nameLower.contains("hs") && nameLower.contains("team")) else { return nil }
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

                Section("Documents") {
                    let pk = appInfo.personPK ?? 39950
                    NavigationLink(destination: DocumentWebView(url: URL(string: "https://documents.veracross.com/oakwood/attendance/\(pk)?grading_period=2&key=_")!)
                        .navigationTitle("Attendance – Sem 1").inlineNavigationBarTitle()) {
                        Label("Attendance – Semester 1", systemImage: "doc.text")
                    }
                    NavigationLink(destination: DocumentWebView(url: URL(string: "https://documents.veracross.com/oakwood/attendance/\(pk)?grading_period=6&key=_")!)
                        .navigationTitle("Attendance – Sem 2").inlineNavigationBarTitle()) {
                        Label("Attendance – Semester 2", systemImage: "doc.text")
                    }
                    NavigationLink(destination: DocumentWebView(url: URL(string: "https://documents.veracross.com/oakwood/report_card/8231?grading_period=2&pad=32941")!)
                        .navigationTitle("Report Card – Sem 1").inlineNavigationBarTitle()) {
                        Label("Report Card – Semester 1", systemImage: "doc.richtext")
                    }
                    NavigationLink(destination: DocumentWebView(url: URL(string: "https://documents.veracross.com/oakwood/report_card/8231?grading_period=6&pad=32941")!)
                        .navigationTitle("Report Card – Sem 2").inlineNavigationBarTitle()) {
                        Label("Report Card – Semester 2", systemImage: "doc.richtext")
                    }
                }
                .onAppear {
                    if appInfo.personPK == nil { Task { await appInfo.fetchPersonPK() } }
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
