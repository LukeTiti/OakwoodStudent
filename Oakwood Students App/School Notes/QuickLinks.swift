//
//  QuickLinks.swift
//  School Notes
//
//  Created by Luke Titi on 4/2/26.
//
import SwiftUI

struct QuickLinks: View {
    var links: [Link] = [
        Link(link: "https://www.oakwoodway.org/family/resource/all-school/volunteer", name: "Volunteer"),
        Link(link: "https://secure.magnushealthportal.com/vclogin/login.jsf?schoolID=666010", name: "Magnus Health"),
        Link(link: "https://www.oakwoodway.org/family/resource/all-school/choicelunch", name: "Choice Lunch"),
        Link(link: "https://www.oakwoodway.org/family/calendar", name: "School Calendar"),
        Link(link: "https://www.oakwoodway.org/family-handbook", name: "Family Handbook"),
        Link(link: "https://oakwoodschool.myshopify.com/", name: "Spirit Store"),
        Link(link: "https://www.oakwoodway.org/family/resource/all-school/dress-code", name: "Dress Code"),
        Link(link: "https://www.oakwoodway.org/fs/sso/?type=Veracross-SSO&target=parentdirectory", name: "School Directory"),
        Link(link: "https://www.oakwoodway.org/support/donate", name: "Donate")
        
    ]
    var body: some View {
        List {
            ForEach(links, id: \.self) { link in
                SwiftUI.Link(link.name, destination: URL(string: link.link)!)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Quick Links")
                    .font(.headline)
            }
        }
    }
}


struct Link: Identifiable, Hashable {
    var id = UUID()
    var link: String
    var name: String
}
