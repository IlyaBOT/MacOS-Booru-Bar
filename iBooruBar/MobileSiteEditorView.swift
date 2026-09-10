import SwiftUI

struct MobileSiteEditorView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.presentationMode) private var presentationMode

    private let existingSite: BooruSite?

    @State private var name: String
    @State private var baseURLString: String
    @State private var apiType: BooruAPIType
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
            apiType: .philomena
        )

        _name = State(initialValue: site?.name ?? "")
        _baseURLString = State(initialValue: site?.baseURL.absoluteString ?? "https://")
        _apiType = State(initialValue: initialSite.apiType)
        _authenticationMode = State(initialValue: site.map(settingsStore.authenticationMode(for:)) ?? .none)
        _username = State(initialValue: site.flatMap(settingsStore.username(for:)) ?? "")
        _password = State(initialValue: site.flatMap(settingsStore.password(for:)) ?? "")
        _userID = State(initialValue: site.flatMap(settingsStore.userID(for:)) ?? "")
        _apiKey = State(initialValue: site.flatMap(settingsStore.apiKey(for:)) ?? "")
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
                    ForEach(BooruAPIType.allCases) { type in
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
        .onChange(of: apiType) { _ in
            // Credentials are intentionally retained when switching API type,
            // but the UI immediately shows the fields required by the new API.
        }
    }

    @ViewBuilder
    private var apiKeyFields: some View {
        switch apiType {
        case .e621:
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

        let site = BooruSite(
            id: existingSite?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL,
            apiType: apiType,
            hasAPIKey: !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

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
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
