import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject private var account = AccountManager.shared
    @State private var confirmRestore = false
    @State private var confirmUpload = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                AccountPreviewNotice()
            }
            Section("Your Account") {
                AccountSignInControls()
                if let user = account.user {
                    LabeledContent("Email", value: user.email ?? "Not shared")
                    Label(user.emailVerified == true ? "Email verified" : "Verify your email before syncing",
                          systemImage: user.emailVerified == true ? "checkmark.seal" : "envelope.badge")
                        .foregroundStyle(user.emailVerified == true ? Color.secondary : Color.orange)
                    Button("Refresh Account Status") { Task { await account.refreshAccountStatus() } }
                        .disabled(account.busy)
                    Button("Sign Out on This Mac") { account.signOut() }
                        .disabled(account.busy)
                }
            }
            if account.user != nil {
                Section("Sign-in & Recovery") {
                    if account.hasEmailPasskeyAccount {
                        Label("Use a passkey instead of your password", systemImage: "key.fill")
                        Text("Save a passkey in Apple Passwords or your password manager. You can then sign in without a password-reset email.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Set Up or Check a Passkey…") { Task { await account.checkPasskeySignIn() } }
                            .disabled(account.busy)
                        Text("Your browser will open. Choose Continue with a passkey, or sign in with your password and choose Create a passkey if offered. Keep a backup you can access from another device; losing every sign-in method may lock you out.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        switch account.signInProvider {
                        case .google:
                            Label("You sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                            Text("Keep using Continue with Google. There is no separate Notchscape password to remember. Your Google account’s security settings have not been changed.")
                                .font(.callout).foregroundStyle(.secondary)
                        case .apple:
                            Label("You sign in with Apple", systemImage: "apple.logo")
                            Text("Keep using Continue with Apple. There is no separate Notchscape password to remember. Your Apple Account’s security settings have not been changed.")
                                .font(.callout).foregroundStyle(.secondary)
                        case .email, .other:
                            Label("Your existing sign-in is unchanged", systemImage: "person.crop.circle.badge.checkmark")
                            Text("Keep using the same sign-in service. It handles your password and recovery; Notchscape does not change its security settings.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Save This Mac’s Settings…") { confirmUpload = true }
                    Button("Restore Cloud Settings…") { confirmRestore = true }
                    Toggle("Automatically save changes on this Mac", isOn: Binding(
                        get: { account.automaticSync }, set: { account.setAutomaticSync($0) }))
                        .disabled(!account.hasSyncBaseline)
                    Button("Check for Changes") { Task { await account.syncIfSafe() } }
                        .disabled(!account.automaticSync)
                } header: { Text("Appearance & Layout Sync") }
                footer: {
                    Text(account.syncAvailable ?
                         "Choose a copy before turning on sync. The cloud copy is checked when this page opens or a local choice changes. If both Macs change, you choose which to keep. Sign-out and app restart pause automatic sync; local settings always work offline." :
                         "The cloud settings service is still being configured. Sign-in and local settings are separate; no settings have been uploaded.")
                }
                .disabled(account.busy || !account.syncAvailable)
                Section {
                    Button("Delete Cloud Settings…", role: .destructive) { confirmDelete = true }
                        .disabled(account.busy || !account.syncAvailable)
                } header: { Text("Saved Cloud Data") }
                footer: { Text("Deletes only your synced appearance and layout, not your login account or this Mac’s settings.") }
            }
            Section("What stays on your Mac") {
                Label("HUD permissions and display setup", systemImage: "macwindow")
                Label("AI conversations, calendar events and files", systemImage: "lock.shield")
                Label("Location, shortcuts and credentials", systemImage: "hand.raised")
                Text("Only supported appearance, Home layout, media display and battery display choices are synced. No app password is stored by Notchscape; session tokens are kept in macOS Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = account.message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Account")
        .task { await account.syncIfSafe() }
        .confirmationDialog("Replace your cloud copy with this Mac’s settings?", isPresented: $confirmUpload) {
            Button("Save This Mac’s Settings") { Task { await account.saveThisMac() } }
        } message: { Text("This affects only supported appearance and layout choices. Other Macs can restore this copy.") }
        .confirmationDialog("Restore your cloud appearance and layout?", isPresented: $confirmRestore) {
            Button("Restore Cloud Settings") { Task { await account.restoreCloud() } }
        } message: { Text("This replaces the supported choices on this Mac. HUD permissions and private data stay unchanged.") }
        .confirmationDialog("Delete your saved cloud settings?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Cloud Settings", role: .destructive) { Task { await account.deleteCloudSettings() } }
        } message: { Text("This cannot be undone. Your account and this Mac’s local settings will remain.") }
    }
}

private struct AccountPreviewNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Account Preview", systemImage: "flask")
                .font(.headline)
            Text("Sign-in and settings sync are still being tested. Passkey setup and recovery are not fully verified. You can keep using the app without an account.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AccountSignInControls: View {
    @ObservedObject private var account = AccountManager.shared
    private var appleEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "NotchAppleSignInEnabled") as? Bool == true }

    var body: some View {
        if account.user == nil {
            VStack(alignment: .leading, spacing: 12) {
                if appleEnabled {
                    Button { Task { await account.signIn(apple: true) } } label: {
                        Label("Continue with Apple", systemImage: "apple.logo")
                    }
                }
                Button { Task { await account.signIn(preferPasskey: true) } } label: {
                    Label("Sign In with a Passkey", systemImage: "key.fill")
                }
                    .buttonStyle(.borderedProminent)
                Button("Sign In Another Way") { Task { await account.signIn() } }
                    .buttonStyle(.bordered)
                Button("Create an Account") { Task { await account.signIn(createAccount: true) } }
                    .buttonStyle(.bordered)
                Text("Already saved a passkey? Choose Continue with a passkey in your browser. For Google or a password, choose Sign In Another Way. New here? Create an Account, or continue without one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(account.busy || !account.signInAvailable)
        } else {
            Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
        }
        if account.signingIn {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Finish sign-in in your browser").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Cancel Sign-In") { account.cancelSignIn() }.buttonStyle(.bordered)
            }
        } else if account.busy { ProgressView().controlSize(.small) }
    }
}

struct AccountOnboardingView: View {
    @ObservedObject private var account = AccountManager.shared
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "person.crop.circle").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("Make it yours").font(.largeTitle.weight(.semibold))
            Text("Create an optional account to save your appearance and layout. You can also use Notchscape without signing in.")
                .foregroundStyle(.secondary)
            AccountPreviewNotice()
            AccountSignInControls()
            if let message = account.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Continue Without an Account") {
                account.continueWithoutAccount()
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            if account.user != nil {
                Button("Continue with This Account", action: onContinue)
                    .disabled(account.busy)
            }
            Text("Camera, calendar, AI activity and HUD access stay on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(30)
    }
}
