//
//  CloudSync.swift
//  School Notes
//

import Foundation
import CloudKit

/// Syncs a small Codable value through CloudKit's private database, reconciling local and
/// remote instead of blindly overwriting either side. Replaced an earlier
/// NSUbiquitousKeyValueStore-based implementation after confirming via direct device-to-device
/// testing that KVS just wasn't propagating between this app's iOS and macOS builds — KVS only
/// ever reads a local cache the OS updates on its own unknowable schedule, with no way to force
/// a live check. CloudKit's private database gives an actual "ask the server right now" fetch.
final class CloudSync<Value: Codable> {
    private let key: String
    private let merge: (Value, Value) -> Value
    private let recordType = "SyncedValue"

    init(key: String, merge: @escaping (Value, Value) -> Value) {
        self.key = key
        self.merge = merge
    }

    private var database: CKDatabase { CKContainer.default().privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: key) }

    /// Call once when local data has loaded (e.g. app launch, a foreground poll, or a manual
    /// refresh) to reconcile with whatever CloudKit has, and get back the merged value. Also
    /// pushes the merged result back so every device converges.
    func reconcile(local: Value) async -> Value {
        guard let remote = await remoteValue() else {
            print("[CloudSync:\(key)] reconcile: no remote value found — pushing local")
            await push(local)
            return local
        }
        let merged = merge(local, remote)
        print("[CloudSync:\(key)] reconcile: found remote value, merged with local")
        await push(merged)
        return merged
    }

    /// Call after any local mutation to push the new value to CloudKit.
    func push(_ value: Value) async {
        guard let data = try? JSONEncoder().encode(value) else {
            print("[CloudSync:\(key)] push: FAILED to encode value")
            return
        }
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["payload"] = data as CKRecordValue
        do {
            // `.changedKeys` (not the default `.ifServerRecordUnchanged`) since this record
            // usually already exists after the first push — same lesson as touchClubActivity.
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            print("[CloudSync:\(key)] push: wrote \(data.count) bytes to CloudKit")
        } catch {
            print("[CloudSync:\(key)] push: FAILED — \(error)")
        }
    }

    func remoteValue() async -> Value? {
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["payload"] as? Data else {
                print("[CloudSync:\(key)] remoteValue: record found but no payload")
                return nil
            }
            guard let decoded = try? JSONDecoder().decode(Value.self, from: data) else {
                print("[CloudSync:\(key)] remoteValue: found \(data.count) bytes but FAILED to decode")
                return nil
            }
            print("[CloudSync:\(key)] remoteValue: found \(data.count) bytes, decoded OK")
            return decoded
        } catch let error as CKError where error.code == .unknownItem {
            print("[CloudSync:\(key)] remoteValue: no record in CloudKit yet")
            return nil
        } catch {
            print("[CloudSync:\(key)] remoteValue: FAILED — \(error)")
            return nil
        }
    }

    /// Removes this value's record from CloudKit entirely — used by the debug "reset all
    /// synced data" tool, not part of normal sync flow.
    func delete() async {
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [recordID])
            print("[CloudSync:\(key)] delete: removed record from CloudKit")
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone — fine.
        } catch {
            print("[CloudSync:\(key)] delete: FAILED — \(error)")
        }
    }
}

struct CalendarSubscriptions: Codable, Equatable {
    var personalCalendarURL: String?
    var practiceCalendarURLs: [String]
}

/// A single last-write-wins entry: `value == nil` explicitly represents "deleted as of this
/// time" (a tombstone), distinct from a key simply never having existed — a real timestamp on
/// the deletion itself is what lets it correctly out-race a stale remote value on merge, instead
/// of a plain `Dictionary.merging` silently resurrecting it (removing a key locally is invisible
/// to a dictionary union — only the *presence* of a value can be merged, not its absence).
struct LWW<T: Codable>: Codable {
    var value: T?
    var updatedAt: Date
}

/// Merges two last-write-wins dictionaries key by key, keeping whichever side's entry has the
/// later `updatedAt` — correct regardless of which device is doing the reconciling, unlike a
/// blanket "local wins"/"remote wins" rule (which only fixes the device making the edit and
/// permanently blocks every other device from ever adopting a fresher change).
func mergeLWW<Key: Hashable, T>(_ local: [Key: LWW<T>], _ remote: [Key: LWW<T>]) -> [Key: LWW<T>] {
    var result = local
    for (key, remoteEntry) in remote {
        if let localEntry = result[key] {
            if remoteEntry.updatedAt > localEntry.updatedAt { result[key] = remoteEntry }
        } else {
            result[key] = remoteEntry
        }
    }
    return result
}

/// Wraps a list of Identifiable items with a set of "tombstoned" ids, so a
/// deletion on one device can actually stick everywhere instead of getting
/// silently re-added by a plain add-wins union the next time another device
/// (which never saw the delete) reconciles. Once an id is tombstoned it never
/// comes back — fine for something like community service records, where
/// entries are only ever added or removed, never resurrected on purpose.
struct SyncedList<Item: Codable & Identifiable>: Codable where Item.ID: Hashable & Codable {
    var items: [Item]
    var deletedIDs: Set<Item.ID>

    static func merge(_ local: SyncedList, _ remote: SyncedList) -> SyncedList {
        let deletedIDs = local.deletedIDs.union(remote.deletedIDs)
        var byID: [Item.ID: Item] = [:]
        for item in remote.items { byID[item.id] = item }
        for item in local.items { byID[item.id] = item }   // local wins on any content differences
        let items = byID.values.filter { !deletedIDs.contains($0.id) }
        return SyncedList(items: Array(items), deletedIDs: deletedIDs)
    }
}
