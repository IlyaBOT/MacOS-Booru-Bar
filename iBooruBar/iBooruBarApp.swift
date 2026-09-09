//
//  iBooruBarApp.swift
//  iBooruBar
//
//  Created by IlyaBOT on 08.09.2026.
//

import SwiftUI

@main
struct iBooruBarApp: App {
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            MobileContentView(settingsStore: settingsStore)
        }
    }
}
