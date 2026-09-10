//
//  BooruBarApp.swift
//  BooruBar
//
//  Created by IlyaBOT on 21.06.2026.
//

import AppKit
import SwiftUI

@main
struct BooruBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 460, height: 720)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(settingsStore: settingsStore)
                .frame(width: 460, height: 720)
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "photo.on.rectangle.angled",
                accessibilityDescription: "BooruBar"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        popover.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
