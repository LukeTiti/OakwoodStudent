//
//  Mac_ClubsView.swift
//  School Notes
//
import SwiftUI

struct Mac_ClubsView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var clubs: [Club] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var newClubName = ""

    private var userEmail: String { appInfo.googleVM.userEmail }
    private var isSuperAdmin: Bool { userEmail.lowercased() == superAdminEmail }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading clubs…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if clubs.isEmpty {
                ContentUnavailableView("No Clubs Yet", systemImage: "person.3")
            } else {
                List(clubs) { club in
                    NavigationLink {
                        Mac_ClubDetailView(
                            club: club,
                            onUpdate: { updated in if let i = clubs.firstIndex(where: { $0.id == updated.id }) { clubs[i] = updated } },
                            onDelete: { clubs.removeAll { $0.id == club.id } }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(club.name).font(.body.weight(.semibold))
                            let s = club.meetingScheduleDisplay
                            if !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Clubs")
        .toolbar {
            if isSuperAdmin {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
        }
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

// MARK: - Club Detail

struct Mac_ClubDetailView: View {
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
        List {
            if !club.description.isEmpty || !club.meetingScheduleDisplay.isEmpty || !club.meetingLocation.isEmpty {
                Section {
                    if !club.description.isEmpty { Text(club.description).font(.subheadline).foregroundStyle(.secondary) }
                    let s = club.meetingScheduleDisplay
                    if !s.isEmpty { Label(s, systemImage: "clock").font(.subheadline) }
                    if !club.meetingLocation.isEmpty { Label(club.meetingLocation, systemImage: "mappin.circle").font(.subheadline) }
                }
            }

            if !club.officers.isEmpty {
                Section("Officers") {
                    ForEach(club.officers) { o in
                        HStack(spacing: 12) {
                            Mac_DirectoryPhoto(urlString: o.photoURL, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.name).font(.body)
                                Text(o.role).font(.caption).foregroundStyle(.secondary)
                                if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if !o.email.isEmpty {
                                Button { openExternalURL("mailto:\(o.email)") } label: {
                                    Image(systemName: "envelope").foregroundStyle(.blue)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }

            Section {
                if isLoadingAnnouncements { HStack { Spacer(); ProgressView(); Spacer() } }
                else if announcements.isEmpty { Text("No announcements").foregroundStyle(.secondary).font(.subheadline) }
                else {
                    ForEach(announcements) { ann in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ann.title).font(.body.weight(.semibold))
                            if !ann.message.isEmpty { Text(ann.message).font(.subheadline).foregroundStyle(.secondary) }
                            HStack {
                                Text(ann.authorName).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(ann.postedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions { if canEdit { deleteAnnouncementButton(ann) } }
                    }
                }
                if canEdit { Button { showAddAnnouncement = true } label: { Label("Post Announcement", systemImage: "megaphone") } }
            } header: { Text("Announcements") }

            Section {
                if isLoadingEvents { HStack { Spacer(); ProgressView(); Spacer() } }
                else if upcomingEvents.isEmpty { Text("No upcoming events").foregroundStyle(.secondary).font(.subheadline) }
                else {
                    ForEach(upcomingEvents) { event in
                        Mac_ClubEventRow(event: event).swipeActions { if canEdit { eventSwipeActions(event) } }
                    }
                }
                if canEdit { Button { showAddEvent = true } label: { Label("Add Event", systemImage: "plus.circle") } }
            } header: { Text("Upcoming Events") }

            if !pastEvents.isEmpty {
                Section("Past Events") {
                    ForEach(pastEvents) { event in
                        Mac_ClubEventRow(event: event).swipeActions { if canEdit { deleteEventButton(event) } }
                    }
                }
            }
        }
        .navigationTitle(club.name)
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
        .sheet(isPresented: $showEdit) {
            Mac_ClubEditView(club: club) { club = $0; onUpdate($0) }
                .frame(minWidth: 480, minHeight: 480)
        }
        .sheet(isPresented: $showManageEditors) {
            Mac_ClubEditorManagerView(club: $club) { Task { try? await FirebaseService.shared.updateClub(club) } }
                .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(isPresented: $showAddEvent) {
            Mac_ClubEventFormView(clubId: club.id, event: nil) { await loadEvents() }
                .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(item: $editingEvent) { event in
            Mac_ClubEventFormView(clubId: club.id, event: event) { await loadEvents() }
                .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(isPresented: $showAddAnnouncement) {
            Mac_ClubAnnouncementFormView(clubId: club.id, authorName: appInfo.googleVM.userName) { await loadAnnouncements() }
                .frame(minWidth: 420, minHeight: 300)
        }
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

private struct Mac_ClubEventRow: View {
    let event: ClubEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.body.weight(.semibold))
            Label(event.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundStyle(.secondary) }
            if !event.description.isEmpty { Text(event.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(.vertical, 4)
    }
}

// MARK: - Club Edit View

private let macClubWeekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

private struct Mac_ClubEditView: View {
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
                    ForEach(macClubWeekDays, id: \.self) { day in
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
                            Text(o.role).font(.caption).foregroundStyle(.secondary)
                            if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 2)
                        .swipeActions { Button(role: .destructive) { club.officers.removeAll { $0.id == o.id } } label: { Label("Remove", systemImage: "trash") } }
                    }
                    Button { showOfficerPicker = true } label: { Label("Add Officer from Directory", systemImage: "person.badge.plus") }
                }
            }
            .navigationTitle("Edit Club")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(club.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showOfficerPicker) {
                Mac_ClubDirectoryPickerView(title: "Add Officer") { person in
                    pendingPerson = person; roleInput = ""
                }
                .frame(minWidth: 380, minHeight: 420)
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

// MARK: - Shared Directory Picker (Mac)

private struct Mac_ClubDirectoryPickerView: View {
    let title: String
    var emailOnly: Bool = false
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
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search by name", text: $searchText)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .onChange(of: searchText) { _, _ in triggerSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .padding()

                if isLoading { Spacer(); ProgressView("Searching..."); Spacer() }
                else if results.isEmpty && !searchText.isEmpty { Spacer(); Text("No results found").foregroundStyle(.secondary); Spacer() }
                else if searchText.isEmpty { Spacer(); Text("Search for a student").foregroundStyle(.secondary).padding(); Spacer() }
                else {
                    List(results) { person in
                        Button {
                            onSelect(person)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Mac_DirectoryPhoto(urlString: person.photoURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.displayName).font(.body).foregroundStyle(.primary)
                                    if let email = person.studentEmail { Text(email).font(.caption).foregroundStyle(.secondary) }
                                    if !person.grade.isEmpty { Text(person.grade).font(.caption2).foregroundStyle(.secondary) }
                                }
                            }.padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
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

private struct Mac_ClubEventFormView: View {
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
            .navigationTitle(event == nil ? "Add Event" : "Edit Event")
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

private struct Mac_ClubAnnouncementFormView: View {
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
            .navigationTitle("Post Announcement")
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

private struct Mac_ClubEditorManagerView: View {
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
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section { Button("Add Editor from Directory") { showPicker = true } }
            }
            .navigationTitle("Manage Editors")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPicker) {
                Mac_ClubDirectoryPickerView(title: "Add Editor", emailOnly: true) { person in
                    if let email = person.studentEmail, !club.editors.contains(email) { club.editors.append(email); onUpdate() }
                }
                .frame(minWidth: 380, minHeight: 420)
            }
        }
    }
}
