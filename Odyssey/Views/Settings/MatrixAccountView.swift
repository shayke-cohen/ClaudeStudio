// Odyssey/Views/Settings/MatrixAccountView.swift
import SwiftUI

struct MatrixAccountView: View {
    @Environment(AppState.self) private var appState

    @State private var homeserverText = "https://matrix.org"
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var isRegistering = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var credentials: MatrixCredentials?
    @State private var syncStatus: String = "Not connected"
    @State private var lastSyncDate: Date?
    @State private var showShareProfile = false

    private let instanceName = InstanceConfig.name

    var body: some View {
        Form {
            if let creds = credentials {
                connectedSection(creds)
            } else {
                signInSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Matrix Account")
        .stableXrayId("settings.federation.matrixAccount")
        .onAppear { loadCurrentCredentials() }
        .sheet(isPresented: $showShareProfile) {
            if let creds = credentials {
                UserInviteSheet(matrixUserId: creds.userId, instanceName: instanceName)
            }
        }
    }

    // MARK: - Sign-in form

    private var signInSection: some View {
        Section("Matrix Account") {
            TextField("Homeserver URL", text: $homeserverText)
                .stableXrayId("settings.federation.homeserverField")
            TextField("Username", text: $username)
                .stableXrayId("settings.federation.usernameField")
            SecureField("Password", text: $password)
                .stableXrayId("settings.federation.passwordField")

            if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }
            if let success = successMessage {
                Text(success).foregroundColor(.green)
            }

            HStack {
                Button("Sign In") { Task { await signIn() } }
                    .disabled(isSigningIn || username.isEmpty || password.isEmpty)
                    .stableXrayId("settings.federation.signInButton")
                    .accessibilityLabel("Sign in to Matrix")

                Button("Create Account") { Task { await register() } }
                    .disabled(isRegistering || username.isEmpty || password.isEmpty)
                    .stableXrayId("settings.federation.createAccountButton")
                    .accessibilityLabel("Create Matrix account")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Connected section

    @ViewBuilder
    private func connectedSection(_ creds: MatrixCredentials) -> some View {
        Section("Identity") {
            LabeledContent("Matrix ID", value: creds.userId)
                .stableXrayId("settings.federation.matrixIdLabel")
            LabeledContent("Device ID", value: creds.deviceId)
                .stableXrayId("settings.federation.deviceIdLabel")
            LabeledContent("Homeserver", value: creds.homeserver.host ?? creds.homeserver.absoluteString)
                .stableXrayId("settings.federation.homeserverLabel")
        }

        Section("Sync") {
            LabeledContent("Status", value: syncStatus)
                .stableXrayId("settings.federation.syncStatusLabel")
            if let date = lastSyncDate {
                LabeledContent("Last Sync", value: date.formatted(.relative(presentation: .named)))
                    .stableXrayId("settings.federation.lastSyncLabel")
            }
            Button("Reset Sync Token") { resetSync() }
                .stableXrayId("settings.federation.resetSyncButton")
                .accessibilityLabel("Reset Matrix sync token")
        }

        Section {
            Button("Share Profile") { showShareProfile = true }
                .stableXrayId("settings.federation.shareProfileButton")
                .accessibilityLabel("Share your Matrix profile as QR code")

            Button("Sign Out", role: .destructive) { signOut() }
                .stableXrayId("settings.federation.signOutButton")
                .accessibilityLabel("Sign out of Matrix")
        }
    }

    // MARK: - Actions

    private func loadCurrentCredentials() {
        let store = MatrixKeychainStore(instanceName: instanceName)
        credentials = try? store.loadCredentials()
    }

    private func signIn() async {
        guard let url = URL(string: homeserverText) else {
            errorMessage = "Invalid homeserver URL"; return
        }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let client = MatrixClient(homeserver: url)
            let creds = try await client.login(username: username, password: password)
            let store = MatrixKeychainStore(instanceName: instanceName)
            try store.saveCredentials(creds)
            credentials = creds
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func register() async {
        guard let url = URL(string: homeserverText) else {
            errorMessage = "Invalid homeserver URL"; return
        }
        isRegistering = true
        errorMessage = nil
        defer { isRegistering = false }
        do {
            let client = MatrixClient(homeserver: url)
            let creds = try await client.register(username: username, password: password)
            let store = MatrixKeychainStore(instanceName: instanceName)
            try store.saveCredentials(creds)
            credentials = creds
            password = ""
        } catch MatrixError.httpError(let code, _, _) where code == 403 {
            errorMessage = "Registration is disabled on this server. Create an account at app.element.io, then sign in here."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetSync() {
        let store = MatrixKeychainStore(instanceName: instanceName)
        store.deleteSyncToken()
        syncStatus = "Sync token cleared"
    }

    private func signOut() {
        let store = MatrixKeychainStore(instanceName: instanceName)
        store.deleteCredentials()
        store.deleteSyncToken()
        credentials = nil
    }
}
