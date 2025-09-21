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
}

struct ClassS: Identifiable {
    var id = UUID()
    var name = ""
    var grade = ""
}
