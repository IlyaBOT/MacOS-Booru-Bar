import SwiftUI

@available(macOS 12.0, *)
struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onDone: () -> Void

    @State private var draftSites: [BooruSite] = []
    @State private var draftAPIKeys: [UUID: String] = [:]
    @State private var selectedSiteID: UUID?
    @State private var editingSiteID: UUID?
    @State private var isAddingSite = false
    @State private var name = ""
    @State private var baseURLString = ""
    @State private var apiKey = ""
    @State private var apiType: BooruProtocol = .philomena
    @State private var errorMessage: String?
    @State private var didLoadDrafts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())

                Spacer()

                Button("Apply") {
                    applyAndClose()
                }
                .keyboardShortcut(.defaultAction)
            }

            Toggle("Allow NSFW content", isOn: nsfwBinding)
            Toggle("Play animations and videos", isOn: playAnimatedMediaBinding)

            Divider()

            HStack(spacing: 16) {
                siteList
                editorPanel
            }
        }
        .padding(18)
        .frame(width: 460, height: 720)
        .onAppear {
            loadDraftsIfNeeded()
        }
        .onChange(of: selectedSiteID) { newValue in
            guard let newValue, !isAddingSite else {
                return
            }

            _ = stageCurrentEdit(showErrors: false)
            selectDraftSite(newValue)
        }
        .onChange(of: baseURLString) { newValue in
            if let detectedAPIType = detectedAPIType(for: newValue) {
                apiType = detectedAPIType
            }
        }
    }

    private var siteList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Booru Sites")
                    .font(.headline)

                Spacer()

                Button {
                    startNewSite()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add custom booru site")

                Button(role: .destructive) {
                    deleteSelectedSite()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(!canDeleteSelectedSite)
                .help("Delete custom booru site")
            }

            List(selection: $selectedSiteID) {
                ForEach(draftSites) { site in
                    HStack {
                        Text(site.name)
                            .lineLimit(1)

                        Spacer()

                        Text(site.resolvedProtocol.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if draftAPIKeys[site.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                            Image(systemName: "key")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(Optional(site.id))
                }
            }
        }
        .frame(width: 210)
    }

    @ViewBuilder
    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAddingSite {
                editorFields(title: "Add Site", showsAddActions: true)
            } else if editingSiteID != nil {
                editorFields(title: "Edit Site")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Select a booru site or add a new one.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func editorFields(title: String, showsAddActions: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            TextField("Display name", text: $name)

            TextField("Base URL", text: $baseURLString)

            HStack(spacing: 8) {
                Text("API:")
                    .foregroundStyle(.secondary)

                Picker("API", selection: $apiType) {
                    ForEach(BooruProtocol.allCases) { apiType in
                        Text(apiType.displayName).tag(apiType)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer()
            }

            SecureField(apiKeyPlaceholder, text: $apiKey)

            if showsAddActions {
                HStack {
                    Button("Cancel") {
                        cancelNewSite()
                    }

                    Spacer()

                    Button("Add") {
                        addDraftSite()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private var nsfwBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.nsfwEnabled },
            set: { settingsStore.nsfwEnabled = $0 }
        )
    }

    private var playAnimatedMediaBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.playAnimatedMedia },
            set: { settingsStore.playAnimatedMedia = $0 }
        )
    }

    private var canDeleteSelectedSite: Bool {
        guard !isAddingSite, let site = selectedSite else {
            return false
        }

        return !settingsStore.isDefaultSite(site)
    }

    private var selectedSite: BooruSite? {
        guard let selectedSiteID else {
            return nil
        }

        return draftSites.first { $0.id == selectedSiteID }
    }

    private var apiKeyPlaceholder: String {
        switch apiType {
        case .philomena:
            return "API key (optional)"
        case .e621, .danbooru:
            return "username:api_key (optional)"
        case .gelbooru:
            return "user_id:api_key (Gelbooru may require this)"
        case .moebooru:
            return "Authentication not required for browsing"
        case .shimmie:
            return "Authentication is server-specific (optional)"
        }
    }

    private func loadDraftsIfNeeded() {
        guard !didLoadDrafts else {
            return
        }

        didLoadDrafts = true
        draftSites = settingsStore.sites
        draftAPIKeys = Dictionary(uniqueKeysWithValues: draftSites.map { site in
            (site.id, settingsStore.apiKey(for: site) ?? "")
        })

        if draftSites.contains(where: { $0.id == settingsStore.selectedSiteID }) {
            selectDraftSite(settingsStore.selectedSiteID)
        } else if let firstSiteID = draftSites.first?.id {
            selectDraftSite(firstSiteID)
        } else {
            clearEditor()
        }
    }

    private func startNewSite() {
        if !isAddingSite {
            _ = stageCurrentEdit(showErrors: false)
        }

        selectedSiteID = nil
        editingSiteID = nil
        isAddingSite = true
        name = ""
        baseURLString = "https://"
        apiKey = ""
        apiType = .philomena
        errorMessage = nil
    }

    private func cancelNewSite() {
        isAddingSite = false
        errorMessage = nil

        if let selectedSiteID, draftSites.contains(where: { $0.id == selectedSiteID }) {
            selectDraftSite(selectedSiteID)
        } else if draftSites.contains(where: { $0.id == settingsStore.selectedSiteID }) {
            selectDraftSite(settingsStore.selectedSiteID)
        } else if let firstSiteID = draftSites.first?.id {
            selectDraftSite(firstSiteID)
        } else {
            clearEditor()
        }
    }

    private func addDraftSite() {
        let newID = UUID()
        guard let site = validatedSite(id: newID, showErrors: true) else {
            return
        }

        draftSites.append(site)
        draftAPIKeys[site.id] = apiKey
        isAddingSite = false
        selectDraftSite(site.id)
    }

    private func selectDraftSite(_ siteID: UUID) {
        guard let site = draftSites.first(where: { $0.id == siteID }) else {
            return
        }

        selectedSiteID = site.id
        editingSiteID = site.id
        isAddingSite = false
        name = site.name
        baseURLString = site.baseURL.absoluteString
        apiType = site.resolvedProtocol
        apiKey = draftAPIKeys[site.id] ?? ""
        errorMessage = nil
    }

    private func stageCurrentEdit(showErrors: Bool) -> Bool {
        guard !isAddingSite, let editingSiteID else {
            return true
        }

        guard let site = validatedSite(id: editingSiteID, showErrors: showErrors) else {
            return false
        }

        if let index = draftSites.firstIndex(where: { $0.id == editingSiteID }) {
            draftSites[index] = site
        } else {
            draftSites.append(site)
        }

        draftAPIKeys[site.id] = apiKey
        return true
    }

    private func validatedSite(id: UUID, showErrors: Bool) -> BooruSite? {
        if showErrors {
            errorMessage = nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            if showErrors {
                errorMessage = "Display name is required."
            }
            return nil
        }

        guard let baseURL = URL(string: trimmedBaseURL),
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil else {
            if showErrors {
                errorMessage = "Enter a valid base URL."
            }
            return nil
        }

        let resolvedAPIType = BooruProtocol.detected(from: baseURL) ?? apiType
        return BooruSite(
            id: id,
            name: trimmedName,
            baseURL: baseURL,
            apiType: resolvedAPIType.legacyAPIType,
            protocolType: resolvedAPIType,
            hasAPIKey: !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private func detectedAPIType(for baseURLString: String) -> BooruProtocol? {
        guard let url = URL(string: baseURLString) else {
            return nil
        }
        return BooruProtocol.detected(from: url)
    }

    private func applyAndClose() {
        guard !isAddingSite else {
            errorMessage = "Add or cancel the new site before applying."
            return
        }

        guard stageCurrentEdit(showErrors: true) else {
            return
        }

        let desiredSelectedSiteID = selectedSiteID
        let draftSiteIDs = Set(draftSites.map(\.id))

        for existingSite in settingsStore.sites where !draftSiteIDs.contains(existingSite.id) {
            settingsStore.deleteSite(existingSite)
        }

        do {
            for site in draftSites {
                try settingsStore.upsertSite(site, apiKey: draftAPIKeys[site.id] ?? "")
            }

            if let desiredSelectedSiteID,
               settingsStore.sites.contains(where: { $0.id == desiredSelectedSiteID }) {
                settingsStore.selectedSiteID = desiredSelectedSiteID
            } else if let firstSiteID = settingsStore.sites.first?.id {
                settingsStore.selectedSiteID = firstSiteID
            }

            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedSite() {
        guard let site = selectedSite, canDeleteSelectedSite else {
            return
        }

        let deletedIndex = draftSites.firstIndex(where: { $0.id == site.id }) ?? 0
        draftSites.removeAll { $0.id == site.id }
        draftAPIKeys[site.id] = nil

        if draftSites.isEmpty {
            clearEditor()
            return
        }

        let nextIndex = min(deletedIndex, draftSites.count - 1)
        selectDraftSite(draftSites[nextIndex].id)
    }

    private func clearEditor() {
        selectedSiteID = nil
        editingSiteID = nil
        isAddingSite = false
        name = ""
        baseURLString = ""
        apiKey = ""
        apiType = .philomena
        errorMessage = nil
    }
}
