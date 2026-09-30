//
//  Mac_GradesView.swift
//  School Notes
//
import SwiftUI

struct Mac_GradesView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var errorMessage: String?
    @State private var showStats = false

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)]

    var body: some View {
        // Own NavigationStack so pushing into a course detail view has its own self-contained
        // push/pop path — without this, the push shares the outer NavigationSplitView's own
        // path, and there's no reliable way back except switching to another sidebar tab and
        // back (same class of bug already fixed for Clubs/Service earlier).
        NavigationStack {
            Group {
                if appInfo.courses.isEmpty {
                    ContentUnavailableView(
                        "No Grades Yet",
                        systemImage: "list.bullet.rectangle.portrait",
                        description: Text(errorMessage ?? "Grades will appear here once loaded.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(appInfo.courses) { course in
                                Mac_CourseTile(course: course)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Grades")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showStats = true
                    } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                }
            }
            .sheet(isPresented: $showStats) {
                Mac_StatsSheet()
                    .environmentObject(appInfo)
                    .frame(minWidth: 480, idealWidth: 760, minHeight: 600, idealHeight: 700)
            }
            .refreshable { await refreshGrades() }
            // Refresh on every appearance, not just the first time courses is empty — matching
            // the iOS fix in VeracrossGradesView.onAppear. GradeNotificationService's background
            // check never writes into appInfo.courses (it only fires a local notification), so
            // reselecting this tab was the only remaining chance to pick up a change, and the old
            // "only load once" guard skipped it after the first load.
            .onAppear { Task { await refreshGrades() } }
        }
    }

    /// Matches VeracrossGradesView.loadGrades() on iOS.
    private func refreshGrades() async {
        await appInfo.restorePersistedCookiesIntoStores()
        await syncCookies()
        if let err = await appInfo.loadCourses() {
            errorMessage = err
            return
        }
        errorMessage = nil
        await appInfo.loadAllAssignments()
    }
}

// MARK: - Course Tile

private struct Mac_CourseTile: View {
    let course: Course
    @EnvironmentObject var appInfo: AppInfo

    private var unreadCount: Int {
        (course.assignments ?? []).filter { $0.is_unread == 1 }.count
    }

    var body: some View {
        NavigationLink {
            Mac_CourseDetailView(course: course)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(course.class_name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(appInfo.classColor(for: course) ?? .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.orange, in: Circle())
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    if let letter = course.ptd_letter_grade, !letter.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(letter.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(for: course.ptd_grade))
                    } else {
                        Text("--")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let grade = course.ptd_grade {
                        Text("\(grade)%")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(gradeColor(for: grade))
                    }
                }
            }
            .padding(20)
            .frame(height: 170, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Course Detail (full page)

private struct Mac_CourseDetailView: View {
    let course: Course
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss
    @State private var showDirectory = false
    @State private var isLoadingRoster = false
    @State private var hasLoadedRoster = false
    @State private var rosterPeople: [DirectoryPerson] = []

    private var assignments: [Assignment] { course.assignments ?? [] }

    private var todoAssignments: [Assignment] {
        Array(assignments.filter { appInfo.info[$0.score_id, default: false] == false }.reversed())
    }

    private var completedAssignments: [Assignment] {
        assignments.filter { appInfo.info[$0.score_id, default: false] == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Mac_GradeBreakdownPanel(course: course)
                GradeHeaderView(course: course, assignments: assignments)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                HStack(alignment: .top, spacing: 32) {
                    assignmentColumn(title: "Completed (\(completedAssignments.count))", assignments: completedAssignments)
                    assignmentColumn(title: "To Do (\(todoAssignments.count))", assignments: todoAssignments)
                }
            }
            .padding(24)
        }
        .navigationTitle(course.class_name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { dismiss() } label: { Label("Grades", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    showDirectory = true
                } label: {
                    Image(systemName: "person.2")
                }
            }
        }
        .sheet(isPresented: $showDirectory) {
            NavigationStack {
                Group {
                    if isLoadingRoster {
                        ProgressView("Loading roster…")
                    } else if rosterPeople.isEmpty {
                        ContentUnavailableView(
                            "Couldn't Load Class Roster",
                            systemImage: "person.2.slash",
                            description: Text("Check the Xcode console for [ClassRoster] diagnostic output.")
                        )
                    } else {
                        List(rosterPeople) { person in
                            Mac_ClassRosterPersonRow(person: person)
                        }
                        .macInsetListStyle()
                    }
                }
                .navigationTitle("Directory")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDirectory = false }
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 500)
            .onAppear {
                guard !hasLoadedRoster else { return }
                hasLoadedRoster = true
                isLoadingRoster = true
                Task {
                    await appInfo.restorePersistedCookiesIntoStores()
                    await syncCookies()
                    let people = await ClassRosterCache.shared.roster(for: course)
                    await MainActor.run {
                        rosterPeople = people
                        isLoadingRoster = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func assignmentColumn(title: String, assignments: [Assignment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            if assignments.isEmpty {
                Text("Nothing here")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assignments, id: \.score_id) { assignment in
                    Mac_CourseAssignmentRow(assignment: assignment, courseName: course.class_name)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Class Roster Row

private struct Mac_ClassRosterPersonRow: View {
    let person: DirectoryPerson

    var body: some View {
        HStack(spacing: 12) {
            Mac_DirectoryPhoto(urlString: person.photoURL, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.body)
                HStack(spacing: 6) {
                    if !person.grade.isEmpty {
                        Text(person.grade).font(.caption).foregroundStyle(.secondary)
                    }
                    if let email = person.studentEmail {
                        Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .macRowPadding()
    }
}

// MARK: - Grade Breakdown Panel

private struct Mac_GradeBreakdownPanel: View {
    let course: Course
    @EnvironmentObject var appInfo: AppInfo

    @State private var selectedPeriod = 6  // 6 = S2 (current), 2 = S1
    @State private var result: GradeDetailResult? = nil
    @State private var isLoading = false

    private var enrollmentPK: Int { course.enrollment_pk ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Grade Breakdown").font(.headline)
                Spacer()
                Picker("Semester", selection: $selectedPeriod) {
                    Text("S1").tag(2)
                    Text("S2").tag(6)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let result {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.semesterTitle).font(.subheadline.weight(.semibold))
                        Text(result.gradingMethod).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(result.letterGrade).font(.title3.bold())
                        if let pct = Double(result.ptdGrade) {
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption)
                                .foregroundStyle(gradeColor(for: result.ptdGrade))
                        }
                    }
                }

                if !result.breakdown.isEmpty {
                    Divider()

                    ForEach(result.breakdown) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.typeName).font(.subheadline.weight(.semibold))
                                if let w = row.weight {
                                    Text(String(format: "%.0f%% of grade", w))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(String(format: "%.1f%%", row.average))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(gradeColor(for: String(row.average)))
                            }
                            HStack {
                                Text("\(row.count) assignment\(row.count == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f / %.1f pts", row.pointsEarned, row.pointsPossible))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No data available for this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task(id: selectedPeriod) { await load() }
    }

    private func load() async {
        guard enrollmentPK > 0 else { return }
        isLoading = true
        result = nil
        await syncCookies()
        result = await appInfo.fetchGradeDetail(courseID: enrollmentPK, gradingPeriod: selectedPeriod)
        isLoading = false
    }
}

// MARK: - Course Assignment Row

private struct Mac_CourseAssignmentRow: View {
    let assignment: Assignment
    let courseName: String
    @EnvironmentObject var appInfo: AppInfo
    @State private var showDetail = false

    private var isComplete: Bool { appInfo.info[assignment.score_id, default: false] }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(assignment.assignment_description)
                    .font(.body)
                    .foregroundStyle(isComplete ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    let type = assignment.assignment_type ?? ""
                    Badge(text: type.isEmpty ? "Unknown" : type, color: assignmentTypeColor(type))
                    if let due = assignment.due_date, !due.isEmpty {
                        Text(due)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            // Matches ShowAssignment(showGrade: true) on iOS (Veracross.swift/CourseView) —
            // this row was missing the actual grade entirely, showing only the due date even
            // for an assignment that's already been scored.
            VStack(alignment: .trailing, spacing: 2) {
                if assignment.completion_status == "Not Turned In" {
                    Text("NTI")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } else if let raw = assignment.raw_score, !raw.isEmpty, let percent = assignment.gradePercent {
                    Text("\(raw) / \(assignment.maximum_score ?? 0)")
                        .font(.subheadline)
                    Text(percent, format: .percent.precision(.fractionLength(2)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let status = assignment.completion_status, status.hasPrefix("Turned In") {
                    Text("Turned In")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                withAnimation(.snappy) {
                    appInfo.toggleInfo(for: assignment.score_id)
                }
            } label: {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(isComplete ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail) {
            Mac_AssignmentDetailView(assignment: assignment, courseName: courseName)
                .frame(width: 340)
        }
    }
}
