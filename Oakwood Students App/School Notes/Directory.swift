//
//  Directory.swift
//  School Notes
//

import SwiftUI
import SwiftSoup

// MARK: - Models

struct DirectoryPerson: Identifiable {
    let id = UUID()
    let name: String
    let grade: String
    let photoURL: String?
    let studentEmail: String?
    let households: [DirectoryHousehold]

    var displayName: String {
        if let parenStart = name.firstIndex(of: "("),
           let parenEnd = name.firstIndex(of: ")") {
            let before = String(name[..<parenStart]).trimmingCharacters(in: .whitespaces)
            let after = String(name[name.index(after: parenEnd)...]).trimmingCharacters(in: .whitespaces)
            return "\(before) \(after)"
        }
        return name
    }
}

struct DirectoryHousehold: Identifiable {
    let id = UUID()
    let address: String?
    let contacts: [DirectoryContact]
}

struct DirectoryContact: Identifiable {
    let id = UUID()
    let name: String
    let phone: String?
    let email: String?
}

// MARK: - Scraping

func fetchDirectoryPage1(queryItems: [URLQueryItem]) async -> ([DirectoryPerson], String?) {
    var components = URLComponents(string: "https://portals.veracross.com/oakwood/student/directory/1")!
    if !queryItems.isEmpty { components.queryItems = queryItems }
    guard let url = components.url,
          let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url).withDirectoryHeaders()),
          let html = String(data: data, encoding: .utf8),
          let doc = try? SwiftSoup.parse(html) else { return ([], nil) }

    let csrf = try? doc.select("meta[name=csrf-token]").first()?.attr("content")
    guard let entries = try? doc.select("div.directory-Entry"), !entries.isEmpty() else {
        return ([], csrf)
    }
    return (entries.array().compactMap { parseDirectoryEntry($0) }, csrf)
}

private func fetchDirectoryPageN(page: Int, queryItems: [URLQueryItem], csrfToken: String) async -> [DirectoryPerson] {
    var components = URLComponents(string: "https://portals.veracross.com/oakwood/student/directory/1/directory_entries/\(page)")!
    if !queryItems.isEmpty { components.queryItems = queryItems }
    guard let url = components.url,
          let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url).withDirectoryHeaders(csrf: csrfToken)),
          let jsText = String(data: data, encoding: .utf8) else { return [] }

    let html = jsText
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\'", with: "'")
        .replacingOccurrences(of: "<\\/", with: "</")
        .replacingOccurrences(of: "\\n", with: "\n")

    guard let doc = try? SwiftSoup.parse(html),
          let entries = try? doc.select("div.directory-Entry"),
          !entries.isEmpty() else { return [] }
    return entries.array().compactMap { parseDirectoryEntry($0) }
}

private func parseDirectoryEntry(_ entry: Element) -> DirectoryPerson? {
    guard let name = try? entry.select("div.directory-Entry_Title").first()?.text().trimmingCharacters(in: .whitespaces),
          !name.isEmpty else { return nil }

    let grade = (try? entry.select("div.directory-Entry_Tag").first()?.text().trimmingCharacters(in: .whitespaces)) ?? ""

    let photoURL: String? = {
        guard let style = try? entry.select("div.directory-Entry_PersonPhoto--square").first()?.attr("style"),
              let start = style.range(of: "url("),
              let end = style.range(of: ")", range: start.upperBound..<style.endIndex) else { return nil }
        return String(style[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .replacingOccurrences(of: "&amp;", with: "&")
    }()

    let studentEmail: String? = {
        let email = try? entry.select("div.directory-Entry_Header a[href^=mailto]").first()?.text()
        return email?.isEmpty == false ? email : nil
    }()

    let households: [DirectoryHousehold] = {
        guard let sections = try? entry.select("div.directory-Entry_HouseholdSection").array() else { return [] }
        return sections.compactMap { section in
            let address: String? = {
                let text = (try? section.select("div.directory-Entry_FieldTitle").first()?.ownText().trimmingCharacters(in: .whitespaces)) ?? ""
                return text.isEmpty ? nil : text
            }()
            let contacts: [DirectoryContact] = ((try? section.select("div.ae-grid__item.item-md-6").array()) ?? []).compactMap { div in
                guard let parentName = try? div.select("div.directory-Entry_FieldTitle--blue").first()?.text().trimmingCharacters(in: .whitespaces),
                      !parentName.isEmpty else { return nil }
                let phone = (try? div.select("a[href^=tel]").first()?.text()).flatMap { $0.isEmpty ? nil : $0 }
                let email = (try? div.select("a[href^=mailto]").first()?.text()).flatMap { $0.isEmpty ? nil : $0 }
                return DirectoryContact(name: parentName, phone: phone, email: email)
            }
            guard address != nil || !contacts.isEmpty else { return nil }
            return DirectoryHousehold(address: address, contacts: contacts)
        }
    }()

    return DirectoryPerson(name: name, grade: grade, photoURL: photoURL, studentEmail: studentEmail, households: households)
}

private extension URLRequest {
    func withDirectoryHeaders(csrf: String? = nil) -> URLRequest {
        var r = self
        r.httpShouldHandleCookies = true
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = 15
        if let csrf {
            r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            r.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
            r.setValue("text/javascript, application/javascript", forHTTPHeaderField: "Accept")
        }
        return r
    }
}

// MARK: - Directory List View

struct DirectoryView: View {
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

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    DirectoryPhoto(urlString: person.photoURL, size: 72)
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

    var body: some View {
        Group {
            if let urlStr = urlString, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { placeholderView }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholderView: some View {
        Color(.systemGray5).overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
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
