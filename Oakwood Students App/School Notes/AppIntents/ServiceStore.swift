import Foundation

/// Mirrors AppInfo's localServices persistence (Observable Class.swift's `localServices`
/// didSet) exactly — same UserDefaults.standard key, same plain [LocalService] encoding — so a
/// quick-logged Siri entry shows up in the app's "Logged Hours" section next time it loads, the
/// same way a manually-added entry already does. Safe without a timestamp stamp (unlike
/// GradeStore.setCompletion's assignmentInfoTimestamps fix): localServices reconciles via
/// SyncedList.merge, a union of both sides by id, not a last-write-wins overwrite — so a fresh
/// entry here can't be silently dropped by the next reconcile, only ever added to.
enum ServiceStore {
    static func localServices() -> [LocalService] {
        guard let data = UserDefaults.standard.data(forKey: "serviceToSubmit"),
              let decoded = try? JSONDecoder().decode([LocalService].self, from: data) else { return [] }
        return decoded
    }

    /// Adds a new quick-logged entry — same shape a student would create by hand via the
    /// Community Service tab's "Log Hours" sheet. It sits in "Logged Hours" until the student
    /// selects it (and others) in-app to build a real submitted form with reflections and a
    /// supervisor to sign — Siri can't reasonably collect those by voice.
    @discardableResult
    static func addServiceEntry(date: String, description: String, notes: String, hours: Double) -> LocalService {
        var services = localServices()
        let entry = LocalService(date: date, description: description, notes: notes, hours: hours)
        services.append(entry)
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "serviceToSubmit")
        }
        return entry
    }
}
