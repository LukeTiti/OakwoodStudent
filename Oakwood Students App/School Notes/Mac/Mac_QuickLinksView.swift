//
//  Mac_QuickLinksView.swift
//  School Notes
//
import SwiftUI

struct Mac_QuickLinksView: View {
    private let links = QuickLinks().links
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(links) { link in
                    SwiftUI.Link(destination: URL(string: link.link)!) {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            Text(link.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Quick Links")
    }
}
