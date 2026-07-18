//
//  Mac_DirectoryView.swift
//  School Notes
//
import SwiftUI

struct Mac_DirectoryView: View {
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, _ in triggerSearch() }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .padding([.horizontal, .top])

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(gradeOptions, id: \.value) { option in
                        Button {
                            selectedGrade = selectedGrade == option.value ? nil : option.value
                        } label: {
                            Text(option.label)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedGrade == option.value ? Color.accentColor : Color(nsColor: .controlColor))
                                .foregroundStyle(selectedGrade == option.value ? Color.white : Color.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if isLoading {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if !results.isEmpty {
                List(results) { person in
                    NavigationLink {
                        Mac_DirectoryPersonView(person: person)
                    } label: {
                        Mac_DirectoryPersonRow(person: person)
                    }
                }
            } else if hasQuery {
                Spacer()
                Text("No results found").foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer()
                Text("Search by name or select a grade").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle("Directory")
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

private struct Mac_DirectoryPersonRow: View {
    let person: DirectoryPerson

    var body: some View {
        HStack(spacing: 12) {
            Mac_DirectoryPhoto(urlString: person.photoURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.body)
                HStack(spacing: 6) {
                    if !person.grade.isEmpty {
                        Text(person.grade).font(.caption).foregroundStyle(.secondary)
                    }
                    if let email = person.studentEmail {
                        Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Person Detail

private struct Mac_DirectoryPersonView: View {
    let person: DirectoryPerson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Mac_DirectoryPhoto(urlString: person.photoURL, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.displayName).font(.title2.weight(.bold))
                        if !person.grade.isEmpty {
                            Text(person.grade).foregroundStyle(.secondary)
                        }
                        if let email = person.studentEmail {
                            Button { openExternalURL("mailto:\(email)") } label: {
                                Text(email).foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(person.households) { household in
                    VStack(alignment: .leading, spacing: 10) {
                        if let address = household.address {
                            Button {
                                let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                openExternalURL("https://maps.apple.com/?q=\(encoded)")
                            } label: {
                                Label(address, systemImage: "map")
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(household.contacts) { contact in
                            Mac_DirectoryContactRow(contact: contact)
                        }
                    }
                    Divider()
                }
            }
            .padding(24)
        }
        .navigationTitle(person.displayName)
    }
}

// MARK: - Contact Row

private struct Mac_DirectoryContactRow: View {
    let contact: DirectoryContact

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contact.name).font(.body.weight(.semibold))
            if let phone = contact.phone {
                Button { openExternalURL("tel:\(phone.filter { $0.isNumber || $0 == "+" })") } label: {
                    Label(phone, systemImage: "phone").foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            if let email = contact.email {
                Button { openExternalURL("mailto:\(email)") } label: {
                    Label(email, systemImage: "envelope").foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Photo Helper

struct Mac_DirectoryPhoto: View {
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
        Color(nsColor: .controlColor).overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
    }
}
