//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Group {
            TabView {
                MemoryTab()
                    .tabItem {
                        Label("Memory", systemImage: "rectangle.compress.vertical")
                    }

                CLIPSettingsTab()
                    .tabItem {
                        Label("CLIP", systemImage: "sparkle.magnifyingglass")
                    }
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
    }
}
