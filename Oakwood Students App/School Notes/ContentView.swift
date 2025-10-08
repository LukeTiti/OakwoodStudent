//
//  ContentView.swift
//  School Notes
//
//  Created by Luke Titi on 9/3/25.
//

import SwiftUI

struct ContentView: View {
    let urls = [
        URL(string: "http://on.aesd.ch/Images/Precalc%201.4%20CPA.png")!
    ]
    @EnvironmentObject var appInfo: AppInfo
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Notes", systemImage: "book") {
                ClassNotes()
                    .id(appInfo.reloadID)
                    .onChange(of: appInfo.googleVM.isSignedIn) { signedIn in
                        if signedIn {
                            appInfo.reloadID = UUID()
                        }
                    }
            }
            Tab("To Do", systemImage: "list.bullet") {
                ToDoPage()
            }
            Tab("Grades", systemImage: "list.bullet.rectangle.portrait") {
                VeracrossGradesView()
            }
            Tab("Sports", systemImage: "trophy.fill") {
                SportsView()
            }
        }
    }
}

