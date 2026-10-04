//
//  Sports View.swift
//  School Notes
//
//  Created by Luke Titi on 10/5/25.
//
import SwiftUI


// MARK: - Sports Event Row
struct SportsEventRow: View {
    let event: SportsEvent
    let score: GameScore?
    var myJob: String? = nil

    var oakwoodScore: Int { score.map { event.isAway ? $0.awayScore : $0.homeScore } ?? 0 }
    var opponentScore: Int { score.map { event.isAway ? $0.homeScore : $0.awayScore } ?? 0 }
    var scoreColor: Color { oakwoodScore > opponentScore ? .green : (oakwoodScore == opponentScore ? .secondary : .red) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: event.sportName, color: .blue)
                if !event.teamName.isEmpty {
                    Badge(text: event.teamName, color: .purple)
                }
                Spacer()
                Badge(text: event.isAway ? "Away" : "Home", color: event.isAway ? .orange : .green)
            }
            HStack {
                Text(event.opponent).fontWeight(.semibold)
                Spacer()
                if score != nil {
                    Text("\(oakwoodScore) - \(opponentScore)")
                        .font(.headline).fontWeight(.bold).foregroundColor(scoreColor)
                }
            }
            Label(event.timeText, systemImage: "clock").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty {
                HStack(spacing: 4) {
                    Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary)
                    if let job = myJob {
                        Text("· Working: \(job)")
                            .font(.caption2)
                            .foregroundColor(.indigo)
                    }
                }
            } else if let job = myJob {
                Text("Working: \(job)")
                    .font(.caption2)
                    .foregroundColor(.indigo)
            }
            if event.isCancelled {
                Badge(text: "Cancelled", color: .red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - School Event Row
struct SchoolEventRow: View {
    let event: SchoolEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: "School Event", color: .teal)
                Spacer()
            }
            Text(event.title).fontWeight(.semibold)
            Label(event.timeText, systemImage: "clock").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Personal Event Row
struct PersonalEventRow: View {
    let event: SchoolEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: "My Schedule", color: .indigo)
                Spacer()
            }
            Text(event.title).fontWeight(.semibold)
            Label(event.timeText, systemImage: "clock").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - School Event Detail View
struct SchoolEventDetailView: View {
    let event: SchoolEvent
    var badgeLabel: String = "School Event"
    var badgeColor: Color = .teal

    var body: some View {
        List {
            Section {
                Badge(text: badgeLabel, color: badgeColor)
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.title2).fontWeight(.bold)
                    Label(event.date.formatted(date: .complete, time: .omitted), systemImage: "calendar").foregroundColor(.secondary)
                    Label(event.timeText, systemImage: "clock").foregroundColor(.secondary)
                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.circle").foregroundColor(.secondary)
                    }
                }
            }
            if !event.description.isEmpty {
                Section("Details") {
                    Text(event.description)
                }
            }
        }
        .navigationTitle("Event Details")
        .inlineNavigationBarTitle()
    }
}

// MARK: - Game Detail View
struct GameDetailView: View {
    let event: SportsEvent
    @EnvironmentObject var appInfo: AppInfo

    @State private var gameScore: GameScore?
    @State private var allSignups: [GameJobSignups] = []
    @State private var isLoading = true
    @State private var showScoreSheet = false
    @State private var homeScoreInput = ""
    @State private var awayScoreInput = ""
    @State private var errorMessage: String?

    var isSignedIn: Bool { !appInfo.googleVM.userEmail.isEmpty }
    var userEmail: String { appInfo.googleVM.userEmail }
    var userName: String { appInfo.googleVM.userName }
    var matchedSignup: GameJobSignups? { matchingSignups(for: event, in: allSignups) }
    var isPastGame: Bool { event.date < Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        List {
            Section {
                HStack {
                    Badge(text: event.sportName, color: .blue)
                    if !event.teamName.isEmpty {
                        Badge(text: event.teamName, color: .purple)
                    }
                    Spacer()
                    Badge(text: event.isAway ? "Away" : "Home", color: event.isAway ? .orange : .green)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.opponent).font(.title2).fontWeight(.bold)
                    Label(event.date.formatted(date: .complete, time: .omitted), systemImage: "calendar").foregroundColor(.secondary)
                    Label(event.timeText, systemImage: "clock").foregroundColor(.secondary)
                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.circle").foregroundColor(.secondary)
                    }
                }
            }

            Section("Score") {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let score = gameScore {
                    scoreDisplay(score)
                    if isSignedIn {
                        Button("Update Score") {
                            homeScoreInput = "\(score.homeScore)"
                            awayScoreInput = "\(score.awayScore)"
                            showScoreSheet = true
                        }
                    }
                } else {
                    Text("No score reported yet").foregroundColor(.secondary)
                    if isSignedIn {
                        Button("Report Score") { showScoreSheet = true }
                    } else {
                        Text("Sign in to report scores").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if !event.isAway, let matchedSignup, !matchedSignup.jobs.isEmpty {
                Section("Scoreboard Jobs") {
                    ForEach(matchedSignup.jobs) { job in
                        jobSlotRow(job: job)
                    }
                    if isPastGame {
                        Text("Signups closed for past games").font(.caption).foregroundColor(.secondary)
                    } else if !isSignedIn {
                        Text("Sign in to sign up for jobs").font(.caption).foregroundColor(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Game Details")
        .inlineNavigationBarTitle()
        .onAppear { Task { await loadData() } }
        .sheet(isPresented: $showScoreSheet) { scoreSheet }
    }

    @ViewBuilder
    func scoreDisplay(_ score: GameScore) -> some View {
        let (leftTeam, leftScore, rightTeam, rightScore) = event.isAway
            ? (event.opponent, score.awayScore, "Oakwood", score.homeScore)
            : ("Oakwood", score.homeScore, event.opponent, score.awayScore)

        VStack(spacing: 12) {
            HStack {
                VStack {
                    Text(leftTeam).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Text("\(leftScore)").font(.largeTitle).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                Text("-").font(.title).foregroundColor(.secondary)
                VStack {
                    Text(rightTeam).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Text("\(rightScore)").font(.largeTitle).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
            }
            Text("Reported by \(score.submittedByName)").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    func jobSlotRow(job: GameJobSlot) -> some View {
        HStack {
            Text(job.name)
            Spacer()
            if !job.isOpen {
                // Matched by name, not email — the sheet only ever stores a first name (same
                // convention the AD already uses manually), so this can't distinguish two
                // students sharing one, same as the sheet itself can't.
                if job.filledBy == userName {
                    Text("You").foregroundColor(.green)
                    if !isPastGame {
                        Button("Cancel") { cancelSignup(job: job.name) }.foregroundColor(.red).buttonStyle(.borderless)
                    }
                } else {
                    Text(job.filledBy).foregroundColor(.secondary)
                }
            } else if isPastGame {
                Text("Unfilled").foregroundColor(.secondary)
            } else if isSignedIn {
                Button("Sign Up") { signUp(job: job.name) }.buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Text("Available").foregroundColor(.secondary)
            }
        }
    }

    var scoreSheet: some View {
        NavigationStack {
            Form {
                Section("Oakwood") {
                    TextField("Score", text: event.isAway ? $awayScoreInput : $homeScoreInput)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Section(event.opponent) {
                    TextField("Score", text: event.isAway ? $homeScoreInput : $awayScoreInput)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            .navigationTitle("Report Score")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScoreSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submitScore() } }
                        .disabled(homeScoreInput.isEmpty || awayScoreInput.isEmpty)
                }
            }
        }
    }

    func loadData() async {
        async let scoreTask: () = loadScore()
        async let signupsTask: () = loadSignups()
        await scoreTask; await signupsTask
        await MainActor.run { isLoading = false }
    }

    func loadScore() async {
        gameScore = try? await FirebaseService.shared.fetchGameScore(eventId: event.id)
    }

    func loadSignups() async {
        allSignups = (try? await SportsSignupService.fetchSignups()) ?? []
    }

    func submitScore() async {
        guard let home = Int(homeScoreInput), let away = Int(awayScoreInput) else { return }
        try? await FirebaseService.shared.submitGameScore(eventId: event.id, homeScore: home, awayScore: away, userEmail: userEmail, userName: userName)
        await loadScore()
        await MainActor.run { showScoreSheet = false }
    }

    func signUp(job: String) {
        guard let matchedSignup else { return }
        Task {
            do {
                try await SportsSignupService.setJob(game: matchedSignup, job: job, name: userName, action: "signup")
                await MainActor.run { errorMessage = nil }
                await loadSignups()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelSignup(job: String) {
        guard let matchedSignup else { return }
        Task {
            do {
                try await SportsSignupService.setJob(game: matchedSignup, job: job, name: userName, action: "cancel")
                await MainActor.run { errorMessage = nil }
                await loadSignups()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Day Detail View

struct DaySelection: Identifiable, Hashable {
    let dateTitle: String
    let items: [CalendarItem]
    var id: String { dateTitle }
}

struct DayDetailView: View {
    let dateTitle: String
    let items: [CalendarItem]
    @EnvironmentObject var appInfo: AppInfo

    var body: some View {
        List {
            ForEach(items) { item in
                switch item {
                case .sports(let event):
                    NavigationLink(destination: GameDetailView(event: event)) {
                        SportsEventRow(
                            event: event,
                            score: appInfo.calendarScores[event.id],
                            myJob: myJobName(for: event, in: appInfo.sportsSignups, userName: appInfo.googleVM.userName)
                        )
                    }
                case .personal(let event):
                    NavigationLink(destination: SchoolEventDetailView(event: event, badgeLabel: "My Schedule", badgeColor: .indigo)) {
                        PersonalEventRow(event: event)
                    }
                case .school(let event):
                    NavigationLink(destination: SchoolEventDetailView(event: event)) {
                        SchoolEventRow(event: event)
                    }
                case .practice(let event):
                    NavigationLink(destination: SchoolEventDetailView(event: event)) {
                        PersonalEventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle(dateTitle)
        .inlineNavigationBarTitle()
    }
}

// MARK: - Calendar Filter View
struct CalendarFilterView: View {
    let allCategories: [String]
    @Binding var selectedCategories: Set<String>
    @Environment(\.dismiss) var dismiss

    private var schoolCalendarCategoryNames: Set<String> {
        Set(schoolEventCalendars.map(\.category))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Show All") { selectedCategories.removeAll() }.foregroundColor(.blue)
                }
                Section("School Calendars") {
                    ForEach(allCategories.filter { schoolCalendarCategoryNames.contains($0) }, id: \.self) { category in
                        filterRow(for: category)
                    }
                }
                Section("Sports Teams") {
                    ForEach(allCategories.filter { !schoolCalendarCategoryNames.contains($0) }, id: \.self) { category in
                        filterRow(for: category)
                    }
                }
            }
            .navigationTitle("Filter Events")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func isSelected(_ category: String) -> Bool {
        selectedCategories.isEmpty || selectedCategories.contains(category)
    }

    @ViewBuilder
    private func filterRow(for category: String) -> some View {
        Button {
            if selectedCategories.isEmpty {
                // Currently showing everything (implicit) — tapping one unchecks just that one,
                // making every other category explicitly selected.
                selectedCategories = Set(allCategories).subtracting([category])
            } else if selectedCategories.contains(category) {
                selectedCategories.remove(category)
            } else {
                selectedCategories.insert(category)
            }
        } label: {
            HStack {
                Text(category).foregroundColor(.primary)
                Spacer()
                if isSelected(category) {
                    Image(systemName: "checkmark").foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var selectedTab = 0
    @State private var showingFilter = false
    @State private var selectedDay: DaySelection? = nil
    @State private var showAddCalendar = false
    @State private var selectedCategories: Set<String> = {
        guard let data = UserDefaults.standard.data(forKey: "selectedCategories"),
              let cats = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return cats
    }()

    var allCategories: [String] {
        Array(Set(appInfo.calendarItems.compactMap { item -> String? in
            if case .personal = item { return nil }
            return item.category
        })).sorted()
    }

    var filteredItems: [CalendarItem] {
        let today = Calendar.current.startOfDay(for: Date())
        var filtered = appInfo.calendarItems.filter { if case .personal = $0 { return false }; return true; }
        if !selectedCategories.isEmpty { filtered = filtered.filter { selectedCategories.contains($0.category) } }
        filtered = selectedTab == 0 ? filtered.filter { $0.date >= today } : filtered.filter { $0.date < today }
        return filtered
    }

    var personalItemsByDate: [String: [CalendarItem]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "MMMM d"
        let cal = Calendar.current
        let personal = appInfo.calendarItems.filter { if case .personal = $0 { return true }; return false }
        return Dictionary(grouping: personal) { item in
            cal.isDateInToday(item.date) ? "Today, \(todayFormatter.string(from: item.date))" : formatter.string(from: item.date)
        }
    }

    var groupedItems: [(String, [CalendarItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "MMMM d"
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func dateKey(_ date: Date) -> String {
            cal.isDateInToday(date) ? "Today, \(todayFormatter.string(from: date))" : formatter.string(from: date)
        }

        var dateMap: [String: (date: Date, items: [CalendarItem])] = [:]
        for item in filteredItems {
            let key = dateKey(item.date)
            if dateMap[key] == nil { dateMap[key] = (item.date, []) }
            dateMap[key]!.items.append(item)
        }

        // Add placeholder entries for dates that only have personal/class events so "View My Day" still appears
        let allPersonal = appInfo.calendarItems.filter { if case .personal = $0 { return true }; return false; }
        let tabPersonal = selectedTab == 0 ? allPersonal.filter { $0.date >= today } : allPersonal.filter { $0.date < today }
        for item in tabPersonal {
            let key = dateKey(item.date)
            if dateMap[key] == nil { dateMap[key] = (item.date, []) }
            // intentionally not appending — personal items only show in My Day
        }

        let sorted = dateMap.sorted { $0.value.date < $1.value.date }.map { ($0.key, $0.value.items) }
        return selectedTab == 1 ? sorted.reversed() : sorted
    }

    @ViewBuilder
    func calendarItemRow(_ item: CalendarItem) -> some View {
        switch item {
        case .sports(let event):
            NavigationLink(destination: GameDetailView(event: event)) {
                SportsEventRow(event: event, score: appInfo.calendarScores[event.id], myJob: myJobName(for: event, in: appInfo.sportsSignups, userName: appInfo.googleVM.userName))
            }
        case .school(let event):
            NavigationLink(destination: SchoolEventDetailView(event: event)) {
                SchoolEventRow(event: event)
            }
        case .personal(let event):
            NavigationLink(destination: SchoolEventDetailView(event: event)) {
                PersonalEventRow(event: event)
            }
        case .practice(let event):
            NavigationLink(destination: SchoolEventDetailView(event: event)) {
                PersonalEventRow(event: event)
            }
        }
    }

    @ViewBuilder
    func dayHeader(date: String, items: [CalendarItem]) -> some View {
        HStack {
            Text(date)
            Spacer()
            Button {
                selectedDay = DaySelection(dateTitle: date, items: (personalItemsByDate[date] ?? []) + items)
            } label: {
                HStack(spacing: 3) {
                    Text("View My Day")
                    Image(systemName: "chevron.right")
                }
                .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
        }
    }

    @ViewBuilder
    var calendarContent: some View {
        if appInfo.calendarIsLoading {
            Spacer()
            ProgressView("Loading events...")
            Spacer()
        } else if groupedItems.isEmpty {
            Spacer()
            Text(selectedTab == 0 ? "No upcoming events" : "No past events")
                .foregroundColor(.secondary)
            Spacer()
        } else {
            List {
                ForEach(groupedItems, id: \.0) { date, items in
                    Section {
                        if items.isEmpty {
                            Text("No school events")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(items) { item in
                                calendarItemRow(item)
                            }
                        }
                    } header: {
                        dayHeader(date: date, items: items)
                    }
                }
            }
            .refreshable { await appInfo.loadAllCalendarEvents() }
            .navigationDestination(item: $selectedDay) { selection in
                DayDetailView(dateTitle: selection.dateTitle, items: selection.items)
            }
        }
    }

    var filterIconName: String {
        selectedCategories.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("Upcoming").tag(0)
                    Text("Past").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                calendarContent
            }
            .navigationTitle("Calendar")
            .macInsetListStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingFilter = true } label: { Image(systemName: filterIconName) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAddCalendar = true } label: {
                        Image(systemName: appInfo.practiceCalendarURLs.isEmpty ? "plus" : "calendar.badge.checkmark")
                    }
                }
            }
            .sheet(isPresented: $showingFilter) {
                CalendarFilterView(allCategories: allCategories, selectedCategories: $selectedCategories)
            }
            .sheet(isPresented: $showAddCalendar) {
                PracticeCalendarSheet(savedURLs: appInfo.practiceCalendarURLs) { updated in
                    appInfo.practiceCalendarURLs = updated
                    Task { await appInfo.loadAllCalendarEvents() }
                }
            }
            .onChange(of: selectedCategories) { _, _ in
                if let data = try? JSONEncoder().encode(selectedCategories) {
                    UserDefaults.standard.set(data, forKey: "selectedCategories")
                }
            }
        }
        .onAppear {
            if appInfo.calendarItems.isEmpty { Task { await appInfo.loadAllCalendarEvents() } }
            else { Task { await appInfo.refreshCalendarData() } }
        }
    }
}

// MARK: - Practice Calendar Sheet

struct PracticeCalendarSheet: View {
    let savedURLs: [String]
    var onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urls: [String] = []
    @State private var newURL = ""

    var body: some View {
        NavigationStack {
            Form {
                if !urls.isEmpty {
                    Section("Saved Calendars") {
                        ForEach(urls, id: \.self) { url in
                            Text(url).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        .onDelete { urls.remove(atOffsets: $0) }
                    }
                }
                Section {
                    TextField("webcal:// or https://", text: $newURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("Add Calendar") {
                        let raw = newURL.trimmingCharacters(in: .whitespaces)
                        let normalized = raw.hasPrefix("webcal://") ? "https://" + raw.dropFirst("webcal://".count) : raw
                        guard !normalized.isEmpty, !urls.contains(normalized) else { return }
                        urls.append(normalized)
                        newURL = ""
                    }
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Add Calendar URL")
                } footer: {
                    Text("Paste the iCal subscription URL for a practice schedule. Find it in the Veracross portal under your team calendar.")
                }
            }
            .navigationTitle("Practice Calendars")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onSave(urls); dismiss() } }
            }
            .onAppear { urls = savedURLs }
        }
    }
}
