//
//  Observable Class.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//
import SwiftUI
import Combine
import GoogleSignIn
import WebKit

struct GoogleLoginSnapshot: Codable {
    var isSignedIn: Bool
    var userName: String
    var userEmail: String
}

class AppInfo: ObservableObject {
    @Published var fetchedString: [String] = []
    @Published var fetchedScoopString: [String] = []
    @Published var assignmentString: String = ""
    @Published var isSignedIn: Bool = false
    @Published var userName: String = ""
    @Published var password: String = ""
    @Published var googleVM = GoogleSignInViewModel()
    @Published var approvedEmails: [String] = []
    @Published var reloadID = UUID()
    @Published var signInSheet = false
    @Published var classes: [ClassS] = []
    @Published var courses: [Course] = []
    @Published var fetchedGrades: [String] = []
    @Published var info: [Int: Bool] = [:] {
        didSet {
            saveAssignmentInfo()
        }
    }

    // MARK: Cookie persistence
    // Store cookies as property dictionaries (HTTPCookie.propertyKeys) and a timestamp
    @Published var persistedCookies: [[HTTPCookiePropertyKey: Any]] = [] {
        didSet { saveCookies() }
    }
    @Published var cookiesLastSaved: Date? {
        didSet { saveCookies() }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadAssignmentInfo()
        loadCookies()
        loadGoogleLogin()

        // Observe googleVM published properties and persist snapshot when they change
        googleVM.$isSignedIn
            .combineLatest(googleVM.$userName, googleVM.$userEmail)
            .sink { [weak self] isSignedIn, name, email in
                self?.saveGoogleLogin(snapshot: GoogleLoginSnapshot(isSignedIn: isSignedIn, userName: name, userEmail: email))
            }
            .store(in: &cancellables)
    }

    private func saveAssignmentInfo() {
        if let encoded = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(encoded, forKey: "assignmentInfo")
        }
    }

    private func loadAssignmentInfo() {
        if let data = UserDefaults.standard.data(forKey: "assignmentInfo"),
           let decoded = try? JSONDecoder().decode([Int: Bool].self, from: data) {
            info = decoded
        }
    }

    // MARK: - Google VM persistence
    private func saveGoogleLogin(snapshot: GoogleLoginSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: "googleLoginSnapshot")
        }
    }

    private func loadGoogleLogin() {
        guard let data = UserDefaults.standard.data(forKey: "googleLoginSnapshot"),
              let snap = try? JSONDecoder().decode(GoogleLoginSnapshot.self, from: data) else {
            return
        }
        // Restore into the live VM on the main thread
        DispatchQueue.main.async {
            self.googleVM.isSignedIn = snap.isSignedIn
            self.googleVM.userName = snap.userName
            self.googleVM.userEmail = snap.userEmail
        }
    }

    // Optional helper
    func toggleInfo(for id: Int) {
        info[id] = !(info[id] ?? false)
    }

    // MARK: - Cookies: Save/Load
    private func saveCookies() {
        // Convert [[HTTPCookiePropertyKey: Any]] to [[String: Any]] for UserDefaults
        let dicts: [[String: Any]] = persistedCookies.map { dict in
            var out: [String: Any] = [:]
            for (k, v) in dict {
                out[k.rawValue] = v
            }
            return out
        }
        UserDefaults.standard.set(dicts, forKey: "persistedCookies")
        if let last = cookiesLastSaved {
            UserDefaults.standard.set(last.timeIntervalSince1970, forKey: "cookiesLastSaved")
        } else {
            UserDefaults.standard.removeObject(forKey: "cookiesLastSaved")
        }
    }

    private func loadCookies() {
        guard let raw = UserDefaults.standard.array(forKey: "persistedCookies") as? [[String: Any]] else {
            persistedCookies = []
            cookiesLastSaved = nil
            return
        }
        let rebuilt: [[HTTPCookiePropertyKey: Any]] = raw.map { dict in
            var out: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in dict {
                out[HTTPCookiePropertyKey(k)] = v
            }
            return out
        }
        persistedCookies = rebuilt
        if let ts = UserDefaults.standard.value(forKey: "cookiesLastSaved") as? TimeInterval {
            cookiesLastSaved = Date(timeIntervalSince1970: ts)
        } else {
            cookiesLastSaved = nil
        }
    }

    // MARK: - Cookies: Export from storages into persistedCookies
    func captureCurrentCookies() async {
        let httpStore = HTTPCookieStorage.shared
        let wkStore = WKWebsiteDataStore.default().httpCookieStore

        // Gather cookies from both stores
        let sharedCookies = httpStore.cookies ?? []

        let wkCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            wkStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        // Merge by name+domain+path to avoid duplicates
        var merged: [String: HTTPCookie] = [:]
        let keyFor: (HTTPCookie) -> String = { "\($0.name)|\($0.domain)|\($0.path)" }
        for c in sharedCookies { merged[keyFor(c)] = c }
        for c in wkCookies { merged[keyFor(c)] = c }

        // Convert to property dictionaries
        let propertyDicts: [[HTTPCookiePropertyKey: Any]] = merged.values.compactMap { cookie in
            cookie.properties
        }

        await MainActor.run {
            self.persistedCookies = propertyDicts
            self.cookiesLastSaved = Date()
        }
    }

    // MARK: - Cookies: Restore persisted cookies back to storages
    func restorePersistedCookiesIntoStores() async {
        guard !persistedCookies.isEmpty else { return }

        let httpStore = HTTPCookieStorage.shared
        let wkStore = WKWebsiteDataStore.default().httpCookieStore

        // Recreate cookies
        let cookies = persistedCookies.compactMap { HTTPCookie(properties: $0) }

        // Insert into shared HTTPCookieStorage
        for cookie in cookies {
            httpStore.setCookie(cookie)
        }

        // Insert into WKWebView cookie store
        await withTaskGroup(of: Void.self) { group in
            for cookie in cookies {
                group.addTask {
                    await withCheckedContinuation { cont in
                        wkStore.setCookie(cookie) {
                            cont.resume()
                        }
                    }
                }
            }
        }
    }
}

struct ClassS: Identifiable {
    var id = UUID()
    var name = ""
    var grade = ""
}
