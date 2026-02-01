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
