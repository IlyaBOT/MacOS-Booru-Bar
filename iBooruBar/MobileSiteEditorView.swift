import SwiftUI

struct MobileSiteEditorView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.presentationMode) private var presentationMode

    private let existingSite: BooruSite?

    @State private var name: String
    @State private var baseURLString: String
    @State private var apiType: BooruProtocol
    @State private var authenticationMode: BooruAuthenticationMode
    @State private var username: String
    @State private var password: String
    @State private var userID: String
    @State private var apiKey: String
    @State private var errorMessage: String?

    init(settingsStore: SettingsStore, site: BooruSite?) {
        self.settingsStore = settingsStore
        self.existingSite = site

        let initialSite = site ?? BooruSite(
            name: "",
            baseURL: URL(string: "https://example.com")!,
            apiType: .philomena,
            protocolType: .philomena
        )

        _name = State(initialValue: site?.name ?? "")
        _baseURLString = State(initialValue: site?.baseURL.absoluteString ?? "https://")
        _apiType = State(initialValue: initialSite.resolvedProtocol)
        _authenticationMode = State(initialValue: site.map { settingsStore.authenticationMode(for: $0) } ?? .none)
        _username = State(initialValue: site.flatMap { settingsStore.username(for: $0) } ?? "")
        _password = State(initialValue: site.flatMap { settingsStore.password(for: $0) } ?? "")
        _userID = State(initialValue: site.flatMap { settingsStore.userID(for: $0) } ?? "")
        _apiKey = State(initialValue: site.flatMap { settingsStore.apiKey(for: $0) } ?? "")
    }

    var body: some View {
        Form {
            Section("Source") {
                TextField("Display Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Base URL", text: $baseURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("API Type", selection: $apiType) {
                    ForEach(BooruProtocol.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            Section {
                Picker("Authorization", selection: $authenticationMode) {
                    ForEach(BooruAuthenticationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                switch authenticationMode {
                case .none:
                    Text("Browsing remains available anonymously. Actions that require an account are disabled.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                case .apiKey:
                    apiKeyFields

                case .credentials:
                    TextField("Username / Email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    credentialsNotice
                }
            } header: {
                Text("Authorization")
            } footer: {
                Text(authenticationFooter)
            }

            if apiType == .shimmie {
                Section {
                    Text("Shimmie does not define a universal rating field. The global NSFW filter cannot be guaranteed for arbitrary Shimmie installations.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            if let existingSite, !settingsStore.isDefaultSite(existingSite) {
                Section {
                    Button("Delete Source", role: .destructive) {
                        settingsStore.deleteSite(existingSite)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationTitle(existingSite == nil ? "Add Source" : "Edit Source")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .onChange(of: baseURLString) { newValue in
            guard let url = URL(string: newValue),
                  let detected = BooruProtocol.detected(from: url) else {
                return
            }
            apiType = detected
        }
    }

    @ViewBuilder
    private var apiKeyFields: some View {
        switch apiType {
        case .e621, .danbooru:
            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("API Key", text: $apiKey)

        case .gelbooru:
            TextField("User ID", text: $userID)
                .keyboardType(.numberPad)
            SecureField("API Key", text: $apiKey)

        case .philomena:
            SecureField("API Key", text: $apiKey)

        case .moebooru, .shimmie:
            SecureField("API Key / Token (optional)", text: $apiKey)
        }
    }

    private var credentialsNotice: some View {
        Text("Password login is stored securely for future browser-session authorization. The current public APIs do not provide a universal username/password write flow.")
            .font(.footnote)
            .foregroundColor(.secondary)
    }

    private var authenticationFooter: String {
        switch apiType {
        case .e621:
            return "e621 API actions use HTTP Basic authentication with your username and API key. Password credentials cannot vote or post comments through the API."

        case .philomena:
            return "Philomena API keys authenticate JSON reads and expose your image interaction state. Voting and posting comments are browser-session routes and are not exposed as public token API actions."

        case .gelbooru:
            return "Gelbooru DAPI uses User ID + API Key for authenticated reads. Stable public write endpoints for votes/comments are not documented."

        case .moebooru:
            return "Moebooru /post.json browsing is anonymous. Legacy account authentication differs between installations and is not required for browsing."

        case .danbooru:
            return "Danbooru API authentication uses your username and API key over HTTP Basic. Browsing works anonymously; authenticated write actions are not enabled yet."

        case .shimmie:
            return "Shimmie browsing uses the Danbooru Client API extension. Authentication and write APIs are installation-specific, so this integration is read-only."
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedURL != nil
    }

    private var normalizedURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func save() {
        guard let baseURL = normalizedURL else {
            errorMessage = "Enter a valid http:// or https:// URL."
            return
        }

        let resolvedAPIType = BooruProtocol.detected(from: baseURL) ?? apiType
        let site = BooruSite(
            id: existingSite?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL,
            apiType: resolvedAPIType.legacyAPIType,
            protocolType: resolvedAPIType,
            hasAPIKey: !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        let previousSelectedSiteID = settingsStore.selectedSiteID

        do {
            try settingsStore.upsertSite(site, apiKey: apiKey)
            try settingsStore.saveAuthentication(
                for: site,
                mode: authenticationMode,
                username: username,
                password: password,
                userID: userID,
                apiKey: apiKey
            )

            if existingSite != nil,
               previousSelectedSiteID != site.id,
               settingsStore.sites.contains(where: { $0.id == previousSelectedSiteID }) {
                settingsStore.selectedSiteID = previousSelectedSiteID
            }

            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
