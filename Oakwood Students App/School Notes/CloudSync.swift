//
//  CloudSync.swift
//  School Notes
//

import Foundation

/// Syncs a small Codable value through iCloud's key-value store, reconciling
/// local and remote instead of blindly overwriting either side. Not for large
/// data — NSUbiquitousKeyValueStore caps total storage around 1MB, which is
/// orders of magnitude more than any of this app's synced values need.
final class CloudSync<Value: Codable> {
    private let key: String
    private let merge: (Value, Value) -> Value
    private let store = NSUbiquitousKeyValueStore.default

    init(key: String, merge: @escaping (Value, Value) -> Value) {
        self.key = key
        self.merge = merge
    }

    /// Call once when local data has loaded (e.g. app launch) to reconcile
    /// with whatever iCloud has, and get back the merged value. Also pushes
    /// the merged result back to iCloud so every device converges.
    func reconcile(local: Value) -> Value {
        guard let remote = remoteValue() else {
            push(local)
            return local
        }
        let merged = merge(local, remote)
        push(merged)
        return merged
    }

    /// Call after any local mutation to push the new value to iCloud.
    func push(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.set(data, forKey: key)
    }

    func remoteValue() -> Value? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}

struct CalendarSubscriptions: Codable, Equatable {
    var personalCalendarURL: String?
    var practiceCalendarURLs: [String]
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
