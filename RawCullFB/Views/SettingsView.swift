//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    @State private var settingsLoaded = false

    var body: some View {
        Group {
            TabView {
                MemoryTab()
                    .tabItem {
                        Label("Memory", systemImage: "rectangle.compress.vertical")
                    }
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
    }
}
