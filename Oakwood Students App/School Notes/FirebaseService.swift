//
//  FirebaseService.swift
//  School Notes
//
//  Created by Luke Titi on 1/30/26.
//

import Foundation
import FirebaseFirestore

// MARK: - FirebaseService (Handles all Firestore operations)
class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Service Hours Forms

    func submitServiceForm(_ form: ServiceForm, studentId: String, studentName: String) async throws {
        let data: [String: Any] = [
            "studentId": studentId,
            "studentName": studentName,
            "title": form.title,
            "status": "pending",
            "submittedAt": Timestamp(date: form.dateCreated),
            "totalHours": form.services.reduce(0) { $0 + $1.hours },
            "reflection1": form.reflection1,
            "reflection2": form.reflection2,
            "reflection3": form.reflection3,
            "taxID": form.taxID ?? "",
            "services": form.services.map { [
                "date": $0.date,
                "notes": $0.notes,
                "hours": $0.hours,
                "description": $0.description
            ]}
        ]
        try await db.collection("serviceForms").addDocument(data: data)
    }

    func fetchMyServiceForms(studentId: String) async throws -> [SubmittedForm] {
        // Note: Removed orderBy because it requires a composite index in Firestore
        // We sort in memory instead after fetching
        let snapshot = try await db.collection("serviceForms")
            .whereField("studentId", isEqualTo: studentId)
            .getDocuments()

        let forms = snapshot.documents.compactMap { doc -> SubmittedForm? in
            let data = doc.data()
            let servicesData = data["services"] as? [[String: Any]] ?? []
            let services = servicesData.map { s in
                LocalService(
                    date: s["date"] as? String ?? "",
                    description: s["description"] as? String ?? "",
                    notes: s["notes"] as? String ?? "",
                    hours: s["hours"] as? Double ?? 0
                )
            }
            return SubmittedForm(
                id: doc.documentID,
                title: data["title"] as? String ?? "Untitled",
                status: data["status"] as? String ?? "pending",
                submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue() ?? Date(),
                totalHours: data["totalHours"] as? Double ?? 0,
                reflection1: data["reflection1"] as? String ?? "",
                reflection2: data["reflection2"] as? String ?? "",
                reflection3: data["reflection3"] as? String ?? "",
                taxID: data["taxID"] as? String ?? "",
                services: services
            )
        }
        // Sort by date descending (newest first) in memory
        return forms.sorted { $0.submittedAt > $1.submittedAt }
    }

    // MARK: - Real-time listener for form status updates
    func listenForFormUpdates(studentId: String, onChange: @escaping ([SubmittedForm]) -> Void) -> ListenerRegistration {
        return db.collection("serviceForms")
            .whereField("studentId", isEqualTo: studentId)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let forms = documents.compactMap { doc -> SubmittedForm? in
                    let data = doc.data()
                    let servicesData = data["services"] as? [[String: Any]] ?? []
                    let services = servicesData.map { s in
                        LocalService(
                            date: s["date"] as? String ?? "",
                            description: s["description"] as? String ?? "",
                            notes: s["notes"] as? String ?? "",
                            hours: s["hours"] as? Double ?? 0
                        )
                    }
                    return SubmittedForm(
                        id: doc.documentID,
                        title: data["title"] as? String ?? "Untitled",
                        status: data["status"] as? String ?? "pending",
                        submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue() ?? Date(),
                        totalHours: data["totalHours"] as? Double ?? 0,
                        reflection1: data["reflection1"] as? String ?? "",
                        reflection2: data["reflection2"] as? String ?? "",
                        reflection3: data["reflection3"] as? String ?? "",
                        taxID: data["taxID"] as? String ?? "",
                        services: services
                    )
                }
                // Sort by date descending (newest first) in memory
                onChange(forms.sorted { $0.submittedAt > $1.submittedAt })
            }
    }
}

// MARK: - SubmittedForm (Form that's been sent to Firebase)
struct SubmittedForm: Identifiable {
    var id: String
    var title: String
    var status: String          // "pending", "approved", "rejected"
    var submittedAt: Date
    var totalHours: Double
    var reflection1: String
    var reflection2: String
    var reflection3: String
    var taxID: String
    var services: [LocalService]
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
}
