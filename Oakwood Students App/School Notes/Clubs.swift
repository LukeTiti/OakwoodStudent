//
//  Clubs.swift
//  School Notes
//
import SwiftUI
import FirebaseFirestore

// MARK: - Models

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

// MARK: - FirebaseService Extension

private let superAdminEmail = "lukti28@oakwoodstudent.org"

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
        try await clubRef(club.id).setData([
            "name": club.name, "description": club.description,
            "meetingDays": club.meetingDays, "meetingFrequency": club.meetingFrequency,
            "meetingTime": club.meetingTime, "meetingLocation": club.meetingLocation,
            "editors": club.editors,
            "officers": club.officers.map { o -> [String: Any] in
                var d: [String: Any] = ["id": o.id, "name": o.name, "role": o.role, "email": o.email]
                if let p = o.photoURL { d["photoURL"] = p }
                return d
            }
        ], merge: true)
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
                    editors: d["editors"] as? [String] ?? [], officers: officers)
    }
}

// MARK: - Clubs List View

struct ClubsView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var clubs: [Club] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var newClubName = ""

    private var userEmail: String { appInfo.googleVM.userEmail }
    private var isSuperAdmin: Bool { userEmail.lowercased() == superAdminEmail }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clubs").font(.largeTitle.bold())
                Spacer()
                if isSuperAdmin {
                    Button { showCreate = true } label: { Image(systemName: "plus") }.font(.title3)
                }
            }
            .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            if isLoading {
                Spacer(); ProgressView("Loading clubs..."); Spacer()
            } else if clubs.isEmpty {
                Spacer(); Text("No clubs yet").foregroundColor(.secondary); Spacer()
            } else {
                List(clubs) { club in
                    NavigationLink(destination: ClubDetailView(club: club,
                        onUpdate: { updated in if let i = clubs.firstIndex(where: { $0.id == updated.id }) { clubs[i] = updated } },
                        onDelete: { clubs.removeAll { $0.id == club.id } }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(club.name).font(.body.weight(.semibold))
                            let s = club.meetingScheduleDisplay
                            if !s.isEmpty { Text(s).font(.caption).foregroundColor(.secondary) }
                        }.padding(.vertical, 2)
                    }
                }
                .refreshable { await loadClubs() }
            }
        }
        .navigationTitle("")
        .alert("New Club", isPresented: $showCreate) {
            TextField("Club name", text: $newClubName)
            Button("Create") { Task { await createClub() } }
            Button("Cancel", role: .cancel) { newClubName = "" }
        }
        .onAppear { Task { await loadClubs() } }
    }

    private func loadClubs() async {
        isLoading = clubs.isEmpty
        clubs = (try? await FirebaseService.shared.fetchClubs()) ?? []
        isLoading = false
    }

    private func createClub() async {
        let name = newClubName.trimmingCharacters(in: .whitespaces); newClubName = ""
        guard !name.isEmpty, let club = try? await FirebaseService.shared.createClub(name: name, creatorEmail: userEmail) else { return }
        clubs.append(club); clubs.sort { $0.name < $1.name }
    }
}

// MARK: - Club Detail View

struct ClubDetailView: View {
    @State var club: Club
    var onUpdate: (Club) -> Void
    var onDelete: () -> Void
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss

    @State private var events: [ClubEvent] = []
    @State private var announcements: [ClubAnnouncement] = []
    @State private var isLoadingEvents = true
    @State private var isLoadingAnnouncements = true
    @State private var showEdit = false
    @State private var showManageEditors = false
    @State private var showAddEvent = false
    @State private var showAddAnnouncement = false
    @State private var editingEvent: ClubEvent? = nil

    private var userEmail: String { appInfo.googleVM.userEmail }
    private var isSuperAdmin: Bool { userEmail.lowercased() == superAdminEmail }
    private var canEdit: Bool { isSuperAdmin || club.editors.contains(userEmail) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var upcomingEvents: [ClubEvent] { events.filter { $0.date >= today } }
    private var pastEvents: [ClubEvent] { events.filter { $0.date < today }.reversed() }

    var body: some View {
        VStack(spacing: 0) {
            Text(club.name).font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            List {
                // Info
                if !club.description.isEmpty || !club.meetingScheduleDisplay.isEmpty || !club.meetingLocation.isEmpty {
                    Section {
                        if !club.description.isEmpty { Text(club.description).font(.subheadline).foregroundColor(.secondary) }
                        let s = club.meetingScheduleDisplay
                        if !s.isEmpty { Label(s, systemImage: "clock").font(.subheadline) }
                        if !club.meetingLocation.isEmpty { Label(club.meetingLocation, systemImage: "mappin.circle").font(.subheadline) }
                    }
                }

                // Officers
                if !club.officers.isEmpty {
                    Section("Officers") {
                        ForEach(club.officers) { o in
                            HStack(spacing: 12) {
                                DirectoryPhoto(urlString: o.photoURL, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.name).font(.body)
                                    Text(o.role).font(.caption).foregroundColor(.secondary)
                                    if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundColor(.secondary) }
                                }
                                Spacer()
                                if !o.email.isEmpty {
                                    Button { openClubURL("mailto:\(o.email)") } label: {
                                        Image(systemName: "envelope").foregroundColor(.blue)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }

                // Announcements
                Section {
                    if isLoadingAnnouncements { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if announcements.isEmpty { Text("No announcements").foregroundColor(.secondary).font(.subheadline) }
                    else {
                        ForEach(announcements) { ann in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ann.title).font(.body.weight(.semibold))
                                if !ann.message.isEmpty { Text(ann.message).font(.subheadline).foregroundColor(.secondary) }
                                HStack {
                                    Text(ann.authorName).font(.caption2).foregroundColor(.secondary)
                                    Spacer()
                                    Text(ann.postedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .swipeActions { if canEdit { deleteAnnouncementButton(ann) } }
                        }
                    }
                    if canEdit { Button { showAddAnnouncement = true } label: { Label("Post Announcement", systemImage: "megaphone") } }
                } header: { Text("Announcements") }

                // Upcoming Events
                Section {
                    if isLoadingEvents { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if upcomingEvents.isEmpty { Text("No upcoming events").foregroundColor(.secondary).font(.subheadline) }
                    else {
                        ForEach(upcomingEvents) { event in
                            ClubEventRow(event: event).swipeActions { if canEdit { eventSwipeActions(event) } }
                        }
                    }
                    if canEdit { Button { showAddEvent = true } label: { Label("Add Event", systemImage: "plus.circle") } }
                } header: { Text("Upcoming Events") }

                if !pastEvents.isEmpty {
                    Section("Past Events") {
                        ForEach(pastEvents) { event in
                            ClubEventRow(event: event).swipeActions { if canEdit { deleteEventButton(event) } }
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .inlineNavigationBarTitle()
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("Edit Club Info") { showEdit = true }
                        if isSuperAdmin {
                            Button("Manage Editors") { showManageEditors = true }
                            Button("Delete Club", role: .destructive) {
                                Task { try? await FirebaseService.shared.deleteClub(clubId: club.id); onDelete(); dismiss() }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showEdit) { ClubEditView(club: club) { club = $0; onUpdate($0) } }
        .sheet(isPresented: $showManageEditors) { ClubEditorManagerView(club: $club) { Task { try? await FirebaseService.shared.updateClub(club) } } }
        .sheet(isPresented: $showAddEvent) { ClubEventFormView(clubId: club.id, event: nil) { await loadEvents() } }
        .sheet(item: $editingEvent) { ClubEventFormView(clubId: club.id, event: $0) { await loadEvents() } }
        .sheet(isPresented: $showAddAnnouncement) { ClubAnnouncementFormView(clubId: club.id, authorName: appInfo.googleVM.userName) { await loadAnnouncements() } }
        .onAppear { Task { await loadEvents(); await loadAnnouncements() } }
    }

    @ViewBuilder private func deleteEventButton(_ event: ClubEvent) -> some View {
        Button(role: .destructive) { Task { try? await FirebaseService.shared.deleteClubEvent(clubId: club.id, eventId: event.id); await loadEvents() } } label: { Label("Delete", systemImage: "trash") }
    }
    @ViewBuilder private func eventSwipeActions(_ event: ClubEvent) -> some View {
        deleteEventButton(event)
        Button { editingEvent = event } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
    }
    @ViewBuilder private func deleteAnnouncementButton(_ ann: ClubAnnouncement) -> some View {
        Button(role: .destructive) { Task { try? await FirebaseService.shared.deleteClubAnnouncement(clubId: club.id, announcementId: ann.id); await loadAnnouncements() } } label: { Label("Delete", systemImage: "trash") }
    }

    private func loadEvents() async {
        isLoadingEvents = true
        events = (try? await FirebaseService.shared.fetchClubEvents(clubId: club.id)) ?? []
        isLoadingEvents = false
    }
    private func loadAnnouncements() async {
        isLoadingAnnouncements = true
        announcements = (try? await FirebaseService.shared.fetchClubAnnouncements(clubId: club.id)) ?? []
        isLoadingAnnouncements = false
    }
}

// MARK: - Club Event Row

struct ClubEventRow: View {
    let event: ClubEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.body.weight(.semibold))
            Label(event.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary) }
            if !event.description.isEmpty { Text(event.description).font(.caption).foregroundColor(.secondary).lineLimit(2) }
        }.padding(.vertical, 4)
    }
}

// MARK: - Club Edit View

private let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

struct ClubEditView: View {
    @State var club: Club
    var onSave: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showOfficerPicker = false
    @State private var pendingPerson: DirectoryPerson? = nil
    @State private var roleInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    TextField("Club name", text: $club.name)
                    TextField("Description", text: $club.description, axis: .vertical).lineLimit(3...6)
                }
                Section("Meeting Days") {
                    ForEach(weekDays, id: \.self) { day in
                        Toggle(day, isOn: Binding(
                            get: { club.meetingDays.contains(day) },
                            set: { on in if on { club.meetingDays.append(day) } else { club.meetingDays.removeAll { $0 == day } } }
                        ))
                    }
                }
                Section("Meeting Schedule") {
                    Picker("Frequency", selection: $club.meetingFrequency) {
                        Text("Weekly").tag("Weekly")
                        Text("Bi-weekly").tag("Bi-weekly")
                        Text("Varies").tag("Varies")
                    }
                    TextField("Time (e.g. 3:30 PM)", text: $club.meetingTime)
                    TextField("Location", text: $club.meetingLocation)
                }
                Section("Officers") {
                    ForEach(club.officers) { o in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.name).font(.body)
                            Text(o.role).font(.caption).foregroundColor(.secondary)
                            if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundColor(.secondary) }
                        }
                        .padding(.vertical, 2)
                        .swipeActions { Button(role: .destructive) { club.officers.removeAll { $0.id == o.id } } label: { Label("Remove", systemImage: "trash") } }
                    }
                    Button { showOfficerPicker = true } label: { Label("Add Officer from Directory", systemImage: "person.badge.plus") }
                }
            }
            .navigationTitle("Edit Club").inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(club.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showOfficerPicker) {
                ClubDirectoryPickerView(title: "Add Officer", emailOnly: false) { person in
                    pendingPerson = person; roleInput = ""
                }
            }
            .alert("What is their role?", isPresented: Binding(get: { pendingPerson != nil }, set: { if !$0 { pendingPerson = nil } })) {
                TextField("e.g. President, Secretary", text: $roleInput)
                Button("Add") {
                    guard let p = pendingPerson, !roleInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    club.officers.append(ClubOfficer(id: UUID().uuidString, name: p.displayName,
                        role: roleInput.trimmingCharacters(in: .whitespaces), email: p.studentEmail ?? "", photoURL: p.photoURL))
                    pendingPerson = nil
                }
                Button("Cancel", role: .cancel) { pendingPerson = nil }
            }
        }
    }

    private func save() async {
        isSaving = true
        try? await FirebaseService.shared.updateClub(club)
        onSave(club); dismiss()
    }
}

// MARK: - Shared Directory Picker

struct ClubDirectoryPickerView: View {
    let title: String
    let emailOnly: Bool
    var onSelect: (DirectoryPerson) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [DirectoryPerson] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search by name", text: $searchText)
                        .textFieldStyle(.plain).autocorrectionDisabled().textInputAutocapitalization(.words)
                        .onChange(of: searchText) { _, _ in triggerSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(10).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10)).padding()

                if isLoading { Spacer(); ProgressView("Searching..."); Spacer() }
                else if results.isEmpty && !searchText.isEmpty { Spacer(); Text("No results found").foregroundColor(.secondary); Spacer() }
                else if searchText.isEmpty { Spacer(); Text("Search for a student").foregroundColor(.secondary).padding(); Spacer() }
                else {
                    List(results) { person in
                        Button {
                            onSelect(person)
                            if !emailOnly { dismiss() }
                            else { dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                DirectoryPhoto(urlString: person.photoURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.displayName).font(.body).foregroundColor(.primary)
                                    if let email = person.studentEmail { Text(email).font(.caption).foregroundColor(.secondary) }
                                    if !person.grade.isEmpty { Text(person.grade).font(.caption2).foregroundColor(.secondary) }
                                }
                            }.padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(title).inlineNavigationBarTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run { isLoading = true }
            let parts = searchText.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            var queryItems: [URLQueryItem] = []
            if let first = parts.first, !first.isEmpty { queryItems.append(URLQueryItem(name: "directory_entry[first_name]", value: first)) }
            if parts.count > 1 { queryItems.append(URLQueryItem(name: "directory_entry[last_name]", value: parts.dropFirst().joined(separator: " "))) }
            let (people, _) = await fetchDirectoryPage1(queryItems: queryItems)
            guard !Task.isCancelled else { return }
            await MainActor.run { results = emailOnly ? people.filter { $0.studentEmail != nil } : people; isLoading = false }
        }
    }
}

// MARK: - Event & Announcement Forms

struct ClubEventFormView: View {
    let clubId: String
    let event: ClubEvent?
    var onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var location = ""
    @State private var desc = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event title", text: $title)
                    DatePicker("Date & Time", selection: $date)
                    TextField("Location (optional)", text: $location)
                    TextField("Description (optional)", text: $desc, axis: .vertical).lineLimit(3...5)
                }
            }
            .navigationTitle(event == nil ? "Add Event" : "Edit Event").inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { if let e = event { title = e.title; date = e.date; location = e.location; desc = e.description } }
        }
    }

    private func save() async {
        isSaving = true
        try? await FirebaseService.shared.saveClubEvent(clubId: clubId, event: ClubEvent(id: event?.id ?? "", title: title, date: date, location: location, description: desc))
        await onSave(); dismiss()
    }
}

struct ClubAnnouncementFormView: View {
    let clubId: String
    let authorName: String
    var onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Message (optional)", text: $message, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle("Post Announcement").inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        try? await FirebaseService.shared.saveClubAnnouncement(clubId: clubId, ann: ClubAnnouncement(id: "", title: title, message: message, postedAt: Date(), authorName: authorName))
        await onSave(); dismiss()
    }
}

// MARK: - Editor Manager

struct ClubEditorManagerView: View {
    @Binding var club: Club
    var onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Current Editors") {
                    ForEach(club.editors, id: \.self) { email in
                        HStack {
                            Text(email)
                            Spacer()
                            if email.lowercased() != superAdminEmail {
                                Button(role: .destructive) { club.editors.removeAll { $0 == email }; onUpdate() } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section { Button("Add Editor from Directory") { showPicker = true } }
            }
            .navigationTitle("Manage Editors").inlineNavigationBarTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPicker) {
                ClubDirectoryPickerView(title: "Add Editor", emailOnly: true) { person in
                    if let email = person.studentEmail, !club.editors.contains(email) { club.editors.append(email); onUpdate() }
                }
            }
        }
    }
}

// MARK: - URL Helper

private func openClubURL(_ string: String) {
    guard let url = URL(string: string) else { return }
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
}
