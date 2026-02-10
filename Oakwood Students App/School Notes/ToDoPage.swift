//
//  ToDoPage.swift
//  School Notes
//
//  Created by Luke Titi on 10/1/25.
//
import SwiftUI

struct ToDoPage: View {
    @State var errorMessage = ""
    @EnvironmentObject var appInfo: AppInfo

    private var incompleteAssignments: [(assignment: Assignment, courseName: String)] {
        appInfo.courses.flatMap { course in
            (course.assignments ?? [])
                .filter { appInfo.info[$0.score_id, default: false] == false }
                .map { ($0, course.class_name) }
        }
    }

    private func assignmentsDue(dayOffset: Int) -> [(assignment: Assignment, courseName: String)] {
        guard let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) else { return [] }
        return incompleteAssignments.filter { item in
            guard let dueDate = item.assignment.dueDate else { return false }
            return Calendar.current.isDate(dueDate, inSameDayAs: targetDate)
        }
    }

    private var pastDueAssignments: [(assignment: Assignment, courseName: String)] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return incompleteAssignments.filter { item in
            guard let dueDate = item.assignment.dueDate else { return false }
            return dueDate < startOfToday
        }
    }

    private func sectionHeader(for dayOffset: Int) -> String {
        switch dayOffset {
        case 0: return "Today's Assignments"
        case 1: return "Tomorrow's Assignments"
        default:
            if let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) {
                return day.formatted(.dateTime.weekday(.wide))
            }
            return ""
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !errorMessage.isEmpty {
                    Text("⚠️ \(errorMessage)")
                        .foregroundColor(.red)
                }
                if !pastDueAssignments.isEmpty {
                    Section(header: Text("Past Due Assignments")) {
                        ForEach(pastDueAssignments, id: \.assignment.score_id) { item in
                            NavigationLink(destination: AssignmentDetailView(assignment: item.assignment, courseName: item.courseName)) {
                                ShowAssignment(assignment: item.assignment, courseName: item.courseName)
                            }
                        }
                    }
                }
                ForEach(0...10, id: \.self) { dayOffset in
                    let items = assignmentsDue(dayOffset: dayOffset)
                    if !items.isEmpty {
                        Section(header: Text(sectionHeader(for: dayOffset))) {
                            ForEach(items, id: \.assignment.score_id) { item in
                                NavigationLink(destination: AssignmentDetailView(assignment: item.assignment, courseName: item.courseName)) {
                                    ShowAssignment(assignment: item.assignment, courseName: item.courseName)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("To Do")
        }
        .onAppear {
            Task {
                await appInfo.restorePersistedCookiesIntoStores()
                await syncCookies()
                if appInfo.courses.isEmpty {
                    if let err = await appInfo.loadCourses() {
                        errorMessage = err
                        return
                    }
                }
                if let err = await appInfo.loadAllAssignments() {
                    errorMessage = err
                }
            }
        }
    }
}


struct ShowAssignment: View {
    let assignment: Assignment
    @EnvironmentObject var appInfo: AppInfo
    var courseName: String = ""
    var showGrade: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(assignment.assignment_description)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    let type = assignment.assignment_type ?? ""
                    Badge(
                        text: type.isEmpty ? "Unknown" : type,
                        color: assignmentTypeColor(type)
                    )
                    if !courseName.isEmpty {
                        Text(courseName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                if showGrade {
                    if assignment.completion_status == "Not Turned In" {
                        Text("NTI")
                            .foregroundColor(.red)
                    } else if let percent = assignment.gradePercent {
                        let color: Color = assignment.is_unread == 1 ? .orange : .primary
                        Text("\(assignment.raw_score ?? "") / \(assignment.maximum_score ?? 0)")
                            .foregroundStyle(color)
                        Text(percent, format: .percent.precision(.fractionLength(2)))
                            .foregroundStyle(color)
                    } else {
                        Text("Pending")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(assignment.due_date ?? "")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                appInfo.toggleInfo(for: assignment.score_id)
            } label: {
                let done = appInfo.info[assignment.score_id, default: false]
                Label(
                    done ? "Mark Incomplete" : "Mark Complete",
                    systemImage: done ? "xmark.circle" : "checkmark.circle"
                )
            }
            .tint(appInfo.info[assignment.score_id, default: false] ? .orange : .green)
        }
    }
}

struct AssignmentDetailView: View {
    let assignment: Assignment
    var courseName: String = ""
    @EnvironmentObject var appInfo: AppInfo
    @State private var shareImage: IdentifiableImage?

    var body: some View {
        List {
            if let raw = assignment.raw_score, !raw.isEmpty, let percent = assignment.gradePercent {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("\(raw) / \(assignment.maximum_score ?? 0)")
                                .font(.title)
                                .fontWeight(.bold)
                            Text(percent, format: .percent.precision(.fractionLength(1)))
                                .font(.headline)
                                .foregroundColor(gradeColor(for: String(percent * 100)))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Details") {
                if let type = assignment.assignment_type, !type.isEmpty {
                    HStack {
                        Text("Type")
                        Spacer()
                        Badge(text: type, color: assignmentTypeColor(type))
                    }
                }
                if let dueDate = assignment.due_date, !dueDate.isEmpty {
                    HStack {
                        Text("Due Date")
                        Spacer()
                        Text(dueDate)
                            .foregroundColor(.secondary)
                    }
                }
                if let status = assignment.completion_status, !status.isEmpty {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(status)
                            .foregroundColor(status == "Not Turned In" ? .red : .secondary)
                    }
                }
            }

            if let notes = assignment.assignment_notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .navigationTitle(assignment.assignment_description)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if assignment.is_unread == 1 {
                Task { await appInfo.markAssignmentAsRead(scoreID: assignment.score_id) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let renderer = ImageRenderer(content: GradeShareCard(assignment: assignment, courseName: courseName))
                    renderer.scale = 3
                    if let image = renderer.uiImage {
                        shareImage = IdentifiableImage(image: image)
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image])
        }
    }
}
