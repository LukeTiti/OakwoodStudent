import Foundation
import SwiftUI
import WebKit
import SwiftSoup
import Combine
import Charts
import FirebaseFirestore
import CloudKit
import PDFKit

// MARK: - API Response Types

struct CoursesResponse: Codable {
    let courses: [Course]
}

struct AssignmentResponse: Codable {
    let assignments: [Assignment]
    let attachments: [Attachment]?
}

struct Attachment: Codable, Identifiable {
    var id: Int { file_pk }
    let assignment_id: Int
    let file_pk: Int
    let type: String
    let description: String
    let url: String
}

// MARK: - Core Models

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
    var _date: String?
    var completion_status: String?
    var is_unread: Int?
    var customCourseName: String?
    var attachments: [Attachment]?
}

// MARK: - Assignment Helpers

extension Assignment {
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var dueDate: Date? {
        if let full = _date, let date = Self.fullDateFormatter.date(from: full) {
            return date
        }
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

// MARK: - Badge View
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Sports Event
struct SportsEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
    let startTime: String
    let endTime: String
    let location: String
    let isAway: Bool
    let isCancelled: Bool
    let sportName: String
    let teamName: String

    var opponent: String {
        var opp = title
        opp = opp.replacingOccurrences(of: "\\s*\\((?:Away|Home|CANCELLED)\\)", with: "", options: .regularExpression)

        let colonComponents = opp.components(separatedBy: ": ")
        if colonComponents.count > 1 {
            opp = colonComponents.last ?? opp
        }

        if let vsRange = opp.range(of: "\\s+vs\\s+", options: .regularExpression) {
            opp = String(opp[vsRange.upperBound...])
        }

        return opp.trimmingCharacters(in: .whitespaces)
    }

    var timeText: String {
        endTime.isEmpty ? startTime : "\(startTime) - \(endTime)"
    }
}

// MARK: - School Event
struct SchoolEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let date: Date
    let startTime: String
    let endTime: String
    let location: String
    let description: String
    var category: String = "School Events"  // which school-level feed this came from — see schoolEventCalendars

    var timeText: String {
        endTime.isEmpty ? startTime : "\(startTime) - \(endTime)"
    }
}

// MARK: - Calendar Item (unified wrapper)
enum CalendarItem: Identifiable, Hashable {
    case sports(SportsEvent)
    case school(SchoolEvent)
    case personal(SchoolEvent)   // classes — only in My Day
    case practice(SchoolEvent)   // practice calendar — shown in main list

    var id: String {
        switch self {
        case .sports(let e): return e.id
        case .school(let e): return "school-\(e.id)"
        case .personal(let e): return "personal-\(e.id)"
        case .practice(let e): return "practice-\(e.id)"
        }
    }

    var date: Date {
        switch self {
        case .sports(let e): return e.date
        case .school(let e): return e.date
        case .personal(let e): return e.date
        case .practice(let e): return e.date
        }
    }

    var category: String {
        switch self {
        case .sports(let e): return e.sportName
        case .school(let e): return e.category
        case .personal: return "My Schedule"
        case .practice: return "Practices"
        }
    }
}

// MARK: - ServiceFormRow

struct ServiceFormRow: View {
    let form: SubmittedForm
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(form.title).font(.body.weight(.semibold))
                HStack(spacing: 4) {
                    Text("\(form.totalHours, specifier: "%.1f") hrs")
                    Text("·")
                    Text(form.submittedAt, style: .date)
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            ServiceStatusBadge(status: form.status)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Supervisor verification helpers

/// Loose, case/whitespace-insensitive comparison for flagging a mismatch between
/// what the student claimed (supervisor name/email) and what the signer actually
/// entered on the sign page — a cheap signal for the advisor, not proof of anything.
func looselyMatches(_ a: String, _ b: String) -> Bool {
    let na = a.trimmingCharacters(in: .whitespaces).lowercased()
    let nb = b.trimmingCharacters(in: .whitespaces).lowercased()
    return !na.isEmpty && na == nb
}

struct MatchIndicator: View {
    let matches: Bool
    var body: some View {
        Image(systemName: matches ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundColor(matches ? .green : .orange)
            .font(.caption)
    }
}

// MARK: - ServiceStatusBadge

struct ServiceStatusBadge: View {
    let status: String
    private var label: String {
        switch status {
        case "pending_signature": return "Awaiting Signature"
        case "signed": return "Signed"
        case "pending": return "Pending Approval"
        case "approved": return "Approved"
        case "rejected": return "Rejected"
        default: return status.capitalized
        }
    }
    private var color: Color {
        switch status {
        case "signed": return .blue
        case "pending": return .orange
        case "approved": return .green
        case "rejected": return .red
        default: return .secondary
        }
    }
    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Signature Image

/// Renders a supervisor's drawn signature, stored as a base64 PNG (optionally
/// a full `data:image/png;base64,...` URI) inside the Firestore form document.
struct SignatureImageView: View {
    let base64: String?

    var body: some View {
        if let image {
            image.resizable().scaledToFit()
        }
    }

    private var image: Image? {
        guard let base64 else { return nil }
        let payload: String
        if let commaIndex = base64.firstIndex(of: ",") {
            payload = String(base64[base64.index(after: commaIndex)...])
        } else {
            payload = base64
        }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return decodedImage(from: data)
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

// MARK: - Grade Detail Models

struct GradeTypeBreakdown: Identifiable {
    let id = UUID()
    let typeName: String
    let count: Int
    let pointsEarned: Double
    let pointsPossible: Double
    let average: Double
    let weight: Double?
}

struct GradeDetailResult {
    let semesterTitle: String
    let gradingMethod: String
    let ptdGrade: String
    let letterGrade: String
    let breakdown: [GradeTypeBreakdown]
}

// MARK: - Cross-Platform View Helpers

extension View {
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func largeNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macInsetListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset(alternatesRowBackgrounds: true))
        #else
        self
        #endif
    }

    @ViewBuilder
    func macRowPadding() -> some View {
        #if os(macOS)
        self.padding(.vertical, 8)
            .padding(.horizontal, 4)
        #else
        self
        #endif
    }

    @ViewBuilder
    func unreadRowBackground(_ isUnread: Int?) -> some View {
        if isUnread == 1 {
            self.listRowBackground(Color.yellow.opacity(0.15))
        } else {
            self
        }
    }
}

// MARK: - Link Detection

func linkedAttributedString(from text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return attributed
    }
    let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
    for match in matches {
        guard let url = match.url,
              let range = Range(match.range, in: text),
              let attrRange = Range(range, in: attributed) else { continue }
        attributed[attrRange].link = url
        attributed[attrRange].foregroundColor = .blue
    }
    return attributed
}

// MARK: - Resource Helpers

func attachmentIcon(for filename: String) -> String {
    let ext = (filename as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf":                          return "doc.richtext"
    case "doc", "docx":                  return "doc.text"
    case "ppt", "pptx":                  return "rectangle.on.rectangle"
    case "xls", "xlsx":                  return "tablecells"
    case "jpg", "jpeg", "png", "gif":    return "photo"
    case "mp4", "mov":                   return "video"
    case "mp3", "m4a":                   return "music.note"
    default:                             return "paperclip"
    }
}

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
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
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
            .inlineNavigationBarTitle()
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

// MARK: - Add Assignment Sheet

struct AddAssignmentSheet: View {
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedCourse = ""
    @State private var dueDate = Date()
    @State private var assignmentType = "Homework"
    @State private var notes = ""

    private let typeOptions = ["Homework", "Classwork", "Quiz", "Test", "Exam", "Other"]

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedCourse.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Course", selection: $selectedCourse) {
                        Text("Select a course").tag("")
                        ForEach(appInfo.courses) { course in
                            Text(course.class_name).tag(course.class_name)
                        }
                    }

                    TextField("Assignment Name", text: $name)

                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }

                Section {
                    Picker("Type", selection: $assignmentType) {
                        ForEach(typeOptions, id: \.self) { type in
                            HStack {
                                Badge(text: type, color: assignmentTypeColor(type))
                                Spacer()
                            }
                            .tag(type)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #endif
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Assignment")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        appInfo.addCustomAssignment(
                            courseName: selectedCourse,
                            description: name.trimmingCharacters(in: .whitespaces),
                            dueDate: dueDate,
                            type: assignmentType,
                            notes: notes.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}

// MARK: - NTI Assignment Row

struct NTIAssignmentRow: View {
    let assignment: Assignment
    let courseName: String
    @EnvironmentObject var appInfo: AppInfo

    private var isCompleted: Bool { appInfo.info[assignment.score_id, default: false] }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(assignment.assignment_description)
                        .font(.body)
                        .strikethrough(isCompleted, color: .secondary)
                        .foregroundColor(isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                HStack(spacing: 6) {
                    Text(courseName).font(.caption).foregroundColor(.secondary)
                    if let due = assignment.due_date, !due.isEmpty {
                        Text("·").foregroundColor(.secondary).font(.caption)
                        Text(due).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(isCompleted ? 0.7 : 1)
    }
}

// MARK: - Mail Composer Data

struct MailData {
    let to: String
    let subject: String
    let body: String
}

func makeSigningMailData(to email: String, supervisorName: String, studentName: String, title: String, totalHours: Double, signingURL: String) -> MailData {
    MailData(
        to: email,
        subject: "Please sign: \(title) — Service Hours Form",
        body: """
Hi \(supervisorName),

I'm requesting your signature for my community service hours form.

Activity: \(title)
Total Hours: \(String(format: "%.1f", totalHours))

Please click the link below to review the details and sign electronically:

\(signingURL)

Thank you,
\(studentName.isEmpty ? "Your Student" : studentName)
"""
    )
}

/// Builds a `mailto:` URL with prefilled subject/body, for platforms without an in-app mail composer.
func mailtoURL(_ data: MailData) -> URL? {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = data.to
    components.queryItems = [
        URLQueryItem(name: "subject", value: data.subject),
        URLQueryItem(name: "body", value: data.body)
    ]
    return components.url
}

// MARK: - PDF Viewer

#if os(iOS)
struct PDFViewer: UIViewRepresentable {
    let url: URL
    let appInfo: AppInfo
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true
        Task {
            await appInfo.restorePersistedCookiesIntoStores()
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let doc = PDFDocument(data: data) { await MainActor.run { v.document = doc } }
        }
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}
#elseif os(macOS)
struct PDFViewer: NSViewRepresentable {
    let url: URL
    let appInfo: AppInfo
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true
        Task {
            await appInfo.restorePersistedCookiesIntoStores()
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let doc = PDFDocument(data: data) { await MainActor.run { v.document = doc } }
        }
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}
#endif

// MARK: - Club Models

struct Club: Identifiable {
    var id: String
    var name: String
    var description: String
    var meetingDays: [String]
    var meetingFrequency: String
    var meetingTime: String
    var meetingLocation: String
    var editors: [String]
    var officers: [ClubOfficer]
    var themeID: String? = nil       // preset theme id (see ClubTheme.presets) — mutually exclusive with a custom image
    var hasCustomBackground: Bool = false  // if true, an image is stored in CloudKit under a "ClubBackground" record keyed by this club's id
    var backgroundVersion: Int = 0   // bumped on every re-upload so cached copies elsewhere know to refetch

    var meetingScheduleDisplay: String {
        var parts: [String] = []
        if !meetingDays.isEmpty {
            let days = meetingDays.joined(separator: " & ")
            parts.append(meetingFrequency == "Bi-weekly" ? "Bi-weekly · \(days)" : days)
        } else if meetingFrequency == "Varies" {
            parts.append("Varies")
        }
        if !meetingTime.isEmpty { parts.append(meetingTime) }
        return parts.joined(separator: " · ")
    }
}

struct ClubOfficer: Identifiable {
    var id: String
    var name: String
    var role: String
    var email: String
    var photoURL: String?
}

struct ClubEvent: Identifiable {
    var id: String
    var title: String
    var date: Date
    var location: String
    var description: String
}

struct ClubAnnouncement: Identifiable {
    var id: String
    var title: String
    var message: String
    var postedAt: Date
    var authorName: String
}

let superAdminEmail = "lukti28@oakwoodstudent.org"

// MARK: - Club Firestore Service

extension FirebaseService {
    private func clubRef(_ id: String) -> DocumentReference { db.collection("clubs").document(id) }
    private func eventsRef(_ clubId: String) -> CollectionReference { clubRef(clubId).collection("events") }
    private func announcementsRef(_ clubId: String) -> CollectionReference { clubRef(clubId).collection("announcements") }

    func fetchClubs() async throws -> [Club] {
        try await db.collection("clubs").getDocuments().documents.compactMap(parseClub).sorted { $0.name < $1.name }
    }

    func createClub(name: String, creatorEmail: String) async throws -> Club {
        let data: [String: Any] = ["name": name, "description": "", "meetingDays": [String](),
            "meetingFrequency": "Weekly", "meetingTime": "", "meetingLocation": "",
            "editors": [creatorEmail], "officers": []]
        let ref = try await db.collection("clubs").addDocument(data: data)
        return (try? parseClub(await ref.getDocument())) ?? Club(id: ref.documentID, name: name, description: "",
            meetingDays: [], meetingFrequency: "Weekly", meetingTime: "", meetingLocation: "",
            editors: [creatorEmail], officers: [])
    }

    func updateClub(_ club: Club) async throws {
        let data: [String: Any] = [
            "name": club.name, "description": club.description,
            "meetingDays": club.meetingDays, "meetingFrequency": club.meetingFrequency,
            "meetingTime": club.meetingTime, "meetingLocation": club.meetingLocation,
            "editors": club.editors,
            "officers": club.officers.map { o -> [String: Any] in
                var d: [String: Any] = ["id": o.id, "name": o.name, "role": o.role, "email": o.email]
                if let p = o.photoURL { d["photoURL"] = p }
                return d
            },
            "themeID": club.themeID ?? FieldValue.delete(),
            "hasCustomBackground": club.hasCustomBackground,
            "backgroundVersion": club.backgroundVersion
        ]
        try await clubRef(club.id).setData(data, merge: true)
    }

    func deleteClub(clubId: String) async throws {
        for doc in try await eventsRef(clubId).getDocuments().documents { try await doc.reference.delete() }
        for doc in try await announcementsRef(clubId).getDocuments().documents { try await doc.reference.delete() }
        try await clubRef(clubId).delete()
    }

    func fetchClubEvents(clubId: String) async throws -> [ClubEvent] {
        try await eventsRef(clubId).getDocuments().documents.compactMap { doc -> ClubEvent? in
            let d = doc.data()
            guard let title = d["title"] as? String, let date = (d["date"] as? Timestamp)?.dateValue() else { return nil }
            return ClubEvent(id: doc.documentID, title: title, date: date,
                             location: d["location"] as? String ?? "", description: d["description"] as? String ?? "")
        }.sorted { $0.date < $1.date }
    }

    func saveClubEvent(clubId: String, event: ClubEvent) async throws {
        let data: [String: Any] = ["title": event.title, "date": Timestamp(date: event.date),
                                   "location": event.location, "description": event.description]
        if event.id.isEmpty { try await eventsRef(clubId).addDocument(data: data) }
        else { try await eventsRef(clubId).document(event.id).setData(data) }
    }

    func deleteClubEvent(clubId: String, eventId: String) async throws {
        try await eventsRef(clubId).document(eventId).delete()
    }

    func fetchClubAnnouncements(clubId: String) async throws -> [ClubAnnouncement] {
        try await announcementsRef(clubId).getDocuments().documents.compactMap { doc -> ClubAnnouncement? in
            let d = doc.data()
            guard let title = d["title"] as? String, let posted = (d["postedAt"] as? Timestamp)?.dateValue() else { return nil }
            return ClubAnnouncement(id: doc.documentID, title: title, message: d["message"] as? String ?? "",
                                    postedAt: posted, authorName: d["authorName"] as? String ?? "")
        }.sorted { $0.postedAt > $1.postedAt }
    }

    func saveClubAnnouncement(clubId: String, ann: ClubAnnouncement) async throws {
        let data: [String: Any] = ["title": ann.title, "message": ann.message,
                                   "postedAt": Timestamp(date: ann.postedAt), "authorName": ann.authorName]
        try await announcementsRef(clubId).addDocument(data: data)
    }

    func deleteClubAnnouncement(clubId: String, announcementId: String) async throws {
        try await announcementsRef(clubId).document(announcementId).delete()
    }

    private func parseClub(_ doc: DocumentSnapshot) -> Club? {
        guard let d = doc.data(), let name = d["name"] as? String else { return nil }
        let officers = (d["officers"] as? [[String: Any]] ?? []).compactMap { o -> ClubOfficer? in
            guard let name = o["name"] as? String, let role = o["role"] as? String else { return nil }
            return ClubOfficer(id: o["id"] as? String ?? UUID().uuidString, name: name, role: role,
                               email: o["email"] as? String ?? "", photoURL: o["photoURL"] as? String)
        }
        let meetingDays: [String] = (d["meetingDays"] as? [String]) ??
            ((d["meetingDay"] as? String).map { $0.isEmpty ? [] : [$0] } ?? [])
        return Club(id: doc.documentID, name: name, description: d["description"] as? String ?? "",
                    meetingDays: meetingDays, meetingFrequency: d["meetingFrequency"] as? String ?? "Weekly",
                    meetingTime: d["meetingTime"] as? String ?? "", meetingLocation: d["meetingLocation"] as? String ?? "",
                    editors: d["editors"] as? [String] ?? [], officers: officers,
                    themeID: d["themeID"] as? String, hasCustomBackground: d["hasCustomBackground"] as? Bool ?? false,
                    backgroundVersion: d["backgroundVersion"] as? Int ?? 0)
    }
}

// MARK: - Club Theme

struct ClubTheme: Identifiable {
    let id: String
    let name: String
    let colors: [Color]

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let presets: [ClubTheme] = [
        ClubTheme(id: "sunset", name: "Sunset", colors: [Color(red: 1.00, green: 0.49, blue: 0.37), Color(red: 0.99, green: 0.71, blue: 0.48)]),
        ClubTheme(id: "ocean", name: "Ocean", colors: [Color(red: 0.02, green: 0.51, blue: 0.71), Color(red: 0.29, green: 0.79, blue: 0.85)]),
        ClubTheme(id: "forest", name: "Forest", colors: [Color(red: 0.13, green: 0.45, blue: 0.27), Color(red: 0.42, green: 0.68, blue: 0.35)]),
        ClubTheme(id: "grape", name: "Grape", colors: [Color(red: 0.42, green: 0.13, blue: 0.55), Color(red: 0.65, green: 0.34, blue: 0.83)]),
        ClubTheme(id: "midnight", name: "Midnight", colors: [Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.25, green: 0.29, blue: 0.48)]),
        ClubTheme(id: "coral", name: "Coral", colors: [Color(red: 0.98, green: 0.42, blue: 0.42), Color(red: 0.99, green: 0.62, blue: 0.62)]),
        ClubTheme(id: "gold", name: "Gold", colors: [Color(red: 0.85, green: 0.65, blue: 0.13), Color(red: 0.96, green: 0.82, blue: 0.40)]),
        ClubTheme(id: "slate", name: "Slate", colors: [Color(red: 0.30, green: 0.34, blue: 0.39), Color(red: 0.55, green: 0.60, blue: 0.65)]),
        ClubTheme(id: "rose", name: "Rose", colors: [Color(red: 0.85, green: 0.20, blue: 0.45), Color(red: 0.98, green: 0.55, blue: 0.70)]),
        ClubTheme(id: "teal", name: "Teal", colors: [Color(red: 0.00, green: 0.50, blue: 0.50), Color(red: 0.35, green: 0.78, blue: 0.75)]),
        ClubTheme(id: "indigo", name: "Indigo", colors: [Color(red: 0.29, green: 0.24, blue: 0.63), Color(red: 0.55, green: 0.48, blue: 0.85)]),
        ClubTheme(id: "crimson", name: "Crimson", colors: [Color(red: 0.70, green: 0.11, blue: 0.15), Color(red: 0.90, green: 0.30, blue: 0.30)]),
        ClubTheme(id: "mint", name: "Mint", colors: [Color(red: 0.15, green: 0.65, blue: 0.50), Color(red: 0.55, green: 0.90, blue: 0.75)]),
        ClubTheme(id: "amber", name: "Amber", colors: [Color(red: 0.90, green: 0.45, blue: 0.05), Color(red: 0.99, green: 0.65, blue: 0.30)]),
        ClubTheme(id: "steel", name: "Steel", colors: [Color(red: 0.20, green: 0.35, blue: 0.50), Color(red: 0.45, green: 0.60, blue: 0.75)]),
        ClubTheme(id: "plum", name: "Plum", colors: [Color(red: 0.35, green: 0.15, blue: 0.30), Color(red: 0.60, green: 0.35, blue: 0.55)]),
    ]

    static func preset(id: String?) -> ClubTheme? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}

struct ThemeSwatchButton: View {
    let gradient: LinearGradient?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let gradient {
                    Circle().fill(gradient)
                } else {
                    Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(gradient == nil ? .secondary : .white)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}

/// Fetches + displays a club's custom background image, stored as a CKAsset in
/// CloudKit's public database (record type "ClubBackground", keyed by club id).
/// Blank while loading or if the club has no custom image — callers that need a
/// fallback (theme color, neutral gray) decide that themselves.
struct ClubCloudImage: View {
    let clubId: String
    var version: Int = 0  // bump Club.backgroundVersion on re-upload so .task(id:) refetches instead of showing a stale cached copy
    var contentMode: ContentMode = .fit  // .fit shows the whole uploaded picture (banners); .fill crops to fill a fixed shape (swatches)

    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = decodedImage(from: imageData) {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: version) { await load() }
    }

    private func load() async {
        let key = "clubBackground-\(clubId)-\(version)"
        if let cached = ImageDataCache.shared.data(for: key) { imageData = cached; return }
        guard let record = try? await CKContainer.default().publicCloudDatabase.record(for: CKRecord.ID(recordName: clubId)),
              let asset = record["image"] as? CKAsset, let fileURL = asset.fileURL,
              let data = try? Data(contentsOf: fileURL) else { return }
        ImageDataCache.shared.store(data, for: key)
        imageData = data
    }
}

/// Small rounded swatch for club list rows — image if the club has one, else theme
/// gradient, else neutral gray.
struct ClubSwatchView: View {
    let club: Club
    var size: CGFloat = 40

    var body: some View {
        Group {
            if club.hasCustomBackground {
                ClubCloudImage(clubId: club.id, version: club.backgroundVersion, contentMode: .fill)
            } else if let theme = ClubTheme.preset(id: club.themeID) {
                theme.gradient
            } else {
                Color.gray.opacity(0.12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 5))
    }
}

/// Downscales + JPEG-compresses an image before upload — caps club background images
/// around a couple hundred KB instead of shipping multi-MB camera photos, since this
/// gets fetched repeatedly by anyone viewing the club page.
func compressedImageData(from data: Data, maxDimension: CGFloat = 1200, quality: CGFloat = 0.7) -> Data? {
    #if os(iOS)
    guard let image = UIImage(data: data) else { return nil }
    let size = image.size
    let scale = min(1, maxDimension / max(size.width, size.height))
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    return resized.jpegData(compressionQuality: quality)
    #else
    guard let image = NSImage(data: data) else { return nil }
    let size = image.size
    let scale = min(1, maxDimension / max(size.width, size.height))
    let newSize = NSSize(width: size.width * scale, height: size.height * scale)
    let resized = NSImage(size: newSize)
    resized.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
    resized.unlockFocus()
    guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    #endif
}

/// Uploads (or replaces) a club's background image as a CKAsset in CloudKit's public
/// database, keyed by the club's own id — no separate URL to store or manage, any
/// device can fetch it later just by knowing the club id. Saving to an existing
/// record name overwrites it, so "replace" is just "upload again."
func uploadClubBackgroundImage(clubId: String, version: Int, imageData: Data) async throws {
    guard let compressed = compressedImageData(from: imageData) else {
        throw NSError(domain: "Club", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't process that image."])
    }
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
    try compressed.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let record = CKRecord(recordType: "ClubBackground", recordID: CKRecord.ID(recordName: clubId))
    record["image"] = CKAsset(fileURL: tempURL)
    // .changedKeys instead of the default .ifServerRecordUnchanged — this is a freshly
    // constructed local record with no change tag, so the default policy treats any
    // re-upload (replacing an existing background) as a conflict and rejects it.
    _ = try await CKContainer.default().publicCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    ImageDataCache.shared.store(compressed, for: "clubBackground-\(clubId)-\(version)")
}

// MARK: - Directory Models

struct DirectoryPerson: Identifiable {
    let id = UUID()
    let name: String
    let grade: String
    let photoURL: String?
    let studentEmail: String?
    let households: [DirectoryHousehold]

    var displayName: String {
        if let parenStart = name.firstIndex(of: "("),
           let parenEnd = name.firstIndex(of: ")") {
            let before = String(name[..<parenStart]).trimmingCharacters(in: .whitespaces)
            let after = String(name[name.index(after: parenEnd)...]).trimmingCharacters(in: .whitespaces)
            return "\(before) \(after)"
        }
        return name
    }
}

struct DirectoryHousehold: Identifiable {
    let id = UUID()
    let address: String?
    let contacts: [DirectoryContact]
}

struct DirectoryContact: Identifiable {
    let id = UUID()
    let name: String
    let phone: String?
    let email: String?
}

// MARK: - Directory Scraping

func fetchDirectoryPage1(queryItems: [URLQueryItem]) async -> ([DirectoryPerson], String?) {
    var components = URLComponents(string: "https://portals.veracross.com/oakwood/student/directory/1")!
    if !queryItems.isEmpty { components.queryItems = queryItems }
    guard let url = components.url,
          let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url).withDirectoryHeaders()),
          let html = String(data: data, encoding: .utf8),
          let doc = try? SwiftSoup.parse(html) else { return ([], nil) }

    let csrf = try? doc.select("meta[name=csrf-token]").first()?.attr("content")
    guard let entries = try? doc.select("div.directory-Entry"), !entries.isEmpty() else {
        return ([], csrf)
    }
    return (entries.array().compactMap { parseDirectoryEntry($0) }, csrf)
}

func fetchDirectoryPageN(page: Int, queryItems: [URLQueryItem], csrfToken: String) async -> [DirectoryPerson] {
    var components = URLComponents(string: "https://portals.veracross.com/oakwood/student/directory/1/directory_entries/\(page)")!
    if !queryItems.isEmpty { components.queryItems = queryItems }
    guard let url = components.url,
          let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url).withDirectoryHeaders(csrf: csrfToken)),
          let jsText = String(data: data, encoding: .utf8) else { return [] }

    let html = jsText
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\'", with: "'")
        .replacingOccurrences(of: "<\\/", with: "</")
        .replacingOccurrences(of: "\\n", with: "\n")

    guard let doc = try? SwiftSoup.parse(html),
          let entries = try? doc.select("div.directory-Entry"),
          !entries.isEmpty() else { return [] }
    return entries.array().compactMap { parseDirectoryEntry($0) }
}

private func parseDirectoryEntry(_ entry: Element) -> DirectoryPerson? {
    guard let name = try? entry.select("div.directory-Entry_Title").first()?.text().trimmingCharacters(in: .whitespaces),
          !name.isEmpty else { return nil }

    let grade = (try? entry.select("div.directory-Entry_Tag").first()?.text().trimmingCharacters(in: .whitespaces)) ?? ""

    let photoURL: String? = {
        guard let style = try? entry.select("div.directory-Entry_PersonPhoto--square").first()?.attr("style"),
              let start = style.range(of: "url("),
              let end = style.range(of: ")", range: start.upperBound..<style.endIndex) else { return nil }
        return String(style[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .replacingOccurrences(of: "&amp;", with: "&")
    }()

    let studentEmail: String? = {
        let email = try? entry.select("div.directory-Entry_Header a[href^=mailto]").first()?.text()
        return email?.isEmpty == false ? email : nil
    }()

    let households: [DirectoryHousehold] = {
        guard let sections = try? entry.select("div.directory-Entry_HouseholdSection").array() else { return [] }
        return sections.compactMap { section in
            let address: String? = {
                let text = (try? section.select("div.directory-Entry_FieldTitle").first()?.ownText().trimmingCharacters(in: .whitespaces)) ?? ""
                return text.isEmpty ? nil : text
            }()
            let contacts: [DirectoryContact] = ((try? section.select("div.ae-grid__item.item-md-6").array()) ?? []).compactMap { div in
                guard let parentName = try? div.select("div.directory-Entry_FieldTitle--blue").first()?.text().trimmingCharacters(in: .whitespaces),
                      !parentName.isEmpty else { return nil }
                let phone = (try? div.select("a[href^=tel]").first()?.text()).flatMap { $0.isEmpty ? nil : $0 }
                let email = (try? div.select("a[href^=mailto]").first()?.text()).flatMap { $0.isEmpty ? nil : $0 }
                return DirectoryContact(name: parentName, phone: phone, email: email)
            }
            guard address != nil || !contacts.isEmpty else { return nil }
            return DirectoryHousehold(address: address, contacts: contacts)
        }
    }()

    return DirectoryPerson(name: name, grade: grade, photoURL: photoURL, studentEmail: studentEmail, households: households)
}

private extension URLRequest {
    func withDirectoryHeaders(csrf: String? = nil) -> URLRequest {
        var r = self
        r.httpShouldHandleCookies = true
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = 15
        if let csrf {
            r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            r.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
            r.setValue("text/javascript, application/javascript", forHTTPHeaderField: "Accept")
        }
        return r
    }
}

// MARK: - External URL Helper

func openExternalURL(_ string: String) {
    guard let url = URL(string: string) else { return }
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
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
    @State private var selectedSemester = 2

    private var gradeHistory: [GradePoint] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let semesterStart = cal.date(from: DateComponents(year: currentYear, month: 1, day: 1))!

        let graded = assignments
            .compactMap { a -> (date: Date, earned: Double, possible: Double, name: String, score: String)? in
                guard let date = a.dueDate,
                      let max = a.maximum_score, max > 0 else { return nil }
                if let earned = Double(a.raw_score ?? "") {
                    return (date, earned, Double(max), a.assignment_description, "\(a.raw_score!)/\(max)")
                } else if a.completion_status?.caseInsensitiveCompare("Not Turned In") == .orderedSame {
                    return (date, 0.0, Double(max), a.assignment_description, "NTI/\(max)")
                }
                return nil
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
                ? (cal.date(byAdding: .hour, value: sameDayCount * 4, to: item.date) ?? item.date)
                : item.date

            points.append(GradePoint(date: plotDate, percent: pct, name: item.name, score: item.score))
        }

        return points
    }

    private var sem1Points: [GradePoint] {
        guard let splitIdx = gradeHistory.firstIndex(where: { $0.isSemesterStart }) else {
            return gradeHistory
        }
        return Array(gradeHistory[..<splitIdx])
    }

    private var sem2Points: [GradePoint] {
        guard let splitIdx = gradeHistory.firstIndex(where: { $0.isSemesterStart }) else {
            return []
        }
        return Array(gradeHistory[(splitIdx + 1)...])
    }

    private var hasBothSemesters: Bool { !sem1Points.isEmpty && !sem2Points.isEmpty }

    private var displayedPoints: [GradePoint] {
        hasBothSemesters && selectedSemester == 1 ? sem1Points : sem2Points.isEmpty ? sem1Points : sem2Points
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
                if hasBothSemesters {
                    Picker("Semester", selection: $selectedSemester) {
                        Text("Semester 1").tag(1)
                        Text("Semester 2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSemester) { _, _ in selectedPoint = nil }
                }

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
                        let gradedCount = displayedPoints.filter { $0.score.contains("/") }.count
                        Text("\(gradedCount) graded assignment\(gradedCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .frame(height: 18)
                .animation(.easeInOut(duration: 0.1), value: selectedPoint?.name)

                GradeChartView(points: displayedPoints, selectedPoint: $selectedPoint)
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

        Chart {
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

// MARK: - Veracross Login

enum GradesLoginState {
    case checking, needsLogin, loggedIn
}

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

// MARK: - Cookie Sync

func syncCookies() async {
    let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    for cookie in cookies {
        HTTPCookieStorage.shared.setCookie(cookie)
    }
}

// MARK: - Image Cache

func preloadScoopImages() async {
    guard let data = UserDefaults.standard.data(forKey: "cachedScoopItems"),
          let items = try? JSONDecoder().decode([ScoopItem].self, from: data) else { return }
    await withTaskGroup(of: Void.self) { group in
        for item in items {
            guard let url = URL(string: item.image) else { continue }
            let key = url.absoluteString
            guard ImageDataCache.shared.data(for: key) == nil else { continue }
            group.addTask {
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                ImageDataCache.shared.store(data, for: key)
            }
        }
    }
}

func decodedImage(from data: Data) -> Image? {
    #if os(iOS)
    guard let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
    #else
    guard let ns = NSImage(data: data) else { return nil }
    return Image(nsImage: ns)
    #endif
}

private class ImageDataCache {
    static let shared = ImageDataCache()
    private let cache = NSCache<NSString, NSData>()
    func data(for url: String) -> Data? { cache.object(forKey: url as NSString) as Data? }
    func store(_ data: Data, for url: String) { cache.setObject(data as NSData, forKey: url as NSString) }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var imageData: Data?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        if let url = url, let cached = ImageDataCache.shared.data(for: url.absoluteString) {
            _imageData = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let data = imageData, let image = decodedImage(from: data) {
                content(image)
            } else {
                placeholder()
                    .task { await load() }
            }
        }
    }

    private func load() async {
        guard let url = url else { return }
        let key = url.absoluteString
        if let cached = ImageDataCache.shared.data(for: key) {
            imageData = cached; return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        ImageDataCache.shared.store(data, for: key)
        await MainActor.run { imageData = data }
    }
}

struct ScoopItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let date: String
    let link: String
    var image: String

    init(title: String, date: String, link: String, image: String) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.link = link
        self.image = image
    }
}

// Decodes items inside the HTML data-image-sizes attribute
// Example element: { "url": "https://...", "width": 640 }
private struct ImageSizeEntry: Decodable {
    let url: String
    let width: Int?
}

class ScoopViewModel: ObservableObject {
    @Published var items: [ScoopItem] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: "cachedScoopItems"),
           let cached = try? JSONDecoder().decode([ScoopItem].self, from: data) {
            items = cached
        }
    }

    private func saveItems(_ items: [ScoopItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "cachedScoopItems")
        }
    }

    func fetchScoop(tag: String) async {
        guard let url = URL(string: "https://www.oakwoodway.org/inside-scoop?tag_id=\(tag)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html),
              let posts = try? doc.select("a.fsThumbnail.fsPostLink") else { return }

        var newItems: [ScoopItem] = []
        for post in posts {
            guard let link = try? post.attr("href"),
                  let div = try? post.select("div.fsCroppedImage").first() else { continue }
            let title = (try? div.attr("title")) ?? "No Title"
            let imageURL: String = {
                let raw = (try? div.attr("data-image-sizes")) ?? ""
                guard !raw.isEmpty else { return "" }
                let unescaped = raw.replacingOccurrences(of: "&quot;", with: "\"")
                if let data = unescaped.data(using: .utf8),
                   let entries = try? JSONDecoder().decode([ImageSizeEntry].self, from: data) {
                    return (entries.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }) ?? entries.first)?.url ?? ""
                }
                let tail = unescaped.range(of: "https:").map { unescaped[$0.lowerBound...] }
                if let tail, let endQuote = tail.firstIndex(of: "\"") { return String(tail[..<endQuote]) }
                return ""
            }()
            newItems.append(ScoopItem(
                title: title,
                date: "",
                link: link.starts(with: "http") ? link : "https://www.oakwoodway.org\(link)",
                image: imageURL
            ))
        }
        items = newItems
        saveItems(newItems)
    }


}
