//
//  BooruBarApp.swift
//  BooruBar
//
//  Created by IlyaBOT on 21.06.2026.
//

import SwiftUI

@main
struct BooruBarApp: App {
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        MenuBarExtra("BooruBar", systemImage: "photo.on.rectangle.angled") {
            ContentView(settingsStore: settingsStore)
        }
        .menuBarExtraStyle(.window)
    }
}
