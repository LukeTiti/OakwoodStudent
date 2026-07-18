//
//  Mac_CalendarView.swift
//  School Notes
//
import SwiftUI

struct Mac_CalendarView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var showingFilter = false
    @State private var showAddCalendar = false
    @State private var selectedCategories: Set<String> = {
        guard let data = UserDefaults.standard.data(forKey: "selectedCategories"),
              let cats = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return cats
    }()

    private let daysBack = 3
    private let minDaysAhead = 14

    /// Always shows at least `minDaysAhead` days out, but extends further to cover
    /// whatever the furthest-out loaded event is — no hard cutoff on how far ahead
    /// the calendar can scroll.
    private var dayOffsets: Range<Int> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let maxEventOffset = nonPersonalItems
            .compactMap { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0.date)).day }
            .max() ?? 0
        let daysAhead = max(minDaysAhead, maxEventOffset + 1)
        return -daysBack..<daysAhead
    }

    private var allCategories: [String] {
        Array(Set(appInfo.calendarItems.compactMap { item -> String? in
            if case .personal = item { return nil }
            return item.category
        })).sorted()
    }

    private var nonPersonalItems: [CalendarItem] {
        var filtered = appInfo.calendarItems.filter { if case .personal = $0 { return false }; return true }
        if !selectedCategories.isEmpty { filtered = filtered.filter { selectedCategories.contains($0.category) } }
        return filtered
    }

    private func items(for dayOffset: Int) -> [CalendarItem] {
        guard let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) else { return [] }
        return nonPersonalItems
            .filter { Calendar.current.isDate($0.date, inSameDayAs: targetDate) }
            .sorted { $0.date < $1.date }
    }

    private func columnTitle(for dayOffset: Int) -> String {
        switch dayOffset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            return Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())
                .map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? ""
        }
    }

    private var filterIconName: String {
        selectedCategories.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    var body: some View {
        Group {
            if appInfo.calendarIsLoading {
                ProgressView("Loading events…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(dayOffsets, id: \.self) { offset in
                            Mac_CalendarDayColumn(
                                title: columnTitle(for: offset),
                                isToday: offset == 0,
                                items: items(for: offset)
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Calendar")
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
        .popover(isPresented: $showingFilter) {
            Mac_CalendarFilterView(allCategories: allCategories, selectedCategories: $selectedCategories)
                .frame(width: 300, height: 360)
        }
        .sheet(isPresented: $showAddCalendar) {
            Mac_PracticeCalendarSheet(savedURLs: appInfo.practiceCalendarURLs) { updated in
                appInfo.practiceCalendarURLs = updated
                Task { await appInfo.loadAllCalendarEvents() }
            }
            .frame(minWidth: 420, minHeight: 360)
        }
        .onChange(of: selectedCategories) { _, _ in
            if let data = try? JSONEncoder().encode(selectedCategories) {
                UserDefaults.standard.set(data, forKey: "selectedCategories")
            }
        }
        .onAppear {
            if appInfo.calendarItems.isEmpty { Task { await appInfo.loadAllCalendarEvents() } }
            else { Task { await appInfo.refreshCalendarData() } }
        }
    }
}

// MARK: - Day Column

private struct Mac_CalendarDayColumn: View {
    let title: String
    let isToday: Bool
    let items: [CalendarItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            if items.isEmpty {
                Text("No events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Mac_CalendarEventCard(item: item)
                }
            }
        }
        .frame(width: 240, alignment: .top)
    }
}

// MARK: - Event Card

private struct Mac_CalendarEventCard: View {
    let item: CalendarItem
    @EnvironmentObject var appInfo: AppInfo
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch item {
            case .sports(let event):
                sportsCard(event)
            case .school(let event):
                simpleCard(title: event.title, badge: "School Event", badgeColor: .teal, event: event)
            case .practice(let event):
                simpleCard(title: event.title, badge: "Practice", badgeColor: .indigo, event: event)
            case .personal:
                EmptyView()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail) {
            Mac_CalendarEventDetailView(item: item)
                .frame(width: 360)
        }
    }

    @ViewBuilder
    private func sportsCard(_ event: SportsEvent) -> some View {
        let score = appInfo.calendarScores[event.id]
        HStack {
            Badge(text: event.sportName, color: .blue)
            Spacer()
            Badge(text: event.isAway ? "Away" : "Home", color: event.isAway ? .orange : .green)
        }
        Text(event.opponent)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
        if let score {
            let oakwoodScore = event.isAway ? score.awayScore : score.homeScore
            let opponentScore = event.isAway ? score.homeScore : score.awayScore
            Text("\(oakwoodScore) - \(opponentScore)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(oakwoodScore > opponentScore ? Color.green : (oakwoodScore == opponentScore ? Color.secondary : Color.red))
        }
        Text(event.timeText)
            .font(.caption)
            .foregroundStyle(.secondary)
        if event.isCancelled {
            Badge(text: "Cancelled", color: .red)
        }
    }

    @ViewBuilder
    private func simpleCard(title: String, badge: String, badgeColor: Color, event: SchoolEvent) -> some View {
        Badge(text: badge, color: badgeColor)
        Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
        Text(event.timeText)
            .font(.caption)
            .foregroundStyle(.secondary)
        if !event.location.isEmpty {
            Text(event.location)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Event Detail (popover)

private struct Mac_CalendarEventDetailView: View {
    let item: CalendarItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch item {
                case .sports(let event):
                    Mac_GameDetailContent(event: event)
                case .school(let event):
                    Mac_SchoolEventDetailContent(event: event, badgeLabel: "School Event", badgeColor: .teal)
                case .practice(let event):
                    Mac_SchoolEventDetailContent(event: event, badgeLabel: "Practice", badgeColor: .indigo)
                case .personal(let event):
                    Mac_SchoolEventDetailContent(event: event, badgeLabel: "My Schedule", badgeColor: .indigo)
                }
            }
            .padding()
        }
    }
}

private struct Mac_SchoolEventDetailContent: View {
    let event: SchoolEvent
    var badgeLabel: String = "School Event"
    var badgeColor: Color = .teal

    var body: some View {
        Badge(text: badgeLabel, color: badgeColor)
        Text(event.title)
            .font(.title3.weight(.bold))
        Label(event.date.formatted(date: .complete, time: .omitted), systemImage: "calendar")
            .foregroundStyle(.secondary)
        Label(event.timeText, systemImage: "clock")
            .foregroundStyle(.secondary)
        if !event.location.isEmpty {
            Label(event.location, systemImage: "mappin.circle")
                .foregroundStyle(.secondary)
        }
        if !event.description.isEmpty {
            Divider()
            Text(event.description)
        }
    }
}

// MARK: - Game Detail Content

private struct Mac_GameDetailContent: View {
    let event: SportsEvent
    @EnvironmentObject var appInfo: AppInfo

    @State private var gameScore: GameScore?
    @State private var signups: [ScoreboardSignup] = []
    @State private var isLoading = true
    @State private var showScoreSheet = false
    @State private var homeScoreInput = ""
    @State private var awayScoreInput = ""
    @State private var errorMessage: String?

    private var isSignedIn: Bool { !appInfo.googleVM.userEmail.isEmpty }
    private var userEmail: String { appInfo.googleVM.userEmail }
    private var userName: String { appInfo.googleVM.userName }
    private var jobs: [JobDefinition] { jobsForSport(event.sportName) }
    private var isPastGame: Bool { event.date < Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        Group {
            HStack {
                Badge(text: event.sportName, color: .blue)
                if !event.teamName.isEmpty {
                    Badge(text: event.teamName, color: .purple)
                }
                Spacer()
                Badge(text: event.isAway ? "Away" : "Home", color: event.isAway ? .orange : .green)
            }
            Text(event.opponent).font(.title3.weight(.bold))
            Label(event.date.formatted(date: .complete, time: .omitted), systemImage: "calendar").foregroundStyle(.secondary)
            Label(event.timeText, systemImage: "clock").foregroundStyle(.secondary)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.circle").foregroundStyle(.secondary)
            }

            Divider()

            Text("Score").font(.headline)
            if isLoading {
                ProgressView()
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
                Text("No score reported yet").foregroundStyle(.secondary)
                if isSignedIn {
                    Button("Report Score") { showScoreSheet = true }
                } else {
                    Text("Sign in to report scores").font(.caption).foregroundStyle(.secondary)
                }
            }

            Group {
                if !event.isAway && !jobs.isEmpty {
                    Divider()
                    Text("Scoreboard Jobs").font(.headline)
                    ForEach(jobs, id: \.name) { job in
                        ForEach(0..<job.slots, id: \.self) { slot in
                            jobSlotRow(job: job, slot: slot)
                        }
                    }
                    if isPastGame {
                        Text("Signups closed for past games").font(.caption).foregroundStyle(.secondary)
                    } else if !isSignedIn {
                        Text("Sign in to sign up for jobs").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onAppear { Task { await loadData() } }
        .sheet(isPresented: $showScoreSheet) { scoreSheet }
    }

    private var scoreSheet: some View {
        NavigationStack {
            Form {
                Section("Oakwood") {
                    TextField("Score", text: event.isAway ? $awayScoreInput : $homeScoreInput)
                }
                Section(event.opponent) {
                    TextField("Score", text: event.isAway ? $homeScoreInput : $awayScoreInput)
                }
            }
            .navigationTitle("Report Score")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScoreSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submitScore() } }
                        .disabled(homeScoreInput.isEmpty || awayScoreInput.isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 260)
    }

    @ViewBuilder
    private func scoreDisplay(_ score: GameScore) -> some View {
        let (leftTeam, leftScore, rightTeam, rightScore) = event.isAway
            ? (event.opponent, score.awayScore, "Oakwood", score.homeScore)
            : ("Oakwood", score.homeScore, event.opponent, score.awayScore)

        HStack {
            VStack {
                Text(leftTeam).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(leftScore)").font(.title).fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            Text("-").font(.title2).foregroundStyle(.secondary)
            VStack {
                Text(rightTeam).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(rightScore)").font(.title).fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
        }
        Text("Reported by \(score.submittedByName)").font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func jobSlotRow(job: JobDefinition, slot: Int) -> some View {
        let displayName = job.slots > 1 ? "\(job.name) \(slot + 1)" : job.name
        let signup = signups.first { $0.job == job.name && $0.slot == slot }

        HStack {
            Text(displayName)
            Spacer()
            if let signup {
                if signup.userEmail == userEmail {
                    Text("You").foregroundStyle(.green)
                    if !isPastGame {
                        Button("Cancel") { cancelSignup(signup) }.foregroundStyle(.red).buttonStyle(.borderless)
                    }
                } else {
                    Text(signup.userName).foregroundStyle(.secondary)
                }
            } else if isPastGame {
                Text("Unfilled").foregroundStyle(.secondary)
            } else if isSignedIn {
                Button("Sign Up") { signUp(job: job.name, slot: slot) }.buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Text("Available").foregroundStyle(.secondary)
            }
        }
    }

    private func loadData() async {
        async let scoreTask: () = loadScore()
        async let signupsTask: () = loadSignups()
        await scoreTask; await signupsTask
        await MainActor.run { isLoading = false }
    }

    private func loadScore() async {
        gameScore = try? await FirebaseService.shared.fetchGameScore(eventId: event.id)
    }

    private func loadSignups() async {
        signups = (try? await FirebaseService.shared.fetchSignups(eventId: event.id)) ?? []
    }

    private func submitScore() async {
        guard let home = Int(homeScoreInput), let away = Int(awayScoreInput) else { return }
        try? await FirebaseService.shared.submitGameScore(eventId: event.id, homeScore: home, awayScore: away, userEmail: userEmail, userName: userName)
        await loadScore()
        await MainActor.run { showScoreSheet = false }
    }

    private func signUp(job: String, slot: Int) {
        let desc = "\(event.sportName) - \(event.teamName) vs \(event.opponent)"
        Task {
            do {
                try await FirebaseService.shared.signUpForJob(eventId: event.id, job: job, slot: slot, userEmail: userEmail, userName: userName, eventDate: event.date, eventDescription: desc)
                await loadSignups()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func cancelSignup(_ signup: ScoreboardSignup) {
        Task {
            try? await FirebaseService.shared.cancelSignup(signupId: signup.id)
            await loadSignups()
        }
    }
}

// MARK: - Calendar Filter View

private struct Mac_CalendarFilterView: View {
    let allCategories: [String]
    @Binding var selectedCategories: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Show All") { selectedCategories.removeAll() }
                }
                Section("Filter Events") {
                    ForEach(allCategories, id: \.self) { category in
                        Button {
                            if selectedCategories.contains(category) { selectedCategories.remove(category) }
                            else { selectedCategories.insert(category) }
                        } label: {
                            HStack {
                                Text(category).foregroundStyle(.primary)
                                Spacer()
                                if selectedCategories.contains(category) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Filter Events")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Practice Calendar Sheet

private struct Mac_PracticeCalendarSheet: View {
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
                            Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .onDelete { urls.remove(atOffsets: $0) }
                    }
                }
                Section {
                    TextField("webcal:// or https://", text: $newURL)
                        .autocorrectionDisabled()
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onSave(urls); dismiss() } }
            }
            .onAppear { urls = savedURLs }
        }
    }
}
