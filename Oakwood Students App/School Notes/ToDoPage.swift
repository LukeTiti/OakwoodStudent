//
//  ToDoPage.swift
//  School Notes
//
//  Created by Luke Titi on 10/1/25.
//
import SwiftUI
import SwiftSoup
import WebKit

struct ToDoPage: View {
    @State var errorMessage = ""
    @EnvironmentObject var appInfo: AppInfo
    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd"
        return f
    }()
    @State var infoSheet = false
    @State var currentAssignment: Assignment? = nil

    // Safely build the header for the "day after tomorrow"
    private var dayAfterTomorrowHeader: String {
        if let day2 = Calendar.current.date(byAdding: .day, value: 2, to: Date()) {
            let weekday = day2.formatted(.dateTime.weekday(.wide))
            return "\(weekday)'s Assignments"
        } else {
            return "Upcoming Assignments"
        }
    }

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                Text("⚠️ \(errorMessage)")
                    .foregroundColor(.red)
            }
            Section(header: Text("Today's Assignments")) {
                ForEach(appInfo.courses) { course in
                    ForEach(course.assignments ?? [], id: \.score_id) { assignment in
                        if appInfo.info[assignment.score_id, default: false] == false {
                            if let due = assignment.due_date,
                               due.contains("\(formatter.string(from: Date()))") {
                                ShowAssignment(assignment: assignment, courseName: course.class_name)
                            }
                        }
                    }
                }
            }
            Section(header: Text("Tomorrow's Assignments")) {
                ForEach(appInfo.courses) { course in
                    ForEach(course.assignments ?? [], id: \.score_id) { assignment in
                        if appInfo.info[assignment.score_id, default: false] == false {
                            if let due = assignment.due_date,
                               let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                               due.contains("\(formatter.string(from: tomorrow))") {
                                ShowAssignment(assignment: assignment, courseName: course.class_name)
                            }
                        }
                    }
                }
            }
            Section(header: Text(dayAfterTomorrowHeader)) {
                ForEach(appInfo.courses) { course in
                    ForEach(course.assignments ?? [], id: \.score_id) { assignment in
                        if appInfo.info[assignment.score_id, default: false] == false {
                            if let due = assignment.due_date,
                               let tomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                               due.contains("\(formatter.string(from: tomorrow))") {
                                ShowAssignment(assignment: assignment, courseName: course.class_name)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("To Do")
        .onAppear {
            // Load assignments for each course, then initialize completion info
            let courseIDs = appInfo.courses.compactMap { $0.enrollment_pk }
            for courseID in courseIDs {
                Task {
                    await loadAssignments(courseID: courseID)
                    
                    // After loading, find assignments for this course safely
                    let loadedAssignments = self.appInfo.courses.first(where: { $0.enrollment_pk == courseID })?.assignments ?? []
                    
                    await MainActor.run {
                        for assignment in loadedAssignments {
                            if let raw = assignment.raw_score, !raw.isEmpty {
                                appInfo.info[assignment.score_id] = true
                            } else if assignment.completion_status == "Not Turned In",
                                      appInfo.info[assignment.score_id] == nil {
                                appInfo.info[assignment.score_id] = false
                            }
                        }
                        // Force SwiftUI to notice the change if needed
                        appInfo.info = appInfo.info
                    }
                }
            }
        }
    }
    func loadAssignments(courseID: Int) async {
        guard let url = URL(string: "https://portals-embed.veracross.com/oakwood/student/enrollment/\(courseID)/assignments") else {
            await MainActor.run {
                errorMessage = "Invalid URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            
            guard status == 200 else {
                await MainActor.run {
                    errorMessage = "Server returned status \(status)"
                }
                return
            }
            
            // Ensure JSON, not HTML
            guard isJSONResponse(response, data: data) else {
                await MainActor.run {
                    errorMessage = "Not authenticated. Please log in."
                }
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(AssignmentResponse.self, from: data)
                await MainActor.run {
                    if let idx = self.appInfo.courses.firstIndex(where: { $0.enrollment_pk == courseID }) {
                        self.appInfo.courses[idx].assignments = decoded.assignments
                    }
                }
            } catch {
                let textPreview = String(data: data, encoding: .utf8) ?? "Unable to decode"
                await MainActor.run {
                    errorMessage = "Decoding error: \(error.localizedDescription)\nPreview: \(textPreview.prefix(200))"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
    }
    private func isJSONResponse(_ response: URLResponse?, data: Data) -> Bool {
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("application/json") {
            return true
        }
        // Fallback sniffing
        if let prefix = String(data: data.prefix(1), encoding: .utf8) {
            return prefix == "{" || prefix == "["
        }
        return false
    }
}


struct ShowAssignment: View {
    @State var assignment: Assignment?
    @EnvironmentObject var appInfo: AppInfo
    @State var courseName: String?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment?.assignment_description ?? "")
                        .font(.body)
                        .foregroundStyle(Color.primary)

                HStack {
                    let type = assignment?.assignment_type ?? ""
                    Text(type.isEmpty ? "?" : type)
                        .foregroundStyle(
                            type == "Test" || type == "Exam" ? Color.red :
                                type == "Quiz" ? Color.yellow :
                                type == "Homework" ? Color.blue : Color.green
                        )
                        .font(.caption)
                }
                if (courseName?.isEmpty) == false {
                    Text(courseName ?? "")
                        .font(.caption)
                }
            }
            Spacer()
            VStack {
                if let due = assignment?.due_date, !due.isEmpty {
                    Text("\(due)")
                }
                if (assignment?.completion_status == "Not Turned In") {
                    Text("NTI")
                        .foregroundColor(.red)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                appInfo.info[assignment?.score_id ?? 0] = !(appInfo.info[assignment?.score_id ?? 0] ?? false)
                appInfo.info = appInfo.info // force SwiftUI to see a change
            } label: {
                Label(
                    appInfo.info[assignment?.score_id ?? 0, default: false] ? "Mark Incomplete" : "Mark Complete",
                    systemImage: appInfo.info[assignment?.score_id ?? 0, default: false] ? "xmark.circle" : "checkmark.circle"
                )
            }
            .tint(appInfo.info[assignment?.score_id ?? 0, default: false] ? .orange : .green)
        }
    }
}

