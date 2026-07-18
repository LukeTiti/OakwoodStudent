//
//  Mac_ToDoView.swift
//  School Notes
//
//  Created by Luke Titi on 6/18/26.
//
import SwiftUI

struct Mac_ToDoView: View {
    @EnvironmentObject var appInfo: AppInfo
    @AppStorage("hasMarkedPastAssignments") private var hasMarkedPastAssignments = false

    @State private var showAll = false
    @State private var showAddAssignment = false
    @State private var showNTIs = false
    @State private var errorMessage = ""

    private let daysAhead = 10

    private var allPairs: [(assignment: Assignment, courseName: String)] {
        let veracross = appInfo.courses.flatMap { course in
            (course.assignments ?? []).map { ($0, course.class_name) }
        }
        let custom = appInfo.customAssignments.map { ($0, $0.customCourseName ?? "Custom") }
        return veracross + custom
    }

    private var filteredAssignments: [(assignment: Assignment, courseName: String)] {
        showAll ? allPairs : allPairs.filter { appInfo.info[$0.assignment.score_id, default: false] == false }
    }

    private var pastDueAssignments: [(assignment: Assignment, courseName: String)] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allPairs
            .filter { appInfo.info[$0.assignment.score_id, default: false] == false }
            .filter { ($0.assignment.dueDate ?? .distantFuture) < startOfToday }
    }

    private var ntiAssignments: [(assignment: Assignment, courseName: String)] {
        allPairs
            .filter { $0.assignment.completion_status?.caseInsensitiveCompare("Not Turned In") == .orderedSame }
            .sorted { ($0.assignment.dueDate ?? .distantFuture) > ($1.assignment.dueDate ?? .distantFuture) }
    }

    private func assignmentsDue(dayOffset: Int) -> [(assignment: Assignment, courseName: String)] {
        guard let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) else { return [] }
        let due = filteredAssignments.filter { Calendar.current.isDate($0.assignment.dueDate ?? .distantFuture, inSameDayAs: targetDate) }
        return sortedByCompletion(due)
    }

    private func sortedByCompletion(_ pairs: [(assignment: Assignment, courseName: String)]) -> [(assignment: Assignment, courseName: String)] {
        pairs.sorted { lhs, rhs in
            let lhsDone = appInfo.info[lhs.assignment.score_id, default: false]
            let rhsDone = appInfo.info[rhs.assignment.score_id, default: false]
            return !lhsDone && rhsDone
        }
    }

    private func columnTitle(for dayOffset: Int) -> String {
        switch dayOffset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            return Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())
                .map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 16) {
                if !pastDueAssignments.isEmpty {
                    Mac_DayColumn(title: "Past Due", titleColor: .red, assignments: pastDueAssignments)
                }
                ForEach(0..<daysAhead, id: \.self) { offset in
                    Mac_DayColumn(title: columnTitle(for: offset), titleColor: .primary, assignments: assignmentsDue(dayOffset: offset))
                }
            }
            .padding()
        }
        .navigationTitle("To Do")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(showAll ? "Hide Done" : "Show All") {
                    withAnimation { showAll.toggle() }
                }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button("NTIs") { showNTIs = true }
                    .foregroundColor(.orange)
                Button {
                    showAddAssignment = true
                } label: {
                    Label("Add Assignment", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddAssignment) {
            AddAssignmentSheet()
                .environmentObject(appInfo)
                .frame(minWidth: 420, minHeight: 380)
        }
        .sheet(isPresented: $showNTIs) {
            Mac_NTIListSheet(assignments: ntiAssignments)
                .environmentObject(appInfo)
                .frame(minWidth: 420, minHeight: 380)
        }
        .overlay(alignment: .top) {
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
            }
        }
        .onAppear { Task { await loadData() } }
    }

    private func loadData() async {
        if !appInfo.isBundledMode {
            await appInfo.restorePersistedCookiesIntoStores()
            await syncCookies()
        }
        if appInfo.courses.isEmpty {
            if let err = await appInfo.loadCourses() {
                errorMessage = err
                return
            }
        }
        if !appInfo.isBundledMode {
            if let err = await appInfo.loadAllAssignments() {
                errorMessage = err
            }
        }
        await appInfo.loadResourceAssignmentIds()
        if !appInfo.isBundledMode && !hasMarkedPastAssignments {
            appInfo.markPastAssignmentsCompleted()
            hasMarkedPastAssignments = true
        }
    }
}

// MARK: - Day Column

private struct Mac_DayColumn: View {
    let title: String
    let titleColor: Color
    let assignments: [(assignment: Assignment, courseName: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(titleColor)
            ForEach(assignments, id: \.assignment.score_id) { item in
                Mac_AssignmentCard(assignment: item.assignment, courseName: item.courseName)
            }
        }
        .frame(width: 220, alignment: .top)
    }
}

// MARK: - Assignment Card

private struct Mac_AssignmentCard: View {
    let assignment: Assignment
    let courseName: String
    @EnvironmentObject var appInfo: AppInfo
    @State private var showDetail = false

    private var isComplete: Bool { appInfo.info[assignment.score_id, default: false] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                let type = assignment.assignment_type ?? ""
                Badge(text: type.isEmpty ? "Unknown" : type, color: assignmentTypeColor(type))
                Spacer()
                completionControl
            }
            Text(assignment.assignment_description)
                .font(.callout)
                .foregroundStyle(isComplete ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !courseName.isEmpty {
                Text(courseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isComplete ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail) {
            Mac_AssignmentDetailView(assignment: assignment, courseName: courseName)
                .frame(width: 340)
        }
    }

    // MARK: Mark-complete control
    //
    // Filled green checkmark when complete, grey outline when not.
    // Nested inside a plain `.onTapGesture` (not a Button) card so this
    // button intercepts its own taps instead of also opening the detail popover.
    @ViewBuilder
    private var completionControl: some View {
        Button {
            withAnimation(.snappy) {
                appInfo.toggleInfo(for: assignment.score_id)
            }
        } label: {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Assignment Detail (popover)

struct Mac_AssignmentDetailView: View {
    let assignment: Assignment
    var courseName: String = ""
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss

    @State private var resources: [FirebaseService.AssignmentResource] = []
    @State private var showAddResource = false

    private var isCustom: Bool { assignment.score_id < 0 }
    private var isComplete: Bool { appInfo.info[assignment.score_id, default: false] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(assignment.assignment_description)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let raw = assignment.raw_score, !raw.isEmpty, let percent = assignment.gradePercent {
                    HStack {
                        Text("\(raw) / \(assignment.maximum_score ?? 0)")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Text(percent, format: .percent.precision(.fractionLength(1)))
                            .font(.headline)
                            .foregroundColor(gradeColor(for: String(percent * 100)))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
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
                            Text(dueDate).foregroundStyle(.secondary)
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
                .font(.subheadline)

                if let notes = assignment.assignment_notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.subheadline.weight(.semibold))
                        Text(linkedAttributedString(from: notes))
                    }
                }

                if let attachments = assignment.attachments, !attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attachments").font(.subheadline.weight(.semibold))
                        ForEach(attachments) { attachment in
                            Button {
                                if let url = URL(string: attachment.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label(attachment.description, systemImage: attachmentIcon(for: attachment.description))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                }

                if !isCustom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Resources").font(.subheadline.weight(.semibold))
                        ForEach(resources) { resource in
                            HStack {
                                Button {
                                    if let url = URL(string: resource.url) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Label(resource.title, systemImage: resourceIcon(for: resource.type))
                                        .foregroundStyle(resourceColor(for: resource.type))
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if resource.addedBy == appInfo.googleVM.userEmail {
                                    Button(role: .destructive) {
                                        Task {
                                            try? await FirebaseService.shared.deleteResource(documentId: resource.id)
                                            loadResources()
                                            await appInfo.loadResourceAssignmentIds()
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button {
                            showAddResource = true
                        } label: {
                            Label("Add Resource", systemImage: "plus.circle")
                        }
                    }
                }

                Divider()

                HStack {
                    Button {
                        appInfo.toggleInfo(for: assignment.score_id)
                    } label: {
                        Label(
                            isComplete ? "Mark Incomplete" : "Mark Complete",
                            systemImage: isComplete ? "xmark.circle" : "checkmark.circle"
                        )
                    }
                    if isCustom {
                        Spacer()
                        Button(role: .destructive) {
                            appInfo.deleteCustomAssignment(scoreId: assignment.score_id)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if assignment.is_unread == 1 {
                Task { await appInfo.markAssignmentAsRead(scoreID: assignment.score_id) }
            }
            if !isCustom { loadResources() }
        }
        .sheet(isPresented: $showAddResource) {
            AddResourceSheet(assignmentId: assignment.assignment_id ?? 0, appInfo: appInfo) {
                loadResources()
                Task { await appInfo.loadResourceAssignmentIds() }
            }
            .frame(minWidth: 380, minHeight: 260)
        }
    }

    private func loadResources() {
        guard let assignmentId = assignment.assignment_id else { return }
        Task {
            if let fetched = try? await FirebaseService.shared.fetchResources(assignmentId: assignmentId) {
                resources = fetched
            }
        }
    }
}

// MARK: - NTI List Sheet

struct Mac_NTIListSheet: View {
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss
    let assignments: [(assignment: Assignment, courseName: String)]

    var body: some View {
        NavigationStack {
            Group {
                if assignments.isEmpty {
                    ContentUnavailableView("No NTI Assignments", systemImage: "checkmark.circle", description: Text("No assignments marked \"Not Turned In\" were found."))
                } else {
                    List {
                        ForEach(assignments, id: \.assignment.score_id) { item in
                            NavigationLink {
                                Mac_AssignmentDetailView(assignment: item.assignment, courseName: item.courseName)
                            } label: {
                                NTIAssignmentRow(assignment: item.assignment, courseName: item.courseName)
                            }
                        }
                    }
                }
            }
            .navigationTitle("NTI Assignments")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
