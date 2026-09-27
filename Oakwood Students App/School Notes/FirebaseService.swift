//
//  FirebaseService.swift
//  School Notes
//
//  Created by Luke Titi on 1/30/26.
//

import Foundation
import FirebaseFirestore

// Advisor roster — update as advisors change. Last names only, deliberately no titles
// (Mr./Mrs./Dr./etc.) — this list is populated from a grade-level roster chart that gives
// no gender/title info, and guessing wrong would misgender someone. Keep in sync with
// ADVISOR_LIST in chrome-extension/popup.js.
let advisorList: [String] = [
    // 9th grade
    "Calvillo", "Hammerbeck", "Hashem", "Sedik/Velez", "Wilmot",
    // 10th grade
    "Call", "Day", "Pak",
    // 11th grade
    "Clink", "Furtado", "Gastelum", "Hubbard",
    // 12th grade
    "de Bree", "Dehpanah", "Kuruvilla", "Sotelo"
]

// Schoolwide Learner Objective categories (from the paper Service Learning Program form, page 2) —
// multi-select, a single service can reasonably touch more than one.
let slOptions: [String] = [
    "Critical Thinkers",
    "Effective Communicators",
    "Community Contributors",
    "Authentic and Resilient Individuals"
]

// Veracross's community-service "organization_key" field posts a numeric fk into a fixed
// value-list (discovered via the admin Chrome extension's "Looking up value lists…" step —
// see popup.js). Oakwood/on-campus service always resolves to this same key, so it's baked in
// here rather than living in the `serviceOrganizations` Firestore collection below — a student
// logging inside hours never needs to pick it themselves.
let oakwoodOrganizationName = "Oakwood"
let oakwoodOrganizationKey = 15296

// MARK: - FirebaseService (Handles all Firestore operations)
class FirebaseService {
    static let shared = FirebaseService()
    let db = Firestore.firestore()
    private init() {}

    // MARK: - Service Hours Forms

    @discardableResult
    func submitServiceForm(_ form: ServiceForm, studentId: String, studentName: String, personPK: Int?, supervisorName: String, supervisorEmail: String, advisorName: String) async throws -> String {
        var data: [String: Any] = [
            "studentId": studentId,
            "studentName": studentName,
            "title": form.title,
            "status": "pending_signature",
            "submittedAt": Timestamp(date: form.dateCreated),
            "totalHours": form.services.reduce(0) { $0 + $1.hours },
            "slos": form.slos,
            "reflection1": form.reflection1,
            "reflection2": form.reflection2,
            "reflection3": form.reflection3,
            "taxID": form.taxID ?? "",
            "organization": form.organization ?? "",
            "supervisorName": supervisorName,
            "supervisorEmail": supervisorEmail,
            "advisorName": advisorName,
            "supervisorSignature": "",
            "services": form.services.map { [
                "date": $0.date,
                "notes": $0.notes,
                "hours": $0.hours,
                "description": $0.description
            ]}
        ]
        if let personPK { data["personPK"] = personPK }
        if let organizationKey = form.organizationKey { data["organizationKey"] = organizationKey }
        let ref = try await db.collection("serviceForms").addDocument(data: data)
        return ref.documentID
    }

    /// Resubmits a rejected form in place: same document, edited fields, restarted signing cycle.
    /// Resets status back to "pending_signature" and clears rejection/signature state so the
    /// supervisor re-verifies whatever the student fixed rather than skipping straight to approval.
    func resubmitServiceForm(formId: String, form: ServiceForm, supervisorName: String, supervisorEmail: String, advisorName: String) async throws {
        let data: [String: Any] = [
            "title": form.title,
            "totalHours": form.services.reduce(0) { $0 + $1.hours },
            "slos": form.slos,
            "reflection1": form.reflection1,
            "reflection2": form.reflection2,
            "reflection3": form.reflection3,
            "taxID": form.taxID ?? "",
            "organization": form.organization ?? "",
            "organizationKey": (form.organizationKey as Any?) ?? FieldValue.delete(),
            "supervisorName": supervisorName,
            "supervisorEmail": supervisorEmail,
            "advisorName": advisorName,
            "status": "pending_signature",
            "rejectionReason": "",
            "supervisorSignature": "",
            "signerEmail": "",
            "signatureImage": FieldValue.delete(),
            "signedAt": FieldValue.delete(),
            "services": form.services.map { [
                "date": $0.date,
                "notes": $0.notes,
                "hours": $0.hours,
                "description": $0.description
            ]}
        ]
        try await db.collection("serviceForms").document(formId).setData(data, merge: true)
    }

    func submitFormToAdvisor(formId: String) async throws {
        // "pending" matches advisor-portal's status vocabulary (its "Pending" tab filters on
        // this exact string) — don't rename without updating advisor-portal/index.html too.
        try await db.collection("serviceForms").document(formId).updateData(["status": "pending"])
    }

    func fetchMyServiceForms(studentId: String) async throws -> [SubmittedForm] {
        // Note: Removed orderBy because it requires a composite index in Firestore
        // We sort in memory instead after fetching
        let snapshot = try await db.collection("serviceForms")
            .whereField("studentId", isEqualTo: studentId)
            .getDocuments()

        let forms = snapshot.documents.compactMap { parseSubmittedForm($0) }
        return forms.sorted { $0.submittedAt > $1.submittedAt }
    }

    func parseSubmittedForm(_ doc: QueryDocumentSnapshot) -> SubmittedForm? {
        let data = doc.data()
        let services = (data["services"] as? [[String: Any]] ?? []).map { s in
            LocalService(date: s["date"] as? String ?? "", description: s["description"] as? String ?? "",
                         notes: s["notes"] as? String ?? "", hours: s["hours"] as? Double ?? 0,
                         veracrossRecordId: s["veracrossRecordId"] as? Int)
        }
        return SubmittedForm(
            id: doc.documentID,
            title: data["title"] as? String ?? "Untitled",
            personPK: data["personPK"] as? Int,
            status: data["status"] as? String ?? "pending_signature",
            submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue() ?? Date(),
            totalHours: data["totalHours"] as? Double ?? 0,
            slos: data["slos"] as? [String] ?? [],
            reflection1: data["reflection1"] as? String ?? "",
            reflection2: data["reflection2"] as? String ?? "",
            reflection3: data["reflection3"] as? String ?? "",
            taxID: data["taxID"] as? String ?? "",
            organization: data["organization"] as? String ?? "",
            organizationKey: data["organizationKey"] as? Int,
            services: services,
            supervisorName: data["supervisorName"] as? String ?? "",
            supervisorEmail: data["supervisorEmail"] as? String ?? "",
            advisorName: data["advisorName"] as? String ?? "",
            supervisorSignature: data["supervisorSignature"] as? String ?? "",
            signerEmail: data["signerEmail"] as? String ?? "",
            signatureImageBase64: data["signatureImage"] as? String,
            signedAt: (data["signedAt"] as? Timestamp)?.dateValue(),
            rejectionReason: data["rejectionReason"] as? String ?? ""
        )
    }

    /// Outside-service organizations a student can pick from when logging non-Oakwood hours.
    /// Grows over time as advisors discover more `organization_key` value-list codes (via the
    /// admin Chrome extension's "Looking up value lists…" step — see popup.js) and add them here
    /// through the Firebase console. Oakwood itself is never in this list — see
    /// `oakwoodOrganizationKey`. `taxID` is optional per-org (also added by hand in the console,
    /// not by the app) — an org without one stored still shows up in the picker, it just doesn't
    /// auto-fill the Tax ID field, same as if the student picked an org that's never had one entered.
    func fetchServiceOrganizations() async throws -> [ServiceOrganization] {
        let snapshot = try await db.collection("serviceOrganizations").order(by: "name").getDocuments()
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let name = data["name"] as? String, let orgKey = data["orgKey"] as? Int else { return nil }
            return ServiceOrganization(id: doc.documentID, name: name, orgKey: orgKey, taxID: data["taxID"] as? String)
        }
    }

    // MARK: - Real-time listener for form status updates
    func listenForFormUpdates(studentId: String, onChange: @escaping ([SubmittedForm]) -> Void) -> ListenerRegistration {
        return db.collection("serviceForms")
            .whereField("studentId", isEqualTo: studentId)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let forms = documents.compactMap { self.parseSubmittedForm($0) }
                onChange(forms.sorted { $0.submittedAt > $1.submittedAt })
            }
    }
}

// MARK: - SubmittedForm (Form that's been sent to Firebase)
struct SubmittedForm: Identifiable {
    var id: String
    var title: String
    var personPK: Int?  // Veracross person PK — carried through so a later "post to Veracross" step doesn't need a separate lookup
    var status: String  // "pending_signature" | "signed" | "pending" | "approved" | "rejected"
    var submittedAt: Date
    var totalHours: Double
    var slos: [String] = []
    var reflection1: String
    var reflection2: String
    var reflection3: String
    var taxID: String
    var organization: String
    var organizationKey: Int?  // Veracross organization_key value-list fk — see oakwoodOrganizationKey
    var services: [LocalService]
    var supervisorName: String
    var supervisorEmail: String
    var advisorName: String = ""
    var supervisorSignature: String
    var signerEmail: String  // email the signer typed in on the sign page — compare against supervisorEmail
    var signatureImageBase64: String?
    var signedAt: Date?
    var rejectionReason: String
}

// MARK: - App Banner
struct AppBanner {
    var message: String
    var type: String   // "info" | "warning" | "urgent"
}

// MARK: - Game Score
struct GameScore: Identifiable {
    var id: String
    var eventId: String
    var homeScore: Int
    var awayScore: Int
    var submittedBy: String
    var submittedByName: String
    var submittedAt: Date
}

// MARK: - Scoreboard Signup
struct ScoreboardSignup: Identifiable {
    var id: String
    var eventId: String
    var job: String
    var slot: Int  // For jobs with multiple slots (e.g., line judge 1, line judge 2)
    var userEmail: String
    var userName: String
    var signedUpAt: Date
    var serviceHoursClaimed: Bool
    var eventDate: Date?
    var eventDescription: String?  // e.g., "Basketball - Boys Varsity vs Notre Dame"
}

// MARK: - Job Definitions
struct JobDefinition {
    let name: String
    let slots: Int
}

let basketballJobs: [JobDefinition] = [
    JobDefinition(name: "Clock", slots: 1),
    JobDefinition(name: "Scoreboard", slots: 1),
    JobDefinition(name: "Shot Clock", slots: 1)
]

let volleyballJobs: [JobDefinition] = [
    JobDefinition(name: "Line Judge", slots: 2),
    JobDefinition(name: "Scorebook", slots: 1),
    JobDefinition(name: "Scoreboard", slots: 1)
]

func jobsForSport(_ sport: String) -> [JobDefinition] {
    switch sport.lowercased() {
    case "basketball": return basketballJobs
    case "volleyball": return volleyballJobs
    default: return []
    }
}

// MARK: - FirebaseService Sports Extensions
extension FirebaseService {

    // MARK: - Game Scores

    func submitGameScore(eventId: String, homeScore: Int, awayScore: Int, userEmail: String, userName: String) async throws {
        // Check if score already exists for this event
        let existing = try await db.collection("gameScores")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()

        if let existingDoc = existing.documents.first {
            // Update existing score
            try await db.collection("gameScores").document(existingDoc.documentID).updateData([
                "homeScore": homeScore,
                "awayScore": awayScore,
                "submittedBy": userEmail,
                "submittedByName": userName,
                "submittedAt": Timestamp(date: Date())
            ])
        } else {
            // Create new score
            let data: [String: Any] = [
                "eventId": eventId,
                "homeScore": homeScore,
                "awayScore": awayScore,
                "submittedBy": userEmail,
                "submittedByName": userName,
                "submittedAt": Timestamp(date: Date())
            ]
            try await db.collection("gameScores").addDocument(data: data)
        }
    }

    func fetchGameScore(eventId: String) async throws -> GameScore? {
        let snapshot = try await db.collection("gameScores")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()

        guard let doc = snapshot.documents.first else { return nil }
        let data = doc.data()

        return GameScore(
            id: doc.documentID,
            eventId: data["eventId"] as? String ?? "",
            homeScore: data["homeScore"] as? Int ?? 0,
            awayScore: data["awayScore"] as? Int ?? 0,
            submittedBy: data["submittedBy"] as? String ?? "",
            submittedByName: data["submittedByName"] as? String ?? "",
            submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    func fetchAllGameScores() async throws -> [String: GameScore] {
        let snapshot = try await db.collection("gameScores").getDocuments()

        var scores: [String: GameScore] = [:]
        for doc in snapshot.documents {
            let data = doc.data()
            let eventId = data["eventId"] as? String ?? ""
            scores[eventId] = GameScore(
                id: doc.documentID,
                eventId: eventId,
                homeScore: data["homeScore"] as? Int ?? 0,
                awayScore: data["awayScore"] as? Int ?? 0,
                submittedBy: data["submittedBy"] as? String ?? "",
                submittedByName: data["submittedByName"] as? String ?? "",
                submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
        return scores
    }

    // MARK: - Scoreboard Signups

    func signUpForJob(eventId: String, job: String, slot: Int, userEmail: String, userName: String, eventDate: Date, eventDescription: String) async throws {
        // Check if slot is already taken
        let existing = try await db.collection("scoreboardSignups")
            .whereField("eventId", isEqualTo: eventId)
            .whereField("job", isEqualTo: job)
            .whereField("slot", isEqualTo: slot)
            .getDocuments()

        if !existing.documents.isEmpty {
            throw NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "This slot is already taken"])
        }

        let data: [String: Any] = [
            "eventId": eventId,
            "job": job,
            "slot": slot,
            "userEmail": userEmail,
            "userName": userName,
            "signedUpAt": Timestamp(date: Date()),
            "serviceHoursClaimed": false,
            "eventDate": Timestamp(date: eventDate),
            "eventDescription": eventDescription
        ]
        try await db.collection("scoreboardSignups").addDocument(data: data)
    }

    func claimServiceHours(signupId: String) async throws {
        try await db.collection("scoreboardSignups").document(signupId).updateData([
            "serviceHoursClaimed": true
        ])
    }

    func fetchUnclaimedPastSignups(userEmail: String) async throws -> [ScoreboardSignup] {
        let snapshot = try await db.collection("scoreboardSignups")
            .whereField("userEmail", isEqualTo: userEmail)
            .whereField("serviceHoursClaimed", isEqualTo: false)
            .getDocuments()

        let now = Date()
        return snapshot.documents.compactMap { doc -> ScoreboardSignup? in
            let data = doc.data()
            guard let eventDate = (data["eventDate"] as? Timestamp)?.dateValue(),
                  eventDate < now else { return nil }

            return ScoreboardSignup(
                id: doc.documentID,
                eventId: data["eventId"] as? String ?? "",
                job: data["job"] as? String ?? "",
                slot: data["slot"] as? Int ?? 0,
                userEmail: data["userEmail"] as? String ?? "",
                userName: data["userName"] as? String ?? "",
                signedUpAt: (data["signedUpAt"] as? Timestamp)?.dateValue() ?? Date(),
                serviceHoursClaimed: data["serviceHoursClaimed"] as? Bool ?? false,
                eventDate: eventDate,
                eventDescription: data["eventDescription"] as? String ?? ""
            )
        }
    }

    func cancelSignup(signupId: String) async throws {
        try await db.collection("scoreboardSignups").document(signupId).delete()
    }

    func fetchSignups(eventId: String) async throws -> [ScoreboardSignup] {
        let snapshot = try await db.collection("scoreboardSignups")
            .whereField("eventId", isEqualTo: eventId)
            .getDocuments()

        return snapshot.documents.map { doc in
            let data = doc.data()
            return ScoreboardSignup(
                id: doc.documentID,
                eventId: data["eventId"] as? String ?? "",
                job: data["job"] as? String ?? "",
                slot: data["slot"] as? Int ?? 0,
                userEmail: data["userEmail"] as? String ?? "",
                userName: data["userName"] as? String ?? "",
                signedUpAt: (data["signedUpAt"] as? Timestamp)?.dateValue() ?? Date(),
                serviceHoursClaimed: data["serviceHoursClaimed"] as? Bool ?? false,
                eventDate: (data["eventDate"] as? Timestamp)?.dateValue(),
                eventDescription: data["eventDescription"] as? String
            )
        }
    }

    func fetchMySignups(userEmail: String) async throws -> [ScoreboardSignup] {
        let snapshot = try await db.collection("scoreboardSignups")
            .whereField("userEmail", isEqualTo: userEmail)
            .getDocuments()

        return snapshot.documents.map { doc in
            let data = doc.data()
            return ScoreboardSignup(
                id: doc.documentID,
                eventId: data["eventId"] as? String ?? "",
                job: data["job"] as? String ?? "",
                slot: data["slot"] as? Int ?? 0,
                userEmail: data["userEmail"] as? String ?? "",
                userName: data["userName"] as? String ?? "",
                signedUpAt: (data["signedUpAt"] as? Timestamp)?.dateValue() ?? Date(),
                serviceHoursClaimed: data["serviceHoursClaimed"] as? Bool ?? false,
                eventDate: (data["eventDate"] as? Timestamp)?.dateValue(),
                eventDescription: data["eventDescription"] as? String
            )
        }
    }

    // MARK: - Assignment Resources

    struct AssignmentResource: Identifiable {
        var id: String
        var assignmentId: Int
        var url: String
        var title: String
        var type: String
        var addedBy: String
        var addedByName: String
        var addedAt: Date
    }

    static func detectResourceType(from url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("quizlet.com") { return "quizlet" }
        if lower.contains("kahoot.it") || lower.contains("kahoot.com") { return "kahoot" }
        if lower.contains("youtube.com") || lower.contains("youtu.be") { return "youtube" }
        return "other"
    }

    func submitResource(assignmentId: Int, url: String, title: String, userEmail: String, userName: String) async throws {
        let type = FirebaseService.detectResourceType(from: url)
        let data: [String: Any] = [
            "assignmentId": assignmentId,
            "url": url,
            "title": title,
            "type": type,
            "addedBy": userEmail,
            "addedByName": userName,
            "addedAt": Timestamp(date: Date())
        ]
        try await db.collection("assignmentResources").addDocument(data: data)
    }

    func fetchResources(assignmentId: Int) async throws -> [AssignmentResource] {
        let snapshot = try await db.collection("assignmentResources")
            .whereField("assignmentId", isEqualTo: assignmentId)
            .getDocuments()

        return snapshot.documents.map { doc in
            let data = doc.data()
            return AssignmentResource(
                id: doc.documentID,
                assignmentId: data["assignmentId"] as? Int ?? 0,
                url: data["url"] as? String ?? "",
                title: data["title"] as? String ?? "",
                type: data["type"] as? String ?? "other",
                addedBy: data["addedBy"] as? String ?? "",
                addedByName: data["addedByName"] as? String ?? "",
                addedAt: (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }.sorted { $0.addedAt > $1.addedAt }
    }

    func fetchResourceAssignmentIds() async throws -> Set<Int> {
        let snapshot = try await db.collection("assignmentResources").getDocuments()
        var ids = Set<Int>()
        for doc in snapshot.documents {
            if let id = doc.data()["assignmentId"] as? Int {
                ids.insert(id)
            }
        }
        return ids
    }

    func deleteResource(documentId: String) async throws {
        try await db.collection("assignmentResources").document(documentId).delete()
    }

    // MARK: - App Banner

    func fetchBanners() async throws -> [AppBanner] {
        let snapshot = try await db.collection("appConfig")
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let message = data["message"] as? String, !message.isEmpty else { return nil }
            return AppBanner(message: message, type: data["type"] as? String ?? "info")
        }
    }
}


struct Service: Identifiable {
    var id = UUID()
    var date: String
    var description: String
    var notes: String
    var hours: Double
    var schoolYear: String
    var veracrossId: Int? = nil
}

struct LocalService: Identifiable, Codable {
    var id = UUID()
    var date: String
    var description: String
    var notes: String
    var hours: Double
    var veracrossRecordId: Int? = nil
}

struct ServiceForm: Identifiable, Codable {
    var id = UUID()
    var title: String
    var dateCreated: Date
    var services: [LocalService]
    var slos: [String] = []
    var reflection1: String
    var reflection2: String
    var reflection3: String
    var taxID: String?
    var organization: String?
    var organizationKey: Int?  // Veracross organization_key value-list fk — see oakwoodOrganizationKey
}

/// One selectable outside-service organization — see FirebaseService.fetchServiceOrganizations().
struct ServiceOrganization: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var orgKey: Int
    var taxID: String?
}
