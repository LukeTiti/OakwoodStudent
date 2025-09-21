//
//  Setting.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//
import SwiftUI

struct SettingView: View {
    @EnvironmentObject var appInfo: AppInfo
    var body: some View {
        Text("Setting")
        TextField("Assignment URL", text: $appInfo.assignmentString)
        if appInfo.googleVM.isSignedIn {
            Text("Signed In!")
        }
        VStack {
            SignInView()
        }
    }
}
