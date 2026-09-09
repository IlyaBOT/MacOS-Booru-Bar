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
                        VStack(alignment: .leading) {
                            Text(site.name)

                            Text(site.apiType.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
