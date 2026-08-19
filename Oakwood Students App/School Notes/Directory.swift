//
//  Directory.swift
//  School Notes
//

import SwiftUI

// MARK: - Directory List View

struct DirectoryView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var searchText = ""
    @State private var selectedGrade: String? = nil
    @State private var results: [DirectoryPerson] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    private let gradeOptions: [(label: String, value: String)] = [
        ("All", ""),
        ("PS", "Preschool"), ("JK", "Junior Kindergarten"), ("K", "Kindergarten"),
        ("1", "Grade 1"), ("2", "Grade 2"), ("3", "Grade 3"), ("4", "Grade 4"),
        ("5", "Grade 5"), ("6", "Grade 6"), ("7", "Grade 7"), ("8", "Grade 8"),
        ("9", "Grade 9"), ("10", "Grade 10"), ("11", "Grade 11"), ("12", "Grade 12")
    ]

    private var hasQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || selectedGrade != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Directory")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search by name", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onChange(of: searchText) { _, _ in triggerSearch() }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(gradeOptions, id: \.value) { option in
                        Button {
                            selectedGrade = selectedGrade == option.value ? nil : option.value
                        } label: {
                            Text(option.label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedGrade == option.value ? Color.accentColor : Color(.systemGray5))
                                .foregroundColor(selectedGrade == option.value ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            if isLoading {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if !results.isEmpty {
                List(results) { person in
                    NavigationLink(destination: DirectoryPersonView(person: person)) {
                        DirectoryPersonRow(person: person)
                    }
                }
                .macInsetListStyle()
            } else if hasQuery {
                Spacer()
                Text("No results found").foregroundColor(.secondary)
                Spacer()
            } else {
                Spacer()
                Text("Search by name or select a grade").foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("")
        .onChange(of: selectedGrade) { _, _ in triggerSearch() }
        .onAppear {
            Task {
                await appInfo.restorePersistedCookiesIntoStores()
                await syncCookies()
            }
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        guard hasQuery else { isLoading = false; results = []; return }
        searchTask = Task {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            await MainActor.run { isLoading = true }

            let parts = searchText.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            let first = parts.first ?? ""
            let last = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
            var queryItems: [URLQueryItem] = []
            if !first.isEmpty { queryItems.append(URLQueryItem(name: "directory_entry[first_name]", value: first)) }
            if !last.isEmpty { queryItems.append(URLQueryItem(name: "directory_entry[last_name]", value: last)) }
            if let grade = selectedGrade, !grade.isEmpty { queryItems.append(URLQueryItem(name: "directory_entry[grade_level]", value: grade)) }

            let (page1, csrf) = await fetchDirectoryPage1(queryItems: queryItems)
            guard !Task.isCancelled else { await MainActor.run { isLoading = false }; return }
            await MainActor.run { results = page1; isLoading = false }

            guard let csrf, page1.count >= 20 else { return }
            var page = 2
            while page <= 50 {
                guard !Task.isCancelled else { return }
                let batch = await fetchDirectoryPageN(page: page, queryItems: queryItems, csrfToken: csrf)
                guard !Task.isCancelled, !batch.isEmpty else { return }
                await MainActor.run { withAnimation { results += batch } }
                if batch.count < 20 { break }
                page += 1
            }
        }
    }
}

// MARK: - Person Row

struct DirectoryPersonRow: View {
    let person: DirectoryPerson

    var body: some View {
        HStack(spacing: 12) {
            DirectoryPhoto(urlString: person.photoURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.body)
                HStack(spacing: 6) {
                    if !person.grade.isEmpty {
                        Text(person.grade).font(.caption).foregroundColor(.secondary)
                    }
                    if let email = person.studentEmail {
                        Text(email).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .macRowPadding()
    }
}

// MARK: - Person Detail View

struct DirectoryPersonView: View {
    let person: DirectoryPerson

    @EnvironmentObject var appInfo: AppInfo

    @State private var clubRoles: [(clubName: String, role: String)] = []
    @State private var sharedClasses: [String]? = nil

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    DirectoryPhoto(urlString: person.photoURL, size: 72, enlargeOnTap: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.displayName).font(.title3.bold())
                        if !person.grade.isEmpty {
                            Text(person.grade).foregroundColor(.secondary)
                        }
                        if let email = person.studentEmail {
                            Button { openURL("mailto:\(email)") } label: {
                                Text(email).font(.caption).foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !clubRoles.isEmpty {
                Section("Clubs") {
                    ForEach(clubRoles, id: \.clubName) { entry in
                        Label("\(entry.role), \(entry.clubName)", systemImage: "person.3")
                    }
                }
            }

            Section("Classes Together") {
                if let sharedClasses {
                    if sharedClasses.isEmpty {
                        Text("No classes together").foregroundColor(.secondary)
                    } else {
                        ForEach(sharedClasses, id: \.self) { className in
                            Label(className, systemImage: "book.closed")
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            ForEach(person.households) { household in
                Section {
                    if let address = household.address {
                        Button {
                            let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            #if os(iOS)
                            openURL("maps://?q=\(encoded)")
                            #elseif os(macOS)
                            openURL("https://maps.apple.com/?q=\(encoded)")
                            #endif
                        } label: {
                            Label(address, systemImage: "map")
                                .font(.footnote)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(household.contacts) { contact in
                        DirectoryContactRow(contact: contact)
                    }
                }
            }
        }
        .navigationTitle("")
        .inlineNavigationBarTitle()
        .macInsetListStyle()
        .task(id: person.studentEmail) {
            clubRoles = await fetchClubRoles(forEmail: person.studentEmail ?? "")
        }
        .task(id: person.studentEmail) {
            sharedClasses = await fetchSharedClasses(withEmail: person.studentEmail ?? "", courses: appInfo.courses)
        }
    }
}

// MARK: - Contact Row

struct DirectoryContactRow: View {
    let contact: DirectoryContact

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contact.name).font(.body.weight(.semibold))
            if let phone = contact.phone {
                Button { openURL("tel:\(phone.filter { $0.isNumber || $0 == "+" })") } label: {
                    Label(phone, systemImage: "phone").font(.footnote).foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            if let email = contact.email {
                Button { openURL("mailto:\(email)") } label: {
                    Label(email, systemImage: "envelope").font(.footnote).foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Photo Helper

struct DirectoryPhoto: View {
    let urlString: String?
    let size: CGFloat
    var isReady: Bool = true
    var enlargeOnTap: Bool = false

    @State private var imageData: Data?
    @State private var loadFailed = false
    @State private var showEnlarged = false

    var body: some View {
        Group {
            if let imageData, let image = decodedImage(from: imageData) {
                image.resizable().scaledToFill()
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture {
            guard enlargeOnTap, imageData != nil else { return }
            showEnlarged = true
        }
        .task(id: "\(isReady)-\(urlString ?? "")") { await load() }
        .sheet(isPresented: $showEnlarged) {
            if let imageData, let image = decodedImage(from: imageData) {
                image
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func load() async {
        guard isReady, let urlStr = urlString, let url = URL(string: urlStr) else { return }
        if let cached = ImageDataCache.shared.data(for: urlStr) { imageData = cached; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[DirectoryPhoto] load failed for \(urlStr): HTTP \(http.statusCode)")
                loadFailed = true
                return
            }
            ImageDataCache.shared.store(data, for: urlStr)
            imageData = data
        } catch {
            print("[DirectoryPhoto] load failed for \(urlStr): \(error)")
            loadFailed = true
        }
    }

    private var placeholderView: some View {
        Color(.systemGray5).overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
    }
}

// MARK: - Officer Photo (live lookup)

/// Displays a club officer's photo by re-running a live directory search for a freshly-signed
/// URL, rather than using `ClubOfficer.photoURL`, which is a one-time signed URL that expires.
struct OfficerPhoto: View {
    let officer: ClubOfficer
    let size: CGFloat
    var isReady: Bool = true

    @State private var freshURL: String?

    var body: some View {
        DirectoryPhoto(urlString: freshURL, size: size, isReady: isReady && freshURL != nil)
            .task(id: "\(isReady)-\(officer.email)") {
                guard isReady, !officer.email.isEmpty else { return }
                freshURL = await lookupFreshPhotoURL(name: officer.name, email: officer.email)
            }
    }
}

// MARK: - URL Helper

private func openURL(_ string: String) {
    guard let url = URL(string: string) else { return }
    #if os(iOS)
    UIApplication.shared.open(url)
    #elseif os(macOS)
    NSWorkspace.shared.open(url)
    #endif
}
