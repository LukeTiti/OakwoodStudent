//
//  Veracross.swift
//  School Notes
//
//  Created by Luke Titi on 9/17/25.
//
import SwiftUI
import SwiftSoup
import WebKit

// MARK: - Data Models
struct CoursesResponse: Codable {
    let courses: [Course]
}
struct AssignmentResponse: Codable {
    let assignments: [Assignment]
}

struct Course: Codable, Identifiable {
    var id: String { class_id }   // Use class_id as stable identifier
    
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
    var completed: Bool? = false
}

// MARK: - Main View
struct VeracrossGradesView: View {
    @State private var isLoggedIn = false
    @State private var courses: [Course] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            if !isLoggedIn {
                // Step 1: Login WebView
                VeracrossLoginView(
                    url: URL(string: "https://portals.veracross.com/oakwood/student")!,
                    onLogin: {
                        syncCookies {
                            Task {
                                await loadGrades()
                            }
                        }
                        isLoggedIn = true
                    }
                )
                .navigationTitle("Login to Veracross")
            } else {
                // Step 2: Show courses + grades
                NavigationStack {
                    List {
                        if let errorMessage = errorMessage {
                            Text("⚠️ \(errorMessage)")
                                .foregroundColor(.red)
                        }
                        
                        ForEach(courses) { course in
                            NavigationLink(destination: CourseView(course: course)) {
                                HStack {
                                    HStack() {
                                        Text(course.class_name)
                                            .font(.headline)
                                        Spacer()
                                        if let grade = course.ptd_grade {
                                            Text("\(grade)%")
                                                .bold()
                                        } else {
                                            Text("-")
                                                .foregroundColor(.gray)
                                        }
                                        if let letter = course.ptd_letter_grade {
                                            Text(letter.trimmingCharacters(in: .whitespaces))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Task { await loadGrades() }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .navigationTitle("My Grades")
                }
            }
        }
        .onAppear {
            // Minimal silent session check:
            // Sync cookies from WKWebView's persistent store, then try a quick call.
            syncCookies {
                Task {
                    let ok = await isSessionValid()
                    if ok {
                        await MainActor.run { isLoggedIn = true }
                        await loadGrades()
                    }
                }
            }
        }
    }

    // MARK: - Networking
    func loadGrades() async {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student/component/ClassListStudent/1308/load_data") else {
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
            
            // Ensure we actually got JSON (not an HTML login page)
            guard isJSONResponse(response, data: data) else {
                await MainActor.run {
                    errorMessage = "Not authenticated. Please log in."
                    isLoggedIn = false
                }
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(CoursesResponse.self, from: data)
                await MainActor.run {
                    self.courses = decoded.courses
                    self.errorMessage = nil
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
    
    // Lightweight session validation
    func isSessionValid() async -> Bool {
        guard let url = URL(string: "https://portals.veracross.com/oakwood/student/component/ClassListStudent/1308/load_data") else {
            return false
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else { return false }
            // Confirm the response is JSON, not an HTML login page
            return isJSONResponse(response, data: data)
        } catch {
            return false
        }
    }
    
    // Heuristic: treat as JSON if Content-Type contains "json",
    // or if body starts with "{" or "[". Otherwise likely HTML login.
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

struct CourseView: View {
    @State private var assignments: [Assignment] = []
    @State private var errorMessage: String?
    @State var course: Course?
    @State var infoSheet = false
    @State var currentAssignment: Assignment?
    
    var body: some View {
        List {
            if let errorMessage = errorMessage {
                Text("⚠️ \(errorMessage)")
                    .foregroundColor(.red)
            }
            ForEach(assignments.indices, id: \.self) { index in
                let assignment = assignments[index]
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action:{
                            infoSheet = true
                            currentAssignment = assignment
                        }){
                            Text(assignment.assignment_description ?? "No description")
                                .font(.body)
                        }
                        HStack {
                            if let due = assignment.due_date, !due.isEmpty {
                                Text("\(due)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(assignment.assignment_type ?? "?")")
                                .foregroundStyle(assignment.assignment_type == "Test" ? Color.red : assignment.assignment_type == "Exam" ? Color.red : assignment.assignment_type == "Quiz" ? Color.yellow : assignment.assignment_type == "Homework" ? Color.blue : Color.green )
                                .font(.caption)
                            Text("\(assignment.completed ?? false ? "Completed" : "Not completed")")
                                .font(.caption)
                            
                        }
                    }
                    Spacer()
                    VStack {
                        if assignment.raw_score == "" {
                            Text("Pending")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(assignment.raw_score ?? "") / \(assignment.maximum_score ?? 0)")
                                .foregroundColor(.secondary)
                            let score = Double(assignment.raw_score ?? "") ?? 0
                            let max = assignment.maximum_score ?? 0
                            let percent = score/Double(max)
                            Text(percent, format: .percent.precision(.fractionLength(2)))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        // Toggle completed locally
                        var updated = assignments[index]
                        updated.completed = !(updated.completed ?? false)
                        assignments[index] = updated
                    } label: {
                        Label((assignment.completed ?? false) ? "Mark Incomplete" : "Mark Complete",
                              systemImage: (assignment.completed ?? false) ? "xmark.circle" : "checkmark.circle")
                    }
                    .tint((assignment.completed ?? false) ? .orange : .green)
                }
            }
        }
        .navigationTitle("\(course?.class_name ?? "Unknown")")
        .onAppear {
            guard let course = course else { return }
            syncCookies {
                Task {
                    await loadAssignments(courseID: course.enrollment_pk ?? 0)
                }
            }
            for i in assignments.indices {
                if assignments[i].raw_score != "" {
                    assignments[i].completed = true
                }
            }
        }
        .sheet(isPresented: $infoSheet) {
            Text("\(currentAssignment?.assignment_description ?? "Unknown")")
                .font(.title)
            Text("\(currentAssignment?.assignment_notes ?? "Unknown")")
        }
    }
    
    // Keep assignments local to this view
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
                    self.assignments = decoded.assignments
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
    // MARK: - Response helpers
    func isJSONResponse(_ response: URLResponse?, data: Data) -> Bool {
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("application/json") {
            return true
        }
        if let firstChar = String(data: data.prefix(1), encoding: .utf8) {
            return firstChar == "{" || firstChar == "["
        }
        return false
    }
}

// MARK: - Login WebView
struct VeracrossLoginView: UIViewRepresentable {
    let url: URL
    var onLogin: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        // Explicitly use the persistent data store to help cookie persistence
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLogin: onLogin)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onLogin: () -> Void

        init(onLogin: @escaping () -> Void) {
            self.onLogin = onLogin
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Detect successful login by URL change
            if webView.url?.absoluteString.contains("/student") == true {
                onLogin()
            }
        }
    }
}

// MARK: - Cookie Sync
func syncCookies(completion: @escaping () -> Void) {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        completion()
    }
}
