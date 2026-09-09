import SwiftUI

struct MobileSettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.presentationMode)
    private var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section("Content") {
                    Toggle(
                        "Allow NSFW content",
                        isOn: $settingsStore.nsfwEnabled
                    )

                    Toggle(
                        "Play animations and videos",
                        isOn: $settingsStore.playAnimatedMedia
                    )
                }

                Section("Booru Sources") {
                    ForEach(settingsStore.sites) { site in
                        NavigationLink {
                            MobileSiteEditorView(
                                settingsStore: settingsStore,
                                site: site
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(site.name)

                                    Text(site.apiType.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if site.hasAPIKey {
                                    Image(systemName: "key")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !settingsStore.isDefaultSite(site) {
                                Button(role: .destructive) {
                                    settingsStore.deleteSite(site)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    NavigationLink {
                        MobileSiteEditorView(
                            settingsStore: settingsStore,
                            site: nil
                        )
                    } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        presentationMode
                            .wrappedValue
                            .dismiss()
                    }
                }
            }
        }
    }
}
