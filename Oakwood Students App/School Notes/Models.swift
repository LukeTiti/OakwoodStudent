import Foundation
import SwiftUI
import WebKit
import SwiftSoup
import Combine
import Charts
import FirebaseFirestore
import CloudKit
import PDFKit
// Not iOS-guarded: UserNotifications/UNUserNotificationCenter works identically on macOS,
// and scheduleEventReminders/scheduleFollowedClubEventReminders below are used from both
// the iOS and macOS targets (unlike checkForNewClubAnnouncements, whose iOS-only body kept
// this import iOS-only previously).
import UserNotifications

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

// MARK: - Class Color
//
// SwiftUI's Color isn't reliably Codable across this project's deployment target, so a
// custom per-class color (see AppInfo.classColors) is stored as plain RGBA components
// instead — converts cleanly to/from Color on both iOS (UIColor) and macOS (NSColor).
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        #if os(iOS)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b); alpha = Double(a)
        #elseif os(macOS)
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        red = Double(ns.redComponent); green = Double(ns.greenComponent); blue = Double(ns.blueComponent); alpha = Double(ns.alphaComponent)
        #endif
    }
}

// MARK: - Onboarding Shared Data
//
// Shared between OnboardingView.swift (iOS, platform-filtered out of the macOS target)
// and Mac/Mac_OnboardingView.swift (macOS). Declared here — a file with no platform
// filter — so both targets see these as ordinary same-module symbols.

struct OnboardingFeature {
    let icon: String
    let color: Color
    let title: String
    let description: String
}

let onboardingFeatures: [OnboardingFeature] = [
    OnboardingFeature(
        icon: "newspaper.fill",
        color: .oakwoodGreen,
        title: "Inside Scoop",
        description: "Stay up to date with Oakwood news, campus announcements, and what's happening today."
    ),
    OnboardingFeature(
        icon: "list.bullet.rectangle.portrait.fill",
        color: .oakwoodGreen,
        title: "Grades & Assignments",
        description: "View your grades and upcoming assignments from Veracross — all in one place."
    ),
    OnboardingFeature(
        icon: "figure.run",
        color: .oakwoodGreen,
        title: "Sports",
        description: "Follow Oakwood sports schedules, live scores, and sign up to work games."
    ),
    OnboardingFeature(
        icon: "heart.fill",
        color: .oakwoodGreen,
        title: "Service & More",
        description: "Track your community service hours and access links and resources."
    ),
]

extension Color {
    static let oakwoodGreen = Color(red: 0.13, green: 0.55, blue: 0.27)
    static let oakwoodGreenLight = Color(red: 0.22, green: 0.78, blue: 0.40)
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

// MARK: - Segmented Hours Bar

/// A single progress bar split into two visibly distinct colored segments — outside-service
/// hours and the rest of a student's approved hours — instead of two separate bars. Both
/// segments size relative to the overall yearly requirement (not to each other), so the bar
/// only fills completely once the full requirement is met, not just the outside minimum.
struct SegmentedHoursBar: View {
    let outsideHours: Double
    let totalHours: Double
    let requiredTotal: Double

    private var otherHours: Double { max(totalHours - outsideHours, 0) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let outsideFraction = requiredTotal > 0 ? min(outsideHours / requiredTotal, 1) : 0
            let otherFraction = requiredTotal > 0 ? min(otherHours / requiredTotal, 1 - outsideFraction) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                HStack(spacing: 0) {
                    Color.orange.frame(width: width * outsideFraction)
                    Color.accentColor.frame(width: width * otherFraction)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }
}

/// Legend row for SegmentedHoursBar — color-matched labels for the outside and total figures,
/// meant to sit directly beside/under the bar they describe.
struct SegmentedHoursLegend: View {
    let outsideHours: Double
    let totalHours: Double

    // Deliberately uncapped — going over 100% (e.g. 210%) is fine and worth showing as-is
    // rather than clamping, unlike the bar itself which has to stop at its own container.
    private var totalPercent: Double {
        requiredServiceHoursPerYear > 0 ? (totalHours / requiredServiceHoursPerYear) * 100 : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Outside \(outsideHours, specifier: "%.1f")/\(requiredOutsideServiceHoursPerYear, specifier: "%.0f")")
            }
            HStack(spacing: 4) {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                Text("Total \(totalHours, specifier: "%.1f")/\(requiredServiceHoursPerYear, specifier: "%.0f") (\(totalPercent, specifier: "%.0f")%)")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundColor(.secondary)
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
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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

    /// Tints a List row with a class's chosen color (see AppInfo.classColor) — applied after
    /// `unreadRowBackground` at call sites so it takes priority when both would otherwise apply.
    @ViewBuilder
    func classColorRowBackground(_ color: Color?) -> some View {
        if let color {
            self.listRowBackground(color.opacity(0.18))
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

func makeSigningMailData(to email: String, studentName: String, title: String, totalHours: Double, signingURL: String) -> MailData {
    MailData(
        to: email,
        subject: "Please sign: \(title) — Service Hours Form",
        body: """
Hello,

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

/// Downloads the PDF at `url` (using the app's authenticated Veracross session, same as
/// PDFViewer below) and writes it to a local temp file. Sharing the remote URL directly doesn't
/// work for anyone but the signed-in student — it requires their own logged-in session to open —
/// so this gives the share sheet a real, standalone PDF file instead.
func downloadPDFForSharing(url: URL, appInfo: AppInfo) async -> URL? {
    await appInfo.restorePersistedCookiesIntoStores()
    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Service Record.pdf")
    do {
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    } catch {
        return nil
    }
}

// MARK: - Document Web View (zoomable, shares Veracross cookie store)
// Moved here from Veracross.swift (which is iOS-only platform-filtered in the Xcode
// project, so a macOS variant declared there would never actually compile into the Mac
// target — same class of bug as the earlier Color.oakwoodGreenLight one). Loads the URL
// directly in a real WKWebView rather than fetching bytes and forcing them through
// PDFDocument(data:) (see PDFViewer below) — some Veracross document endpoints (e.g.
// attendance) don't return clean PDF bytes to a bare URLSession fetch outside a real
// browser/navigation context, but render fine when actually loaded as a web page.
// Best-effort: some Veracross pages (e.g. a specific class's directory, which lives on
// classes.veracross.com — a different subdomain from portals.veracross.com, where we
// actually log in) return a bare "not found" when hit directly, cold, with just copied
// cookies — they seem to need an actual in-session click-through from an authenticated
// portals.veracross.com page to establish, rather than being reachable as a standalone
// authenticated URL. When `autoClickLinkContaining`/`matchHint` are set, this loads `url`
// (a known-good portals.veracross.com page) and then searches the loaded page for an <a>
// whose href contains `autoClickLinkContaining` and whose nearby row text contains
// `matchHint` (case-insensitive), clicking it programmatically to trigger a real
// in-session navigation to the target page. This is a heuristic over unknown page
// structure, not a guaranteed match.
class DocumentWebViewCoordinator: NSObject, WKNavigationDelegate {
    let autoClickLinkContaining: String?
    let matchHint: String?
    private var hasAttemptedClick = false

    init(autoClickLinkContaining: String?, matchHint: String?) {
        self.autoClickLinkContaining = autoClickLinkContaining
        self.matchHint = matchHint
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasAttemptedClick, let linkSubstring = autoClickLinkContaining, let hint = matchHint else { return }
        hasAttemptedClick = true
        let escapedLink = linkSubstring.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let escapedHint = hint.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var links = Array.from(document.querySelectorAll('a[href*="\(escapedLink)"]'));
            var hint = '\(escapedHint)'.toLowerCase();
            for (var i = 0; i < links.length; i++) {
                // Climb to the enclosing course list item, not just the immediate parent —
                // the course name lives in a sibling div (course-list-class), not inside the
                // same website-links wrapper as the link itself.
                var row = links[i].closest('li') || links[i].closest('.ae-grid') || links[i].parentElement;
                var text = ((row ? row.innerText : links[i].innerText) || '').toLowerCase();
                if (text.indexOf(hint) !== -1) {
                    links[i].removeAttribute('target');
                    links[i].click();
                    return true;
                }
            }
            return false;
        })();
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error { print("[DocumentWebView] auto-click JS failed: \(error)") }
            else { print("[DocumentWebView] auto-click matched a link: \(result ?? false)") }
        }
    }
}

#if os(iOS)
struct DocumentWebView: UIViewRepresentable {
    let url: URL
    var autoClickLinkContaining: String? = nil
    var matchHint: String? = nil

    func makeCoordinator() -> DocumentWebViewCoordinator {
        DocumentWebViewCoordinator(autoClickLinkContaining: autoClickLinkContaining, matchHint: matchHint)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 5.0
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#elseif os(macOS)
struct DocumentWebView: NSViewRepresentable {
    let url: URL
    var autoClickLinkContaining: String? = nil
    var matchHint: String? = nil

    func makeCoordinator() -> DocumentWebViewCoordinator {
        DocumentWebViewCoordinator(autoClickLinkContaining: autoClickLinkContaining, matchHint: matchHint)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

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

    func saveClubEvent(clubId: String, clubName: String, authorName: String, event: ClubEvent) async throws {
        let isNewEvent = event.id.isEmpty
        let data: [String: Any] = ["title": event.title, "date": Timestamp(date: event.date),
                                   "location": event.location, "description": event.description]
        if isNewEvent { try await eventsRef(clubId).addDocument(data: data) }
        else { try await eventsRef(clubId).document(event.id).setData(data) }
        // Best-effort: only pings followers for genuinely new events, never edits — mirrors
        // saveClubAnnouncement's use of touchClubActivity below.
        if isNewEvent {
            try? await touchClubActivity(clubId: clubId, clubName: clubName, announcementTitle: "New Event: \(event.title)", authorName: authorName)
        }
    }

    func deleteClubEvent(clubId: String, eventId: String) async throws {
        try await eventsRef(clubId).document(eventId).delete()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["event-\(eventId)-1hr", "event-\(eventId)-start"])
    }

    func fetchClubAnnouncements(clubId: String) async throws -> [ClubAnnouncement] {
        try await announcementsRef(clubId).getDocuments().documents.compactMap { doc -> ClubAnnouncement? in
            let d = doc.data()
            guard let title = d["title"] as? String, let posted = (d["postedAt"] as? Timestamp)?.dateValue() else { return nil }
            return ClubAnnouncement(id: doc.documentID, title: title, message: d["message"] as? String ?? "",
                                    postedAt: posted, authorName: d["authorName"] as? String ?? "")
        }.sorted { $0.postedAt > $1.postedAt }
    }

    func saveClubAnnouncement(clubId: String, clubName: String, ann: ClubAnnouncement) async throws {
        let data: [String: Any] = ["title": ann.title, "message": ann.message,
                                   "postedAt": Timestamp(date: ann.postedAt), "authorName": ann.authorName]
        try await announcementsRef(clubId).addDocument(data: data)
        // Best-effort: pings a lightweight CloudKit record so followers of this club get a
        // push notification via their CKQuerySubscription. Never blocks/fails the actual
        // announcement post, which is the primary action here.
        try? await touchClubActivity(clubId: clubId, clubName: clubName, announcementTitle: ann.title, authorName: ann.authorName)
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

/// Looks up every club officer role this person holds, matched by email (case-insensitive) since
/// names alone aren't reliably unique. Used by the Directory feature to surface a person's club
/// involvement on their profile — best-effort, returns empty on any failure or if the person has
/// no directory email on file.
func fetchClubRoles(forEmail email: String) async -> [(clubName: String, role: String)] {
    guard !email.isEmpty else { return [] }
    let clubs = (try? await FirebaseService.shared.fetchClubs()) ?? []
    return clubs.flatMap { club in
        club.officers.filter { $0.email.lowercased() == email.lowercased() }
            .map { (clubName: club.name, role: $0.role) }
    }
}

/// Every one of the current student's own classes (from `courses`) that also has `email`
/// enrolled, matched by studentEmail (case-insensitive) — same matching convention as
/// fetchClubRoles. Best-effort: returns empty on any failure, and if `email` is empty.
func fetchSharedClasses(withEmail email: String, courses: [Course]) async -> [String] {
    guard !email.isEmpty else { return [] }
    var shared: [String] = []
    for course in courses {
        let roster = await ClassRosterCache.shared.roster(for: course)
        if roster.contains(where: { ($0.studentEmail ?? "").caseInsensitiveCompare(email) == .orderedSame }) {
            shared.append(course.class_name)
        }
    }
    return shared
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
        ClubTheme(id: "sunset", name: "Sunset", colors: [Color(red: 0.80, green: 0.47, blue: 0.40), Color(red: 0.83, green: 0.64, blue: 0.49)]),
        ClubTheme(id: "ocean", name: "Ocean", colors: [Color(red: 0.12, green: 0.43, blue: 0.56), Color(red: 0.35, green: 0.67, blue: 0.71)]),
        ClubTheme(id: "forest", name: "Forest", colors: [Color(red: 0.15, green: 0.40, blue: 0.26), Color(red: 0.41, green: 0.61, blue: 0.36)]),
        ClubTheme(id: "grape", name: "Grape", colors: [Color(red: 0.36, green: 0.18, blue: 0.45), Color(red: 0.57, green: 0.37, blue: 0.69)]),
        // "Midnight" is the reference point everything else was toned down to match — leave unchanged.
        ClubTheme(id: "midnight", name: "Midnight", colors: [Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.25, green: 0.29, blue: 0.48)]),
        ClubTheme(id: "coral", name: "Coral", colors: [Color(red: 0.79, green: 0.43, blue: 0.43), Color(red: 0.83, green: 0.59, blue: 0.59)]),
        ClubTheme(id: "gold", name: "Gold", colors: [Color(red: 0.65, green: 0.54, blue: 0.24), Color(red: 0.77, green: 0.69, blue: 0.45)]),
        ClubTheme(id: "slate", name: "Slate", colors: [Color(red: 0.30, green: 0.34, blue: 0.39), Color(red: 0.55, green: 0.60, blue: 0.65)]),
        ClubTheme(id: "rose", name: "Rose", colors: [Color(red: 0.68, green: 0.26, blue: 0.42), Color(red: 0.82, green: 0.54, blue: 0.64)]),
        ClubTheme(id: "teal", name: "Teal", colors: [Color(red: 0.08, green: 0.41, blue: 0.41), Color(red: 0.38, green: 0.67, blue: 0.65)]),
        ClubTheme(id: "indigo", name: "Indigo", colors: [Color(red: 0.28, green: 0.25, blue: 0.51), Color(red: 0.51, green: 0.47, blue: 0.72)]),
        ClubTheme(id: "crimson", name: "Crimson", colors: [Color(red: 0.53, green: 0.16, blue: 0.18), Color(red: 0.70, green: 0.32, blue: 0.32)]),
        ClubTheme(id: "mint", name: "Mint", colors: [Color(red: 0.21, green: 0.51, blue: 0.42), Color(red: 0.53, green: 0.75, blue: 0.66)]),
        ClubTheme(id: "amber", name: "Amber", colors: [Color(red: 0.66, green: 0.40, blue: 0.17), Color(red: 0.77, green: 0.57, blue: 0.37)]),
        ClubTheme(id: "steel", name: "Steel", colors: [Color(red: 0.20, green: 0.35, blue: 0.50), Color(red: 0.45, green: 0.60, blue: 0.75)]),
        ClubTheme(id: "plum", name: "Plum", colors: [Color(red: 0.31, green: 0.16, blue: 0.27), Color(red: 0.53, green: 0.35, blue: 0.50)]),
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

// MARK: - Club Activity / Follow Notifications
//
// A single "ping" record per club (recordName = club id, so it's trivially upsertable)
// rather than one record per announcement — keeps this simple and avoids unbounded record
// growth. Followers subscribe with a CKQuerySubscription filtered to their club's id, so a
// create/update of this one record fires a push to everyone following that club.

/// Upserts the activity record for a club whenever it posts a new announcement. Uses
/// `.changedKeys` (not the default `.save`/`.ifServerRecordUnchanged` policy) since this
/// record already exists after the first post — see `uploadClubBackgroundImage` above for
/// the same lesson learned with club background images.
func touchClubActivity(clubId: String, clubName: String, announcementTitle: String, authorName: String) async throws {
    let record = CKRecord(recordType: "ClubActivity", recordID: CKRecord.ID(recordName: "club-activity-\(clubId)"))
    record["clubId"] = clubId
    record["clubName"] = clubName
    record["announcementTitle"] = announcementTitle
    record["authorName"] = authorName
    record["postedAt"] = Date()
    do {
        _ = try await CKContainer.default().publicCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        print("[ClubActivity] Touched activity record for club \(clubId) (\(clubName)), announcement: \"\(announcementTitle)\"")
    } catch {
        print("[ClubActivity] FAILED to touch activity record for club \(clubId) (\(clubName)), announcement: \"\(announcementTitle)\": \(error)")
        if let ckError = error as? CKError {
            print("[ClubActivity] CKError code: \(ckError.code.rawValue), description: \(ckError.localizedDescription)")
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                for (itemID, itemError) in partialErrors {
                    print("[ClubActivity] Partial error for item \(itemID): \(itemError)")
                }
            }
        }
        // Preserve existing behavior: rethrow so callers (currently `try?`) see no change
        // in control flow — this is diagnostic instrumentation only.
        throw error
    }
}

/// Creates a CKQuerySubscription so this device gets a push notification whenever the given
/// club's ClubActivity record is created or updated (i.e. whenever it posts). Best-effort —
/// a failure here (e.g. offline, iCloud not signed in) shouldn't block the follow action.
func subscribeToClubActivity(clubId: String) async {
    let predicate = NSPredicate(format: "clubId == %@", clubId)
    let subscription = CKQuerySubscription(
        recordType: "ClubActivity",
        predicate: predicate,
        subscriptionID: "club-follow-\(clubId)",
        options: [.firesOnRecordCreation, .firesOnRecordUpdate]
    )
    // Silent push (no alert/sound of its own) — CloudKit's own alert templating needs a
    // properly-registered Localizable.strings in an .lproj folder, which this project has
    // never had set up. Instead this just wakes the app, which then builds the real
    // notification text itself in checkForNewClubAnnouncements() and fires it as a local
    // notification — reusing code that's already proven to produce correct dynamic text.
    let info = CKSubscription.NotificationInfo()
    info.shouldSendContentAvailable = true
    subscription.notificationInfo = info
    do {
        _ = try await CKContainer.default().publicCloudDatabase.save(subscription)
        print("[ClubActivity] Subscribed to club \(clubId)")
    } catch {
        print("[ClubActivity] FAILED to subscribe to club \(clubId): \(error)")
        if let ckError = error as? CKError {
            print("[ClubActivity] CKError code: \(ckError.code.rawValue), description: \(ckError.localizedDescription)")
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                for (itemID, itemError) in partialErrors {
                    print("[ClubActivity] Partial error for item \(itemID): \(itemError)")
                }
            }
        }
    }
}

/// Removes the CKQuerySubscription created by `subscribeToClubActivity` when a student
/// unfollows a club. Best-effort — no harm if the subscription is already gone.
func unsubscribeFromClubActivity(clubId: String) async {
    do {
        try await CKContainer.default().publicCloudDatabase.deleteSubscription(withID: "club-follow-\(clubId)")
        print("[ClubActivity] Unsubscribed from club \(clubId)")
    } catch {
        print("[ClubActivity] FAILED to unsubscribe from club \(clubId): \(error)")
        if let ckError = error as? CKError {
            print("[ClubActivity] CKError code: \(ckError.code.rawValue), description: \(ckError.localizedDescription)")
        }
    }
}

// Background-poll fallback for club announcement notifications — CKQuerySubscription-based
// push (see subscribeToClubActivity) is fully built and correctly configured but appears to
// be hitting a genuine Apple-side CloudKit push delivery bug (extensively verified: subscription
// confirmed created and correctly configured via CloudKit Dashboard, schema/indexes correct in
// both Development and Production, manual APNs test push to the device works, cross-device
// tested, fresh club/fresh subscription still doesn't fire). This periodically polls each
// followed club's ClubActivity record directly (a plain CKRecord fetch, same mechanism proven
// working for club background images) and fires a LOCAL notification for anything new, instead
// of depending on push at all.
func checkForNewClubAnnouncements() async {
    #if os(iOS)
    guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: "followedClubIDs"),
          let followedClubIDs = try? JSONDecoder().decode(Set<String>.self, from: data),
          !followedClubIDs.isEmpty else { return }

    for clubId in followedClubIDs {
        guard let record = try? await CKContainer.default().publicCloudDatabase.record(for: CKRecord.ID(recordName: "club-activity-\(clubId)")),
              let postedAt = record["postedAt"] as? Date else { continue }

        let clubName = record["clubName"] as? String ?? "A club you follow"
        let announcementTitle = record["announcementTitle"] as? String ?? "New announcement"
        let authorName = record["authorName"] as? String ?? ""

        // Re-read fresh each iteration (not hoisted before the loop) so a concurrent
        // invocation of this same function (e.g. background refresh and a push waking
        // the app at nearly the same moment) can't clobber another club's already-persisted
        // dedup state with a stale in-memory copy.
        var lastSeen = (UserDefaults(suiteName: appGroupID)?.dictionary(forKey: "lastSeenClubActivity") as? [String: TimeInterval]) ?? [:]
        let lastSeenTime = lastSeen[clubId].map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        guard postedAt > lastSeenTime else { continue }

        lastSeen[clubId] = postedAt.timeIntervalSince1970
        UserDefaults(suiteName: appGroupID)?.set(lastSeen, forKey: "lastSeenClubActivity")

        let content = UNMutableNotificationContent()
        content.title = clubName
        content.body = authorName.isEmpty ? announcementTitle : "\(announcementTitle) — \(authorName)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "club-\(clubId)-\(Int(postedAt.timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[ClubActivity] Failed to send local notification: \(error)") }
        }
    }
    #endif
}

/// Schedules "1 hour before" and "starting now" local notification reminders for a club's
/// upcoming events. Uses stable per-event identifiers so calling this again for the same
/// events (e.g. on every background refresh or page visit) harmlessly replaces the existing
/// pending request rather than creating duplicates — UNUserNotificationCenter.add(_:) with an
/// identifier that already exists just updates it in place.
func scheduleEventReminders(clubName: String, events: [ClubEvent]) {
    let now = Date()
    for event in events where event.date > now {
        let locationSuffix = event.location.isEmpty ? "" : " · \(event.location)"
        let oneHourBefore = event.date.addingTimeInterval(-3600)
        if oneHourBefore > now {
            scheduleEventLocalNotification(
                id: "event-\(event.id)-1hr",
                title: clubName,
                body: "\(event.title) starts in 1 hour" + locationSuffix,
                date: oneHourBefore
            )
        }
        scheduleEventLocalNotification(
            id: "event-\(event.id)-start",
            title: clubName,
            body: "\(event.title) is starting now" + locationSuffix,
            date: event.date
        )
    }
}

private func scheduleEventLocalNotification(id: String, title: String, body: String, date: Date) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

/// Scans every club this device follows and (re)schedules event reminders for all of their
/// upcoming events — the "keep reminders fresh in the background" sweep, mirroring
/// checkForNewClubAnnouncements()'s followed-club scan. Called from the same trigger points
/// (background refresh, silent push wake-up, and Mac's clubs-list appearance since macOS has
/// no background-refresh task) so reminders exist even for events the user never personally
/// opens that club's page to see. Not #if os(iOS) guarded — UNUserNotificationCenter works
/// identically on iOS and macOS, and reminders should fire on both platforms.
func scheduleFollowedClubEventReminders() async {
    guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: "followedClubIDs"),
          let followedClubIDs = try? JSONDecoder().decode(Set<String>.self, from: data),
          !followedClubIDs.isEmpty else { return }
    let clubs = (try? await FirebaseService.shared.fetchClubs()) ?? []
    for clubId in followedClubIDs {
        guard let club = clubs.first(where: { $0.id == clubId }) else { continue }
        let events = (try? await FirebaseService.shared.fetchClubEvents(clubId: clubId)) ?? []
        scheduleEventReminders(clubName: club.name, events: events)
    }
}

/// Deletes every `club-follow-*` subscription on the account (regardless of which clubId it's
/// for) and recreates one fresh subscription per currently-followed club. Use this to clear out
/// orphaned/duplicate subscriptions — e.g. leftovers from a deleted test club, or ones created
/// under an older `NotificationInfo` config before a code change — without needing to figure out
/// which specific stale IDs are safe to remove. A clean slate that's guaranteed to end up
/// matching exactly what's followed on this device right now.
func resetClubSubscriptions(followedClubIDs: Set<String>) async -> String {
    var log = ""
    do {
        let subscriptions = try await CKContainer.default().publicCloudDatabase.allSubscriptions()
        let followSubscriptionIDs = subscriptions.map(\.subscriptionID).filter { $0.hasPrefix("club-follow-") }
        if !followSubscriptionIDs.isEmpty {
            _ = try await CKContainer.default().publicCloudDatabase.modifySubscriptions(saving: [], deleting: followSubscriptionIDs)
            log += "Deleted \(followSubscriptionIDs.count) existing club-follow subscription(s).\n"
        } else {
            log += "No existing club-follow subscriptions found.\n"
        }
    } catch {
        log += "Failed to fetch/delete existing subscriptions: \(error)\n"
        print("[ClubActivity] resetClubSubscriptions — delete step failed: \(error)")
    }

    for clubId in followedClubIDs {
        await subscribeToClubActivity(clubId: clubId)
    }
    log += "Recreated \(followedClubIDs.count) subscription(s) for currently followed club(s)."
    print("[ClubActivity] resetClubSubscriptions: \(log)")
    return log
}

// DIAGNOSTIC TEST ONLY — isolates whether CKQuerySubscription's predicate
// evaluation specifically is broken, vs. CloudKit push delivery in general.
// CKDatabaseSubscription fires on ANY public-database change, no predicate.
func subscribeToDatabaseTest() async {
    let subscription = CKDatabaseSubscription(subscriptionID: "test-database-subscription")
    let info = CKSubscription.NotificationInfo()
    info.alertBody = "Database changed (test)"
    info.soundName = "default"
    subscription.notificationInfo = info
    do {
        _ = try await CKContainer.default().publicCloudDatabase.save(subscription)
        print("[DatabaseSubscriptionTest] Subscribed to database-wide changes")
    } catch {
        print("[DatabaseSubscriptionTest] FAILED to subscribe: \(error)")
        if let ckError = error as? CKError {
            print("[DatabaseSubscriptionTest] CKError code: \(ckError.code.rawValue), description: \(ckError.localizedDescription)")
        }
    }
}

// MARK: - CloudKit Notification Lab (Debug diagnostics)
//
// The CKQuerySubscription used by `subscribeToClubActivity` is confirmed correctly configured
// (verified via CloudKit Dashboard: subscription exists, matches expected config, schema/indexes
// correct in both Development and Production) yet the Dashboard's raw event Logs show zero
// `NotificationSend` events ever — CloudKit's backend isn't even attempting delivery. These
// functions each try a different configuration variation to isolate what (if anything) makes
// push delivery actually fire. Each one is self-contained: it subscribes AND immediately writes
// a matching record in the same call, eliminating any timing gap between separate follow/post
// actions across different UI flows. All print output is prefixed `[CloudKitLab]` for easy
// filtering in Xcode's console.

/// Variation 1: a CKQuerySubscription with EVERY reasonable `NotificationInfo` field explicitly
/// set (not just alertBody/soundName), on a brand-new never-before-used subscriptionID, matched
/// against a dedicated TEST record so it can't interfere with real club data.
func testFullyExplicitSubscription() async -> String {
    let testId = "lab-test-\(Int(Date().timeIntervalSince1970))"
    var log = ""

    let predicate = NSPredicate(format: "clubId == %@", testId)
    let subscription = CKQuerySubscription(
        recordType: "ClubActivity",
        predicate: predicate,
        subscriptionID: "lab-sub-\(testId)",
        options: [.firesOnRecordCreation, .firesOnRecordUpdate]
    )
    let info = CKSubscription.NotificationInfo()
    info.alertBody = "Lab test notification"
    info.title = "CloudKit Lab Test"
    info.soundName = "default"
    info.shouldBadge = true
    info.shouldSendContentAvailable = false
    info.desiredKeys = ["clubId", "clubName", "announcementTitle", "authorName", "postedAt"]
    info.category = "LAB_TEST"
    subscription.notificationInfo = info

    do {
        _ = try await CKContainer.default().publicCloudDatabase.save(subscription)
        log += "Subscribe: SUCCESS\n"
    } catch {
        log += "Subscribe: FAILED — \(error)\n"
        print("[CloudKitLab] testFullyExplicitSubscription — Subscribe failed: \(error)")
        return log
    }

    // Small delay to let the subscription register before triggering it.
    try? await Task.sleep(nanoseconds: 2_000_000_000)

    let record = CKRecord(recordType: "ClubActivity", recordID: CKRecord.ID(recordName: "lab-record-\(testId)"))
    record["clubId"] = testId
    record["clubName"] = "Lab Test Club"
    record["announcementTitle"] = "Lab test announcement"
    record["authorName"] = "Diagnostic"
    record["postedAt"] = Date()
    do {
        _ = try await CKContainer.default().publicCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        log += "Matching record write: SUCCESS (testId: \(testId))\n"
    } catch {
        log += "Matching record write: FAILED — \(error)\n"
        print("[CloudKitLab] testFullyExplicitSubscription — Record write failed: \(error)")
    }

    print("[CloudKitLab] testFullyExplicitSubscription: \(log)")
    return log
}

/// Variation 2: per Apple's own QA1917 debugging recommendation, uses `NSPredicate(value: true)`
/// (matches literally any ClubActivity record, no field filtering at all) instead of a specific
/// clubId match. Isolates whether predicate evaluation itself is the broken part, vs. general
/// subscription delivery.
func testWildcardPredicateSubscription() async -> String {
    let testId = "lab-test-wildcard-\(Int(Date().timeIntervalSince1970))"
    var log = ""

    let predicate = NSPredicate(value: true)
    let subscription = CKQuerySubscription(
        recordType: "ClubActivity",
        predicate: predicate,
        subscriptionID: "lab-sub-wildcard-\(testId)",
        options: [.firesOnRecordCreation, .firesOnRecordUpdate]
    )
    let info = CKSubscription.NotificationInfo()
    info.alertBody = "Lab test notification"
    info.title = "CloudKit Lab Test (wildcard)"
    info.soundName = "default"
    info.shouldBadge = true
    info.shouldSendContentAvailable = false
    info.desiredKeys = ["clubId", "clubName", "announcementTitle", "authorName", "postedAt"]
    info.category = "LAB_TEST"
    subscription.notificationInfo = info

    do {
        _ = try await CKContainer.default().publicCloudDatabase.save(subscription)
        log += "Subscribe (wildcard predicate): SUCCESS\n"
    } catch {
        log += "Subscribe (wildcard predicate): FAILED — \(error)\n"
        print("[CloudKitLab] testWildcardPredicateSubscription — Subscribe failed: \(error)")
        return log
    }

    // Small delay to let the subscription register before triggering it.
    try? await Task.sleep(nanoseconds: 2_000_000_000)

    // Any ClubActivity record will match a `value: true` predicate.
    let record = CKRecord(recordType: "ClubActivity", recordID: CKRecord.ID(recordName: "lab-record-\(testId)"))
    record["clubId"] = testId
    record["clubName"] = "Lab Test Club (wildcard)"
    record["announcementTitle"] = "Lab wildcard test announcement"
    record["authorName"] = "Diagnostic"
    record["postedAt"] = Date()
    do {
        _ = try await CKContainer.default().publicCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        log += "Matching record write: SUCCESS (testId: \(testId))\n"
    } catch {
        log += "Matching record write: FAILED — \(error)\n"
        print("[CloudKitLab] testWildcardPredicateSubscription — Record write failed: \(error)")
    }

    print("[CloudKitLab] testWildcardPredicateSubscription: \(log)")
    return log
}

/// Variation 3: try `CKRecordZoneSubscription` (the third CloudKit subscription type, alongside
/// Query and Database) against the public database's default zone. This might fail with the
/// same "Metasync subscriptions are not allowed in public database" error `CKDatabaseSubscription`
/// hit — that's a valid, useful result either way.
func testRecordZoneSubscription() async -> String {
    let subscription = CKRecordZoneSubscription(
        zoneID: CKRecordZone.default().zoneID,
        subscriptionID: "lab-zone-sub-\(Int(Date().timeIntervalSince1970))"
    )
    let info = CKSubscription.NotificationInfo()
    info.alertBody = "Lab zone test notification"
    info.soundName = "default"
    subscription.notificationInfo = info
    do {
        _ = try await CKContainer.default().publicCloudDatabase.save(subscription)
        print("[CloudKitLab] testRecordZoneSubscription: CKRecordZoneSubscription save: SUCCESS")
        return "CKRecordZoneSubscription save: SUCCESS"
    } catch {
        print("[CloudKitLab] testRecordZoneSubscription — Zone subscription failed: \(error)")
        if let ckError = error as? CKError {
            print("[CloudKitLab] testRecordZoneSubscription — CKError code: \(ckError.code.rawValue), description: \(ckError.localizedDescription)")
        }
        return "CKRecordZoneSubscription save: FAILED — \(error)"
    }
}

/// Variation 4: client-side sanity check — lists every subscription the app itself can currently
/// see for this container/database via `CKDatabase.allSubscriptions()`, confirming from the
/// CLIENT's own perspective (not just the Dashboard) exactly what subscriptions exist right now.
///
/// NOTE ON API CERTAINTY: `CKDatabase.allSubscriptions() async throws -> [CKSubscription]` is the
/// modern async replacement for `CKFetchSubscriptionsOperation` (fetching ALL subscriptions, as
/// opposed to `subscription(for:)` which fetches one by ID). It has shipped since iOS 15 /
/// macOS 12. This is a good-faith best attempt at the real, current API surface.
func fetchAllMySubscriptions() async -> String {
    do {
        let subscriptions = try await CKContainer.default().publicCloudDatabase.allSubscriptions()
        guard !subscriptions.isEmpty else {
            print("[CloudKitLab] fetchAllMySubscriptions: no subscriptions found")
            return "No subscriptions found on this database."
        }
        var log = "Found \(subscriptions.count) subscription(s):\n"
        for sub in subscriptions {
            var line = "- ID: \(sub.subscriptionID), type: \(sub.subscriptionType.rawValue)"
            if let querySub = sub as? CKQuerySubscription {
                line += ", recordType: \(querySub.recordType), predicate: \(querySub.predicate)"
            } else if let zoneSub = sub as? CKRecordZoneSubscription {
                line += ", zoneID: \(zoneSub.zoneID)"
            }
            log += line + "\n"
        }
        print("[CloudKitLab] fetchAllMySubscriptions: \(log)")
        return log
    } catch {
        print("[CloudKitLab] fetchAllMySubscriptions — FAILED: \(error)")
        return "Fetch subscriptions: FAILED — \(error)"
    }
}

/// Variation 5: identical scenario to `testWildcardPredicateSubscription`, but built with the
/// older, explicit `CKModifySubscriptionsOperation` / `CKModifyRecordsOperation` API instead of
/// the async/await convenience methods (`CKDatabase.save(_:)` / `CKDatabase.modifyRecords`) that
/// every other lab test — and all of production — exclusively uses. This isolates whether the
/// async convenience wrappers are silently leaving something mis-configured (e.g.
/// `qualityOfService`, operation-level config) that the explicit Operation path sets correctly.
///
/// NOTE ON API CERTAINTY: `modifySubscriptionsResultBlock` and `modifyRecordsResultBlock` are the
/// modern iOS 15+ result-block completion properties (`((Result<Void, Error>) -> Void)?`),
/// replacing the deprecated `modifySubscriptionsCompletionBlock` / `modifyRecordsCompletionBlock`.
/// This is a good-faith best attempt at the real, current API surface.
func testOperationBasedSubscription() async -> String {
    let testId = "lab-op-test-\(Int(Date().timeIntervalSince1970))"
    var log = ""

    let predicate = NSPredicate(value: true)
    let subscription = CKQuerySubscription(
        recordType: "ClubActivity",
        predicate: predicate,
        subscriptionID: "lab-op-sub-\(testId)",
        options: [.firesOnRecordCreation, .firesOnRecordUpdate]
    )
    let info = CKSubscription.NotificationInfo()
    info.alertBody = "Lab operation-based test notification"
    info.soundName = "default"
    subscription.notificationInfo = info

    let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
    operation.qualityOfService = .userInitiated

    log += await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
        operation.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                continuation.resume(returning: "Operation-based subscribe: SUCCESS\n")
            case .failure(let error):
                print("[CloudKitLab] Operation-based subscribe failed: \(error)")
                continuation.resume(returning: "Operation-based subscribe: FAILED — \(error)\n")
            }
        }
        CKContainer.default().publicCloudDatabase.add(operation)
    }

    // Small delay to let the subscription register before writing a matching record.
    try? await Task.sleep(nanoseconds: 2_000_000_000)

    let record = CKRecord(recordType: "ClubActivity", recordID: CKRecord.ID(recordName: "lab-op-record-\(testId)"))
    record["clubId"] = testId
    record["clubName"] = "Lab Operation Test Club"
    record["announcementTitle"] = "Lab operation-based test announcement"
    record["authorName"] = "Diagnostic"
    record["postedAt"] = Date()

    let recordOp = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
    recordOp.savePolicy = .changedKeys
    recordOp.qualityOfService = .userInitiated

    log += await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
        recordOp.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                continuation.resume(returning: "Operation-based record write: SUCCESS (testId: \(testId))\n")
            case .failure(let error):
                continuation.resume(returning: "Operation-based record write: FAILED — \(error)\n")
            }
        }
        CKContainer.default().publicCloudDatabase.add(recordOp)
    }

    print("[CloudKitLab] testOperationBasedSubscription: \(log)")
    return log
}

/// Cleanup: removes leftover diagnostic subscriptions created by the lab test functions above.
/// These all used broad/test predicates (several use `NSPredicate(value: true)`, matching ANY
/// `ClubActivity` record change) and were never torn down after testing, so they kept firing
/// extra pushes alongside the real `club-follow-<clubId>` subscription on every genuine club
/// announcement. Matches every subscriptionID prefix produced by the lab functions in this file
/// (`lab-sub-...` from testFullyExplicitSubscription/testWildcardPredicateSubscription,
/// `lab-op-sub-...` from testOperationBasedSubscription, `lab-zone-sub-...` from
/// testRecordZoneSubscription — included defensively even though that one failed to save — and
/// the standalone `test-database-subscription` from subscribeToDatabaseTest, which also failed
/// outright but is filtered defensively in case of partial success). Deliberately does NOT match
/// `club-follow-*`, the real, working per-club follow subscriptions created by
/// `subscribeToClubActivity` — those must never be touched by this cleanup.
func cleanUpLabSubscriptions() async -> String {
    do {
        let subscriptions = try await CKContainer.default().publicCloudDatabase.allSubscriptions()
        let labSubscriptions = subscriptions.filter { $0.subscriptionID.hasPrefix("lab-") || $0.subscriptionID == "test-database-subscription" }
        guard !labSubscriptions.isEmpty else {
            print("[CloudKitLab] cleanUpLabSubscriptions: no leftover lab subscriptions found")
            return "No leftover lab subscriptions found."
        }

        var log = "Found \(labSubscriptions.count) lab subscription(s) to remove:\n"
        for sub in labSubscriptions {
            do {
                try await CKContainer.default().publicCloudDatabase.deleteSubscription(withID: sub.subscriptionID)
                log += "Deleted: \(sub.subscriptionID)\n"
            } catch {
                log += "FAILED to delete \(sub.subscriptionID): \(error)\n"
            }
        }
        print("[CloudKitLab] cleanUpLabSubscriptions: \(log)")
        return log
    } catch {
        print("[CloudKitLab] cleanUpLabSubscriptions failed to list subscriptions: \(error)")
        return "Failed to list subscriptions: \(error)"
    }
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

/// Runs a live directory search for a club officer by name and returns a freshly-signed
/// `photoURL` valid at the moment of the call. Officer photo URLs stored in Firestore are
/// signed with a baked-in expiration and 403 once that passes, so display code should always
/// call this instead of using `ClubOfficer.photoURL` directly.
func lookupFreshPhotoURL(name: String, email: String) async -> String? {
    let parts = name.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
    let first = parts.first ?? ""
    let last = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
    var queryItems: [URLQueryItem] = []
    if !first.isEmpty { queryItems.append(URLQueryItem(name: "directory_entry[first_name]", value: first)) }
    if !last.isEmpty { queryItems.append(URLQueryItem(name: "directory_entry[last_name]", value: last)) }
    let (results, _) = await fetchDirectoryPage1(queryItems: queryItems)
    // Disambiguate by email in case of a name collision among search results.
    return results.first(where: { $0.studentEmail == email })?.photoURL ?? results.first?.photoURL
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

// MARK: - Class Roster Scraping
//
// Fetches a single class's roster (Directory tab), which lives at
// classes.veracross.com/oakwood/course/{class_id}/website/directory — a different subdomain
// from portals.veracross.com, where the app actually authenticates. Two fetch paths:
//   1. Cheap path: a direct authenticated URLSession GET straight at that URL.
//   2. Fallback: reuses the exact click-through mechanism proven to work for the webview
//      version (load the authenticated portal overview page, find the matching course's
//      Directory link by nearby text, strip target="_blank", click it, wait for the
//      resulting navigation), except here it's driven by an off-screen, headless WKWebView
//      and awaited, then the resulting page's HTML is pulled out and parsed with SwiftSoup
//      instead of being left on screen.
//
// Confirmed via a real console capture: the class directory page uses the exact same
// `div.DirectoryEntries > div.directory-Entry` component as the main school Directory search
// (fetchDirectoryPage1 above) — same directory-Entry_Header/PersonPhoto--square/HouseholdSection
// class names — so this reuses parseDirectoryEntry directly instead of a separate generic
// parser, producing real DirectoryPerson results (name, grade, photo, households) instead of
// a stripped-down custom model.

/// Per-session cache of class rosters, keyed by class_id. Without this, viewing multiple
/// directory profiles would each independently re-fetch every one of the student's classes'
/// rosters from scratch, which is expensive (the click-through fallback path involves a real
/// off-screen webview navigation). Both the Directory profile "shared classes" lookup and the
/// class's own roster sheet (CourseView/Mac_CourseDetailView) should go through this instead of
/// calling fetchClassRoster directly, so repeated lookups within a session are cheap after the
/// first fetch per class.
actor ClassRosterCache {
    static let shared = ClassRosterCache()
    private var cache: [String: [DirectoryPerson]] = [:]

    func roster(for course: Course) async -> [DirectoryPerson] {
        if let cached = cache[course.class_id] { return cached }
        let fetched = await fetchClassRoster(course: course)
        cache[course.class_id] = fetched
        return fetched
    }
}

/// Entry point: tries the direct fetch first, falls back to the click-through mechanism if
/// that comes back empty.
func fetchClassRoster(course: Course) async -> [DirectoryPerson] {
    if let direct = await fetchClassRosterDirect(classID: course.class_id), !direct.isEmpty {
        print("[ClassRoster] direct fetch to classes.veracross.com succeeded with \(direct.count) people")
        return direct
    }

    print("[ClassRoster] direct fetch found no roster entries, falling back to portal click-through")
    let fetcher = ClassRosterWebFetcher(matchHint: course.class_name)
    guard let html = await fetcher.fetchDirectoryHTML() else {
        print("[ClassRoster] click-through fallback failed to produce a page (no click match, navigation failure, or timeout)")
        return []
    }
    let people = parseClassRoster(html: html)
    if people.isEmpty {
        print("[ClassRoster] click-through HTML length: \(html.count). Parse found 0 people. First 1500 chars:\n\(String(html.prefix(1500)))")
    } else {
        print("[ClassRoster] click-through fetch succeeded with \(people.count) people")
    }
    return people
}

/// Direct authenticated GET against classes.veracross.com. Returns nil on outright failure
/// (network error, non-200, undecodable body) and an empty array if the fetch succeeded but
/// parsing found no directory entries — callers should treat both as "didn't work" and fall
/// back to the click-through path, but the distinction is preserved in the logs.
private func fetchClassRosterDirect(classID: String) async -> [DirectoryPerson]? {
    guard let url = URL(string: "https://classes.veracross.com/oakwood/course/\(classID)/website/directory") else { return nil }
    var request = URLRequest(url: url)
    request.httpShouldHandleCookies = true
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 15

    guard let (data, response) = try? await URLSession.shared.data(for: request) else {
        print("[ClassRoster] direct fetch request failed (network error)")
        return nil
    }
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        print("[ClassRoster] direct fetch returned HTTP \(http.statusCode)")
        return nil
    }
    guard let html = String(data: data, encoding: .utf8) else {
        print("[ClassRoster] direct fetch response wasn't decodable as UTF-8 text")
        return nil
    }
    print("[ClassRoster] direct fetch HTML length: \(html.count)")
    return parseClassRoster(html: html)
}

/// Same directory-Entry component the main school Directory search already parses (see
/// parseDirectoryEntry above) — just scoped under this page's `div.DirectoryEntries` wrapper.
private func parseClassRoster(html: String) -> [DirectoryPerson] {
    guard let doc = try? SwiftSoup.parse(html),
          let entries = try? doc.select("div.DirectoryEntries div.directory-Entry"), !entries.isEmpty() else {
        return []
    }
    return entries.array().compactMap { parseDirectoryEntry($0) }
}

/// Drives an off-screen, headless WKWebView through the same authenticated click-through the
/// visible DocumentWebViewCoordinator uses (see the big comment above DocumentWebViewCoordinator
/// near the top of this file), then hands back the final page's raw HTML instead of leaving it
/// on screen. Never added to any view hierarchy — just a helper object that owns a WKWebView
/// for the duration of one fetch.
@MainActor
private final class ClassRosterWebFetcher: NSObject, WKNavigationDelegate {
    private let matchHint: String
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var hasClicked = false
    private var isFinished = false

    init(matchHint: String) {
        self.matchHint = matchHint
    }

    /// Loads the known-good authenticated portal overview page, auto-clicks the matching
    /// course's Directory link, waits for the resulting navigation, and returns that page's
    /// `outerHTML` — or nil if the click never matched, a navigation failed, or nothing
    /// happened within the timeout.
    func fetchDirectoryHTML() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            self.webView = wv
            wv.load(URLRequest(url: URL(string: "https://portals.veracross.com/oakwood/student/student/overview")!))

            // Safety net: if the click never leads to a second didFinish (no match, or the
            // click-through silently does nothing), don't hang forever.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await MainActor.run { self?.finish(with: nil, reason: "timed out waiting for click-through navigation") }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !hasClicked {
            hasClicked = true
            runAutoClick(on: webView)
            return
        }
        // Second didFinish: this is (presumably) the class directory page the click navigated to.
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            Task { @MainActor in
                if let error {
                    print("[ClassRoster] outerHTML fetch failed: \(error)")
                    self?.finish(with: nil, reason: "outerHTML fetch error")
                    return
                }
                self?.finish(with: result as? String, reason: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[ClassRoster] navigation failed: \(error)")
        finish(with: nil, reason: "navigation failed")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[ClassRoster] provisional navigation failed: \(error)")
        finish(with: nil, reason: "provisional navigation failed")
    }

    private func runAutoClick(on webView: WKWebView) {
        let escapedLink = "/website/directory".replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let escapedHint = matchHint.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var links = Array.from(document.querySelectorAll('a[href*="\(escapedLink)"]'));
            var hint = '\(escapedHint)'.toLowerCase();
            for (var i = 0; i < links.length; i++) {
                var row = links[i].closest('li') || links[i].closest('.ae-grid') || links[i].parentElement;
                var text = ((row ? row.innerText : links[i].innerText) || '').toLowerCase();
                if (text.indexOf(hint) !== -1) {
                    links[i].removeAttribute('target');
                    links[i].click();
                    return true;
                }
            }
            return false;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    print("[ClassRoster] auto-click JS failed: \(error)")
                    self.finish(with: nil, reason: "auto-click JS error")
                    return
                }
                let clicked = (result as? Bool) ?? false
                print("[ClassRoster] auto-click matched a link: \(clicked)")
                if !clicked {
                    self.finish(with: nil, reason: "no matching directory link found")
                }
                // If clicked, wait for the next didFinish (the resulting navigation).
            }
        }
    }

    private func finish(with html: String?, reason: String?) {
        guard !isFinished else { return }
        isFinished = true
        if let reason { print("[ClassRoster] \(reason)") }
        webView?.navigationDelegate = nil
        webView = nil
        continuation?.resume(returning: html)
        continuation = nil
    }
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

class ImageDataCache {
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
