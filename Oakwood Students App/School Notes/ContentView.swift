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
            Tab("Calendar", systemImage: "calendar") {
                ICSView(string: "https://api.veracross.com/oakwood/subscribe/9E7F7993-EB95-4710-B481-AF2130F54B16.ics?uid=D2AF59EB-A594-4ECF-B72E-93428BD7576B" )
            }
            Tab("Vercross", systemImage: "book.fill") {
                VeracrossGradesView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingView()
            }
        }
    }
}

