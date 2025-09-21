//
//  Observable Class.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//
import SwiftUI
import Combine
import GoogleSignIn

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
    @Published var fetchedGrades: [String] = []
    @Published var info: [Int: Bool] = [:] {
        didSet {
            saveInfo()
        }
    }
    
    init() {
        loadInfo()
    }
    
    private func saveInfo() {
        if let encoded = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(encoded, forKey: "assignmentInfo")
        }
    }
    
    private func loadInfo() {
        if let data = UserDefaults.standard.data(forKey: "assignmentInfo"),
           let decoded = try? JSONDecoder().decode([Int: Bool].self, from: data) {
            info = decoded
        }
    }
    
    // Optional helper
    func toggleInfo(for id: Int) {
        info[id] = !(info[id] ?? false)
    }
}


struct ClassS: Identifiable {
    var id = UUID()
    var name = ""
    var grade = ""
}
