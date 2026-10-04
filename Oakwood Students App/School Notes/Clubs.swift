//
//  Clubs.swift
//  School Notes
//
import SwiftUI
import PhotosUI

// MARK: - Clubs List View

struct ClubsView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var clubs: [Club] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var newClubName = ""

    private var userEmail: String { appInfo.googleVM.userEmail }
    private var isSuperAdmin: Bool { userEmail.lowercased() == superAdminEmail }
    // Followed clubs sort to the top; each group keeps alphabetical order.
    private var sortedClubs: [Club] {
        clubs.sorted {
            (appInfo.followedClubIDs.contains($0.id) ? 0 : 1, $0.name) < (appInfo.followedClubIDs.contains($1.id) ? 0 : 1, $1.name)
        }
    }

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
                List(sortedClubs) { club in
                    NavigationLink(destination: ClubDetailView(club: club,
                        onUpdate: { updated in if let i = clubs.firstIndex(where: { $0.id == updated.id }) { clubs[i] = updated } },
                        onDelete: { clubs.removeAll { $0.id == club.id } }
                    )) {
                        HStack(spacing: 12) {
                            ClubSwatchView(club: club)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(club.name).font(.body.weight(.semibold))
                                let s = club.meetingScheduleDisplay
                                if !s.isEmpty { Text(s).font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if appInfo.followedClubIDs.contains(club.id) {
                                Image(systemName: "bell.fill").font(.caption).foregroundColor(.secondary)
                            }
                            if appInfo.clubsWithUnreadAnnouncements.contains(club.id) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                            }
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
        .onAppear {
            Task { await loadClubs() }
            Task { await appInfo.refreshUnreadClubBadges() }
        }
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
    @State private var attendeesByEvent: [String: [ClubEventAttendee]] = [:]
    @State private var isLoadingEvents = true
    @State private var isLoadingAnnouncements = true
    @State private var showEdit = false
    @State private var showManageEditors = false
    @State private var showAddEvent = false
    @State private var showAddAnnouncement = false
    @State private var editingEvent: ClubEvent? = nil
    @State private var managingAttendanceFor: ClubEvent? = nil
    @State private var cookiesReady = false

    private var userEmail: String { appInfo.googleVM.userEmail }
    private var isSuperAdmin: Bool { userEmail.lowercased() == superAdminEmail }
    private var canEdit: Bool { isSuperAdmin || club.editors.contains(userEmail) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var upcomingEvents: [ClubEvent] { events.filter { $0.date >= today } }
    private var pastEvents: [ClubEvent] { events.filter { $0.date < today }.reversed() }

    private var themeGradient: LinearGradient? { ClubTheme.preset(id: club.themeID)?.gradient }

    var body: some View {
        VStack(spacing: 0) {
            Text(club.name).font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

            List {
                if club.hasCustomBackground {
                    ClubCloudImage(clubId: club.id, version: club.backgroundVersion)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                }
                // About — also surfaces the latest announcement right under the description,
                // since iOS has less room to scroll all the way down to the full list for it.
                if !club.description.isEmpty || announcements.first != nil {
                    Section {
                        if !club.description.isEmpty {
                            Text(club.description)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        if let latest = announcements.first {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(latest.title).font(.body.weight(.semibold))
                                if !latest.message.isEmpty { Text(latest.message).font(.subheadline).foregroundColor(.secondary) }
                                HStack {
                                    Text(latest.authorName).font(.caption2).foregroundColor(.secondary)
                                    Spacer()
                                    Text(latest.postedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                // Info
                if !club.meetingScheduleDisplay.isEmpty || !club.meetingLocation.isEmpty {
                    Section {
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
                                OfficerPhoto(officer: o, size: 44, isReady: cookiesReady)
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

                // Upcoming Events
                Section {
                    if isLoadingEvents { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if upcomingEvents.isEmpty { Text("No upcoming events").foregroundColor(.secondary).font(.subheadline) }
                    else {
                        ForEach(upcomingEvents) { event in
                            ClubEventRow(event: event, attendees: attendeesByEvent[event.id] ?? [], isPast: false, canEdit: canEdit,
                                isGoing: attendeesByEvent[event.id]?.first(where: { $0.id == userEmail })?.rsvped ?? false,
                                onToggleRSVP: { toggleRSVP(for: event) },
                                onManageAttendance: { managingAttendanceFor = event })
                                .swipeActions { if canEdit { eventSwipeActions(event) } }
                        }
                    }
                    if canEdit { Button { showAddEvent = true } label: { Label("Add Event", systemImage: "plus.circle") } }
                } header: { Text("Upcoming Events") }

                // Past Announcements
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
                } header: { Text("Past Announcements") }

                if !pastEvents.isEmpty {
                    Section("Past Events") {
                        ForEach(pastEvents) { event in
                            ClubEventRow(event: event, attendees: attendeesByEvent[event.id] ?? [], isPast: true, canEdit: canEdit,
                                isGoing: false, onToggleRSVP: {}, onManageAttendance: { managingAttendanceFor = event })
                                .swipeActions { if canEdit { deleteEventButton(event) } }
                        }
                    }
                }
            }
            .scrollContentBackground(themeGradient == nil ? .automatic : .hidden)
        }
        .background { themeGradient?.ignoresSafeArea() }
        .navigationTitle("")
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { appInfo.toggleFollowingClub(club.id) } label: {
                    Image(systemName: appInfo.followedClubIDs.contains(club.id) ? "bell.fill" : "bell")
                }
            }
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
        .sheet(isPresented: $showAddEvent) { ClubEventFormView(clubId: club.id, clubName: club.name, authorName: appInfo.googleVM.userName, event: nil) { await loadEvents() } }
        .sheet(item: $editingEvent) { ClubEventFormView(clubId: club.id, clubName: club.name, authorName: appInfo.googleVM.userName, event: $0) { await loadEvents() } }
        .sheet(isPresented: $showAddAnnouncement) { ClubAnnouncementFormView(clubId: club.id, clubName: club.name, authorName: appInfo.googleVM.userName) { await loadAnnouncements() } }
        .sheet(item: $managingAttendanceFor) { event in
            ClubEventAttendanceView(clubId: club.id, event: event, attendees: attendeesByEvent[event.id] ?? []) { updated in
                attendeesByEvent[event.id] = updated
            }
        }
        .onAppear {
            appInfo.markClubViewed(club.id)
            appInfo.clubsWithUnreadAnnouncements.remove(club.id)
            Task {
                // Officer photos are Veracross-hosted and need an authenticated session to
                // load, same as any other Veracross image/document — unlike events/announcements
                // (Firestore-backed), this view never synced cookies before, so photos silently failed.
                await appInfo.restorePersistedCookiesIntoStores()
                await syncCookies()
                cookiesReady = true
                await loadEvents()
                await loadAnnouncements()
            }
        }
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
        if appInfo.followedClubIDs.contains(club.id) { scheduleEventReminders(clubName: club.name, events: events) }
        for event in events {
            attendeesByEvent[event.id] = (try? await FirebaseService.shared.fetchClubEventAttendees(clubId: club.id, eventId: event.id)) ?? []
        }
    }

    private func toggleRSVP(for event: ClubEvent) {
        let email = userEmail, name = appInfo.googleVM.userName
        guard !email.isEmpty else { return }
        let currentlyGoing = attendeesByEvent[event.id]?.first(where: { $0.id == email })?.rsvped ?? false
        Task {
            try? await FirebaseService.shared.setClubEventRSVP(clubId: club.id, eventId: event.id, email: email, name: name, going: !currentlyGoing)
            attendeesByEvent[event.id] = (try? await FirebaseService.shared.fetchClubEventAttendees(clubId: club.id, eventId: event.id)) ?? []
        }
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
    let attendees: [ClubEventAttendee]
    let isPast: Bool
    let canEdit: Bool
    let isGoing: Bool
    var onToggleRSVP: () -> Void
    var onManageAttendance: () -> Void

    private var goingCount: Int { attendees.filter { $0.rsvped }.count }
    private var attendedCount: Int { attendees.filter { $0.attended }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.body.weight(.semibold))
            Label(event.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary) }
            if !event.description.isEmpty { Text(event.description).font(.caption).foregroundColor(.secondary).lineLimit(2) }

            HStack(spacing: 8) {
                if !isPast {
                    Button(action: onToggleRSVP) {
                        Label(isGoing ? "Going" : "RSVP", systemImage: isGoing ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(isGoing ? .green : .accentColor)
                    .controlSize(.small)
                    if goingCount > 0 { Text("\(goingCount) going").font(.caption2).foregroundColor(.secondary) }
                }
                if canEdit {
                    Button(action: onManageAttendance) {
                        Label(attendedCount > 0 ? "\(attendedCount) attended" : "Attendance", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 2)
        }.padding(.vertical, 4)
    }
}

// MARK: - Club Event Attendance

/// Lets a club editor check off who actually showed up to an event — pre-populated from RSVPs,
/// but also supports adding a walk-in who never RSVP'd via the same directory picker used for
/// officers/editors.
struct ClubEventAttendanceView: View {
    let clubId: String
    let event: ClubEvent
    @State var attendees: [ClubEventAttendee]
    var onUpdate: ([ClubEventAttendee]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showAddAttendee = false

    private var sorted: [ClubEventAttendee] { attendees.sorted { $0.name < $1.name } }

    var body: some View {
        NavigationStack {
            List {
                if attendees.isEmpty {
                    Text("No RSVPs or attendees yet").foregroundColor(.secondary)
                }
                ForEach(sorted) { attendee in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attendee.name)
                            if attendee.rsvped { Text("RSVP'd").font(.caption2).foregroundColor(.secondary) }
                        }
                        Spacer()
                        Button { toggleAttended(attendee) } label: {
                            Image(systemName: attendee.attended ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(attendee.attended ? .green : .secondary)
                                .font(.title3)
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Attendance: \(event.title)").inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button { showAddAttendee = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showAddAttendee) {
                ClubDirectoryPickerView(title: "Add Attendee", emailOnly: true) { person in
                    guard let email = person.studentEmail else { return }
                    addWalkIn(email: email, name: person.displayName)
                }
            }
        }
    }

    private func toggleAttended(_ attendee: ClubEventAttendee) {
        guard let idx = attendees.firstIndex(where: { $0.id == attendee.id }) else { return }
        attendees[idx].attended.toggle()
        let updatedAttended = attendees[idx].attended
        onUpdate(attendees)
        Task { try? await FirebaseService.shared.setClubEventAttendance(clubId: clubId, eventId: event.id, email: attendee.id, name: attendee.name, attended: updatedAttended) }
    }

    private func addWalkIn(email: String, name: String) {
        if let idx = attendees.firstIndex(where: { $0.id == email }) {
            attendees[idx].attended = true
        } else {
            attendees.append(ClubEventAttendee(id: email, name: name, rsvped: false, attended: true))
        }
        onUpdate(attendees)
        Task { try? await FirebaseService.shared.setClubEventAttendance(clubId: clubId, eventId: event.id, email: email, name: name, attended: true) }
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
    @State private var editingOfficer: ClubOfficer? = nil
    @State private var editRoleInput = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingImage = false
    @State private var uploadError: String? = nil
    @State private var officerEditMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    TextField("Club name", text: $club.name)
                    TextField("Description", text: $club.description, axis: .vertical).lineLimit(3...6)
                }
                Section("Appearance") {
                    Text("Accent Color").font(.caption).foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ThemeSwatchButton(gradient: nil, isSelected: club.themeID == nil) {
                                club.themeID = nil
                            }
                            ForEach(ClubTheme.presets) { theme in
                                ThemeSwatchButton(gradient: theme.gradient, isSelected: club.themeID == theme.id) {
                                    club.themeID = theme.id
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(club.hasCustomBackground ? "Replace Custom Background" : "Upload Custom Background", systemImage: "photo")
                    }
                    if isUploadingImage {
                        HStack { ProgressView(); Text("Uploading…").foregroundColor(.secondary) }
                    }
                    if let uploadError {
                        Text(uploadError).font(.caption).foregroundColor(.red)
                    }
                    if club.hasCustomBackground {
                        Button("Remove Custom Background", role: .destructive) { club.hasCustomBackground = false }
                    }
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
                Section {
                    ForEach(club.officers) { o in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.name).font(.body)
                                Text(o.role).font(.caption).foregroundColor(.secondary)
                                if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundColor(.secondary) }
                            }
                            Spacer()
                            Button { editingOfficer = o; editRoleInput = o.role } label: { Image(systemName: "pencil") }
                                .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                        .swipeActions { Button(role: .destructive) { club.officers.removeAll { $0.id == o.id } } label: { Label("Remove", systemImage: "trash") } }
                    }
                    .onMove { club.officers.move(fromOffsets: $0, toOffset: $1) }
                    Button { showOfficerPicker = true } label: { Label("Add Officer from Directory", systemImage: "person.badge.plus") }
                } header: {
                    HStack {
                        Text("Officers")
                        Spacer()
                        if club.officers.count > 1 { EditButton() }
                    }
                }
            }
            .environment(\.editMode, $officerEditMode)
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
            .alert("Edit Role", isPresented: Binding(get: { editingOfficer != nil }, set: { if !$0 { editingOfficer = nil } })) {
                TextField("e.g. President, Secretary", text: $editRoleInput)
                Button("Save") {
                    guard let officer = editingOfficer, !editRoleInput.trimmingCharacters(in: .whitespaces).isEmpty,
                          let idx = club.officers.firstIndex(where: { $0.id == officer.id }) else { return }
                    club.officers[idx].role = editRoleInput.trimmingCharacters(in: .whitespaces)
                    editingOfficer = nil
                }
                Button("Cancel", role: .cancel) { editingOfficer = nil }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await uploadSelectedPhoto(newItem) }
            }
        }
    }

    private func uploadSelectedPhoto(_ item: PhotosPickerItem) async {
        uploadError = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run { uploadError = "Couldn't load that photo." }
            return
        }
        await MainActor.run { isUploadingImage = true }
        let newVersion = club.backgroundVersion + 1
        do {
            try await uploadClubBackgroundImage(clubId: club.id, version: newVersion, imageData: data)
            await MainActor.run {
                club.hasCustomBackground = true
                club.backgroundVersion = newVersion
                isUploadingImage = false
            }
        } catch {
            await MainActor.run {
                uploadError = "Upload failed: \(error.localizedDescription)"
                isUploadingImage = false
            }
        }
    }

    private func save() async {
        isSaving = true
        try? await FirebaseService.shared.updateClub(club)
        onSave(club); dismiss()
    }
}

// MARK: - Theme Swatch Button

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
    let clubName: String
    let authorName: String
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
        try? await FirebaseService.shared.saveClubEvent(clubId: clubId, clubName: clubName, authorName: authorName, event: ClubEvent(id: event?.id ?? "", title: title, date: date, location: location, description: desc))
        await onSave(); dismiss()
    }
}

struct ClubAnnouncementFormView: View {
    let clubId: String
    let clubName: String
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
        try? await FirebaseService.shared.saveClubAnnouncement(clubId: clubId, clubName: clubName, ann: ClubAnnouncement(id: "", title: title, message: message, postedAt: Date(), authorName: authorName))
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
