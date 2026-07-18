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
                .frame(minWidth: 480, minHeight: 600)
        }
        .onAppear { Task { await loadIfNeeded() } }
    }

    private func loadIfNeeded() async {
        guard appInfo.courses.isEmpty else { return }
        if !appInfo.isBundledMode {
            await appInfo.restorePersistedCookiesIntoStores()
            await syncCookies()
        }
        if let err = await appInfo.loadCourses() {
            errorMessage = err
            return
        }
        if !appInfo.isBundledMode {
            await appInfo.loadAllAssignments()
        }
    }
}

// MARK: - Course Tile

private struct Mac_CourseTile: View {
    let course: Course

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

// MARK: - Grade Breakdown Panel

private struct Mac_GradeBreakdownPanel: View {
    let course: Course

    @State private var selectedPeriod = 6  // 6 = S2 (current), 2 = S1

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

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Semester 2").font(.subheadline.weight(.semibold))
                    Text("Weighted Average").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("A").font(.title3.bold())
                    Text("--%").font(.caption).foregroundStyle(.secondary)
                }
            }
            .redacted(reason: .placeholder)

            Divider()

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Assignment Type").font(.subheadline.weight(.semibold))
                        Text("00% of grade")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                        Spacer()
                        Text("--%").font(.subheadline.weight(.semibold))
                    }
                    HStack {
                        Text("-- assignments").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("-- / -- pts").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
