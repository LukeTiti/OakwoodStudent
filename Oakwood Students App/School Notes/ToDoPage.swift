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
                await appInfo.loadResourceAssignmentIds()
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
                    if let id = assignment.assignment_id, appInfo.resourceAssignmentIds.contains(id) {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundColor(.blue)
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
    @State private var resources: [FirebaseService.AssignmentResource] = []
    @State private var showAddResource = false

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

            Section {
                ForEach(resources) { resource in
                    Button {
                        if let url = URL(string: resource.url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: resourceIcon(for: resource.type))
                                .foregroundColor(resourceColor(for: resource.type))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.title)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text("Added by \(resource.addedByName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if resource.addedBy == appInfo.googleVM.userEmail {
                            Button(role: .destructive) {
                                Task {
                                    try? await FirebaseService.shared.deleteResource(documentId: resource.id)
                                    loadResources()
                                    await appInfo.loadResourceAssignmentIds()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showAddResource = true
                } label: {
                    Label("Add Resource", systemImage: "plus.circle")
                }
            } header: {
                Text("Resources")
            }
        }
        .navigationTitle(assignment.assignment_description)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if assignment.is_unread == 1 {
                Task { await appInfo.markAssignmentAsRead(scoreID: assignment.score_id) }
            }
            loadResources()
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
        .sheet(isPresented: $showAddResource) {
            AddResourceSheet(assignmentId: assignment.assignment_id ?? 0, appInfo: appInfo) {
                loadResources()
                Task { await appInfo.loadResourceAssignmentIds() }
            }
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

// MARK: - Resource Helpers
func resourceIcon(for type: String) -> String {
    switch type {
    case "quizlet": return "rectangle.stack"
    case "kahoot": return "gamecontroller"
    case "youtube": return "play.rectangle"
    default: return "link"
    }
}

func resourceColor(for type: String) -> Color {
    switch type {
    case "quizlet": return .purple
    case "kahoot": return .green
    case "youtube": return .red
    default: return .blue
    }
}

// MARK: - Add Resource Sheet
struct AddResourceSheet: View {
    let assignmentId: Int
    let appInfo: AppInfo
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State private var isSubmitting = false

    private var detectedType: String {
        FirebaseService.detectResourceType(from: url)
    }

    private var canSubmit: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL (required)", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Title (optional)", text: $title)
                } footer: {
                    if !url.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: resourceIcon(for: detectedType))
                                .foregroundColor(resourceColor(for: detectedType))
                            Text("Detected: \(detectedType.capitalized)")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Resource")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        let trimmedUrl = url.trimmingCharacters(in: .whitespaces)
        let resourceTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? trimmedUrl
            : title.trimmingCharacters(in: .whitespaces)

        Task {
            try? await FirebaseService.shared.submitResource(
                assignmentId: assignmentId,
                url: trimmedUrl,
                title: resourceTitle,
                userEmail: appInfo.googleVM.userEmail,
                userName: appInfo.googleVM.userName
            )
            onSubmit()
            dismiss()
        }
    }
}
