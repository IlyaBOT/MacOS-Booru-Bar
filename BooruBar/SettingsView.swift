import SwiftUI

@available(macOS 12.0, *)
struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onDone: () -> Void

    @State private var draftSites: [BooruSite] = []
    @State private var draftAPIKeys: [UUID: String] = [:]
    @State private var draftUsernames: [UUID: String] = [:]
    @State private var draftPasswords: [UUID: String] = [:]
    @State private var draftUserIDs: [UUID: String] = [:]
    @State private var draftAuthenticationModes: [UUID: BooruAuthenticationMode] = [:]

    @State private var selectedSiteID: UUID?
    @State private var editingSiteID: UUID?
    @State private var isAddingSite = false

    @State private var name = ""
    @State private var baseURLString = ""
    @State private var apiType: BooruProtocol = .philomena
    @State private var authenticationMode: BooruAuthenticationMode = .none
    @State private var username = ""
    @State private var password = ""
    @State private var userID = ""
    @State private var apiKey = ""

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
                    HStack(spacing: 6) {
                        Text(site.name)
                            .lineLimit(1)

                        Spacer()

                        Text(site.resolvedProtocol.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if draftAuthenticationModes[site.id] != .none {
                            Image(systemName: authenticationIcon(for: site.id))
                                .font(.caption)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                TextField("Display name", text: $name)
                TextField("Base URL", text: $baseURLString)

                HStack(spacing: 8) {
                    Text("API:")
                        .foregroundStyle(.secondary)

                    Picker("API", selection: $apiType) {
                        ForEach(BooruProtocol.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Spacer()
                }

                Divider()

                Text("Authorization")
                    .font(.headline)

                Picker("Authorization", selection: $authenticationMode) {
                    ForEach(BooruAuthenticationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                authenticationFields

                Text(authenticationFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if apiType == .shimmie {
                    Text("Shimmie does not define a universal rating field, so the global NSFW filter cannot be guaranteed on arbitrary installations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var authenticationFields: some View {
        switch authenticationMode {
        case .none:
            Text("Browsing remains anonymous. Account-only actions are disabled.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .apiKey:
            switch apiType {
            case .e621, .danbooru:
                TextField("Username", text: $username)
                SecureField("API Key", text: $apiKey)

            case .gelbooru:
                TextField("User ID", text: $userID)
                SecureField("API Key", text: $apiKey)

            case .philomena:
                SecureField("API Key", text: $apiKey)

            case .moebooru, .shimmie:
                SecureField("API Key / Token (optional)", text: $apiKey)
            }

        case .credentials:
            TextField("Username / Email", text: $username)
            SecureField("Password", text: $password)

            Text("Credentials are stored in Keychain. They are available for site-specific browser/session authorization; public APIs do not provide one universal username/password write flow.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authenticationFooter: String {
        switch apiType {
        case .e621:
            return "e621 API actions use your username + API key with HTTP Basic authentication. Password credentials cannot vote or post comments through the public API."
        case .philomena:
            return "Philomena API keys authenticate JSON reads and expose interaction state. Voting and comment posting remain browser-session routes."
        case .gelbooru:
            return "Gelbooru DAPI uses User ID + API Key for authenticated reads. Stable public vote/comment write endpoints are not documented."
        case .moebooru:
            return "Moebooru browsing works anonymously. Legacy account authentication differs between installations."
        case .danbooru:
            return "Danbooru API authentication uses username + API key over HTTP Basic. Browsing works anonymously; write interactions are not enabled yet."
        case .shimmie:
            return "Shimmie authentication and write APIs are installation-specific. The current integration is read-only."
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
        guard let selectedSiteID else { return nil }
        return draftSites.first { $0.id == selectedSiteID }
    }

    private func authenticationIcon(for siteID: UUID) -> String {
        switch draftAuthenticationModes[siteID] ?? .none {
        case .none:
            return "lock.open"
        case .apiKey:
            return "key.fill"
        case .credentials:
            return "person.crop.circle.fill"
        }
    }

    private func loadDraftsIfNeeded() {
        guard !didLoadDrafts else { return }

        didLoadDrafts = true
        draftSites = settingsStore.sites

        for site in draftSites {
            draftAPIKeys[site.id] = settingsStore.apiKey(for: site) ?? ""
            draftUsernames[site.id] = settingsStore.username(for: site) ?? ""
            draftPasswords[site.id] = settingsStore.password(for: site) ?? ""
            draftUserIDs[site.id] = settingsStore.userID(for: site) ?? ""
            draftAuthenticationModes[site.id] = settingsStore.authenticationMode(for: site)
        }

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
        apiType = .philomena
        authenticationMode = .none
        username = ""
        password = ""
        userID = ""
        apiKey = ""
        errorMessage = nil
    }

    private func cancelNewSite() {
        isAddingSite = false
        errorMessage = nil

        if let selectedSiteID,
           draftSites.contains(where: { $0.id == selectedSiteID }) {
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
        storeAuthenticationDraft(for: newID)
        isAddingSite = false
        selectDraftSite(newID)
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
        authenticationMode = draftAuthenticationModes[site.id] ?? .none
        username = draftUsernames[site.id] ?? ""
        password = draftPasswords[site.id] ?? ""
        userID = draftUserIDs[site.id] ?? ""
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

        storeAuthenticationDraft(for: editingSiteID)
        return true
    }

    private func storeAuthenticationDraft(for siteID: UUID) {
        draftAuthenticationModes[siteID] = authenticationMode
        draftUsernames[siteID] = username
        draftPasswords[siteID] = password
        draftUserIDs[siteID] = userID
        draftAPIKeys[siteID] = apiKey
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
        guard let url = URL(string: baseURLString) else { return nil }
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
                let key = draftAPIKeys[site.id] ?? ""
                try settingsStore.upsertSite(site, apiKey: key)
                try settingsStore.saveAuthentication(
                    for: site,
                    mode: draftAuthenticationModes[site.id] ?? .none,
                    username: draftUsernames[site.id] ?? "",
                    password: draftPasswords[site.id] ?? "",
                    userID: draftUserIDs[site.id] ?? "",
                    apiKey: key
                )
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
        draftUsernames[site.id] = nil
        draftPasswords[site.id] = nil
        draftUserIDs[site.id] = nil
        draftAuthenticationModes[site.id] = nil

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
        apiType = .philomena
        authenticationMode = .none
        username = ""
        password = ""
        userID = ""
        apiKey = ""
        errorMessage = nil
    }
}
