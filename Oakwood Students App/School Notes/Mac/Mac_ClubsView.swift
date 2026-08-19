//
//  Mac_ClubsView.swift
//  School Notes
//
import SwiftUI
import PhotosUI

struct Mac_ClubsView: View {
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
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading clubs…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if clubs.isEmpty {
                    ContentUnavailableView("No Clubs Yet", systemImage: "person.3")
                } else {
                    List(sortedClubs) { club in
                        NavigationLink {
                            Mac_ClubDetailView(
                                club: club,
                                onUpdate: { updated in if let i = clubs.firstIndex(where: { $0.id == updated.id }) { clubs[i] = updated } },
                                onDelete: { clubs.removeAll { $0.id == club.id } }
                            )
                        } label: {
                            HStack(spacing: 12) {
                                ClubSwatchView(club: club)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(club.name).font(.body.weight(.semibold))
                                    let s = club.meetingScheduleDisplay
                                    if !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if appInfo.followedClubIDs.contains(club.id) {
                                    Image(systemName: "bell.fill").font(.caption).foregroundStyle(.secondary)
                                }
                                if appInfo.clubsWithUnreadAnnouncements.contains(club.id) {
                                    Circle().fill(Color.red).frame(width: 8, height: 8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Clubs")
            .refreshable { await loadClubs() }
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
            .onAppear {
                Task { await loadClubs() }
                Task { await appInfo.refreshUnreadClubBadges() }
                Task { await scheduleFollowedClubEventReminders() }
            }
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
    @State private var cookiesReady = false

    private var userEmail: String { appInfo.googleVM.userEmail }
    private var isSuperAdmin: Bool { userEmail.lowercased() == superAdminEmail }
    private var canEdit: Bool { isSuperAdmin || club.editors.contains(userEmail) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var upcomingEvents: [ClubEvent] { events.filter { $0.date >= today } }
    private var pastEvents: [ClubEvent] { events.filter { $0.date < today }.reversed() }
    private var themeGradient: LinearGradient? { ClubTheme.preset(id: club.themeID)?.gradient }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if club.hasCustomBackground {
                    ClubCloudImage(clubId: club.id, version: club.backgroundVersion)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                // About
                if !club.description.isEmpty {
                    cardSection {
                        Text(club.description)
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                }

                // Info
                if !club.meetingScheduleDisplay.isEmpty || !club.meetingLocation.isEmpty {
                    cardSection {
                        let s = club.meetingScheduleDisplay
                        if !s.isEmpty { Label(s, systemImage: "clock").font(.subheadline).foregroundStyle(.white) }
                        if !s.isEmpty && !club.meetingLocation.isEmpty { cardDivider }
                        if !club.meetingLocation.isEmpty { Label(club.meetingLocation, systemImage: "mappin.circle").font(.subheadline).foregroundStyle(.white) }
                    }
                }

                if !club.officers.isEmpty {
                    sectionHeader("Officers")
                    cardSection {
                        ForEach(Array(club.officers.enumerated()), id: \.element.id) { index, o in
                            if index > 0 { cardDivider }
                            HStack(spacing: 12) {
                                Mac_OfficerPhoto(officer: o, size: 44, isReady: cookiesReady)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.name).font(.body).foregroundStyle(.white)
                                    Text(o.role).font(.caption).foregroundStyle(.white.opacity(0.65))
                                    if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundStyle(.white.opacity(0.65)) }
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

                sectionHeader("Announcements")
                cardSection {
                    if isLoadingAnnouncements { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if announcements.isEmpty { Text("No announcements").foregroundStyle(.white.opacity(0.65)).font(.subheadline) }
                    else {
                        ForEach(Array(announcements.enumerated()), id: \.element.id) { index, ann in
                            if index > 0 { cardDivider }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ann.title).font(.body.weight(.semibold)).foregroundStyle(.white)
                                if !ann.message.isEmpty { Text(ann.message).font(.subheadline).foregroundStyle(.white.opacity(0.65)) }
                                HStack {
                                    Text(ann.authorName).font(.caption2).foregroundStyle(.white.opacity(0.65))
                                    Spacer()
                                    Text(ann.postedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .padding(.vertical, 4)
                            .contextMenu { if canEdit { deleteAnnouncementButton(ann) } }
                        }
                    }
                    if canEdit {
                        if !announcements.isEmpty || isLoadingAnnouncements { cardDivider }
                        Button { showAddAnnouncement = true } label: { Label("Post Announcement", systemImage: "megaphone") }
                    }
                }

                sectionHeader("Upcoming Events")
                cardSection {
                    if isLoadingEvents { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if upcomingEvents.isEmpty { Text("No upcoming events").foregroundStyle(.white.opacity(0.65)).font(.subheadline) }
                    else {
                        ForEach(Array(upcomingEvents.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { cardDivider }
                            Mac_ClubEventRow(event: event)
                                .contextMenu { if canEdit { eventContextMenuItems(event) } }
                        }
                    }
                    if canEdit {
                        if !upcomingEvents.isEmpty || isLoadingEvents { cardDivider }
                        Button { showAddEvent = true } label: { Label("Add Event", systemImage: "plus.circle") }
                    }
                }

                if !pastEvents.isEmpty {
                    sectionHeader("Past Events")
                    cardSection {
                        ForEach(Array(pastEvents.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { cardDivider }
                            Mac_ClubEventRow(event: event)
                                .contextMenu { if canEdit { deleteEventButton(event) } }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { (themeGradient ?? LinearGradient(colors: [Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)).ignoresSafeArea() }
        .navigationTitle(club.name)
        .toolbar {
            ToolbarItem {
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
        .sheet(isPresented: $showEdit) {
            Mac_ClubEditView(club: club) { club = $0; onUpdate($0) }
                .frame(minWidth: 480, minHeight: 480)
        }
        .sheet(isPresented: $showManageEditors) {
            Mac_ClubEditorManagerView(club: $club) { Task { try? await FirebaseService.shared.updateClub(club) } }
                .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(isPresented: $showAddEvent) {
            Mac_ClubEventFormView(clubId: club.id, clubName: club.name, authorName: appInfo.googleVM.userName, event: nil) { await loadEvents() }
                .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(item: $editingEvent) { event in
            Mac_ClubEventFormView(clubId: club.id, clubName: club.name, authorName: appInfo.googleVM.userName, event: event) { await loadEvents() }
                .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(isPresented: $showAddAnnouncement) {
            Mac_ClubAnnouncementFormView(clubId: club.id, clubName: club.name, authorName: appInfo.googleVM.userName) { await loadAnnouncements() }
                .frame(minWidth: 420, minHeight: 300)
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
    @ViewBuilder private func eventContextMenuItems(_ event: ClubEvent) -> some View {
        Button { editingEvent = event } label: { Label("Edit", systemImage: "pencil") }
        deleteEventButton(event)
    }
    @ViewBuilder private func deleteAnnouncementButton(_ ann: ClubAnnouncement) -> some View {
        Button(role: .destructive) { Task { try? await FirebaseService.shared.deleteClubAnnouncement(clubId: club.id, announcementId: ann.id); await loadAnnouncements() } } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Card styling (macOS has no built-in grouped-list card look like iOS's
    // dark-mode insetGrouped rendering, so this replicates it manually: solid near-black
    // rounded cards with white text, matching what iOS gets for free.)

    @ViewBuilder private func cardSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var cardDivider: some View {
        Divider().overlay(Color.white.opacity(0.15))
    }

    private func loadEvents() async {
        isLoadingEvents = true
        events = (try? await FirebaseService.shared.fetchClubEvents(clubId: club.id)) ?? []
        isLoadingEvents = false
        if appInfo.followedClubIDs.contains(club.id) { scheduleEventReminders(clubName: club.name, events: events) }
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
            Text(event.title).font(.body.weight(.semibold)).foregroundStyle(.white)
            Label(event.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption).foregroundStyle(.white.opacity(0.65))
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundStyle(.white.opacity(0.65)) }
            if !event.description.isEmpty { Text(event.description).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(2) }
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
    @State private var editingOfficer: ClubOfficer? = nil
    @State private var editRoleInput = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingImage = false
    @State private var uploadError: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    TextField("Club name", text: $club.name)
                    TextField("Description", text: $club.description, axis: .vertical).lineLimit(3...6)
                }
                Section("Appearance") {
                    Text("Accent Color").font(.caption).foregroundStyle(.secondary)
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
                        HStack { ProgressView(); Text("Uploading…").foregroundStyle(.secondary) }
                    }
                    if let uploadError {
                        Text(uploadError).font(.caption).foregroundStyle(.red)
                    }
                    if club.hasCustomBackground {
                        Button("Remove Custom Background", role: .destructive) { club.hasCustomBackground = false }
                    }
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
                Section {
                    ForEach(Array(club.officers.enumerated()), id: \.element.id) { index, o in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.name).font(.body)
                                Text(o.role).font(.caption).foregroundStyle(.secondary)
                                if !o.email.isEmpty { Text(o.email).font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button { moveOfficer(at: index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.plain).disabled(index == 0)
                            Button { moveOfficer(at: index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.plain).disabled(index == club.officers.count - 1)
                            Button { editingOfficer = o; editRoleInput = o.role } label: { Image(systemName: "pencil") }
                                .buttonStyle(.plain)
                            Button(role: .destructive) { club.officers.removeAll { $0.id == o.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    Button { showOfficerPicker = true } label: { Label("Add Officer from Directory", systemImage: "person.badge.plus") }
                } header: {
                    Text("Officers")
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

    private func moveOfficer(at index: Int, by offset: Int) {
        let newIndex = index + offset
        guard club.officers.indices.contains(newIndex) else { return }
        club.officers.swapAt(index, newIndex)
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
        try? await FirebaseService.shared.saveClubEvent(clubId: clubId, clubName: clubName, authorName: authorName, event: ClubEvent(id: event?.id ?? "", title: title, date: date, location: location, description: desc))
        await onSave(); dismiss()
    }
}

private struct Mac_ClubAnnouncementFormView: View {
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
        try? await FirebaseService.shared.saveClubAnnouncement(clubId: clubId, clubName: clubName, ann: ClubAnnouncement(id: "", title: title, message: message, postedAt: Date(), authorName: authorName))
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
