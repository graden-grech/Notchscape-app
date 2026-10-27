import AppKit
import Auth0
import Combine
import CryptoKit
import Defaults
import JWTDecode
import SimpleKeychain

struct NotchAccountConfiguration {
    let domain: String
    let clientID: String
    let audience: String
    let settingsURL: URL?

    static var bundled: Self? {
        guard AccountFeaturePolicy.enabled,
              let domain = Bundle.main.object(forInfoDictionaryKey: "NotchAccountDomain") as? String,
              !domain.isEmpty, !domain.contains("/"),
              let clientID = Bundle.main.object(forInfoDictionaryKey: "NotchAccountClientID") as? String,
              !clientID.isEmpty,
              let audience = Bundle.main.object(forInfoDictionaryKey: "NotchAccountAudience") as? String,
              !audience.isEmpty else { return nil }
        let raw = Bundle.main.object(forInfoDictionaryKey: "NotchAccountSettingsURL") as? String ?? ""
        let url = URL(string: raw)
        let safeURL = url.flatMap { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil &&
            $0.query == nil && $0.fragment == nil ? $0 : nil }
        return Self(domain: domain, clientID: clientID, audience: audience, settingsURL: safeURL)
    }
}

@MainActor final class AccountManager: ObservableObject {
    static let shared = AccountManager()
    @Published private(set) var user: UserProfile?
    @Published private(set) var busy = false
    @Published private(set) var signingIn = false
    @Published private(set) var message: String?
    @Published private(set) var automaticSync = false
    @Published private(set) var hasSyncBaseline = false
    let configuration = NotchAccountConfiguration.bundled
    private var credentials: CredentialsManager?
    private var signInAttempt: AccountSignInAttempt<Credentials>?
    private var observer: NSObjectProtocol?
    private var pendingSync: Task<Void, Never>?
    private var sessionGeneration = UUID()
    private var applying = false
    private var baseline: AccountSettingsDocument?
    private var revision = 0

    var signInAvailable: Bool { configuration != nil }
    var syncAvailable: Bool { configuration?.settingsURL != nil }
    // These are presentation hints, not proof of enrollment or authorization.
    var signInProvider: AccountSignInProvider { AccountSignInProvider(subject: user?.sub ?? "") }
    var hasEmailPasskeyAccount: Bool { user != nil && signInProvider == .email }

    private init() {
        if let config = configuration {
            let key = SHA256.hash(data: Data("\(config.domain)|\(config.clientID)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            credentials = CredentialsManager(authentication: Auth0.authentication(clientId: config.clientID, domain: config.domain),
                                             storeKey: "notch-account-\(key)",
                                             storage: AccountCredentialStorage(base: SimpleKeychain(
                                                service: "theboringteam.boringnotch.accounts.\(key)",
                                                accessibility: .whenUnlockedThisDeviceOnly)))
            // Reading the cached profile is only for display, never authorization.
            user = try? credentials?.userProfile()
        }
        // Keep existing Keychain entries untouched during the public release
        // hold. No preference observation or account work runs while disabled.
        guard configuration != nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.preferencesChanged() }
        }
    }

    func signIn(createAccount: Bool = false, apple: Bool = false, preferPasskey: Bool = false) async {
        guard !busy, user == nil else { return }
        let flow: AccountSignInFlow = createAccount ? .signUp : (preferPasskey ? .passkey : .standard)
        await authenticate(flow: flow, apple: apple)
    }

    func checkPasskeySignIn() async {
        guard !busy, let user, hasEmailPasskeyAccount else { return }
        await authenticate(flow: .passkeyCheck, expectedSubject: user.sub)
    }

    private func authenticate(flow: AccountSignInFlow, apple: Bool = false, expectedSubject: String? = nil) async {
        guard let config = configuration, let credentials else { message = AccountSettingsError.notConfigured.localizedDescription; return }
        busy = true; signingIn = true; message = nil
        defer { busy = false; signingIn = false; signInAttempt = nil }
        do {
            // Auth0 owns the password/passkey form. PKCE, state, nonce and ID-token
            // validation are handled by its maintained SDK, not a home-grown flow.
            var login = Auth0.webAuth(clientId: config.clientID, domain: config.domain)
                .scope("openid profile email offline_access read:settings write:settings")
                .audience(config.audience)
                .useEphemeralSession()
            if !flow.parameters.isEmpty { login = login.parameters(flow.parameters) }
            if let connection = flow.connection { login = login.connection(connection) }
            if apple { login = login.connection("apple") }
            if let window = NSApp.keyWindow { login = login.presentationWindow(window) }
            let attempt = AccountSignInAttempt<Credentials> { WebAuthentication.cancel() }
            signInAttempt = attempt
            let result = try await attempt.run { completion in
                login.start { completion($0.mapError { $0 as any Error }) }
            }
            // Web Auth validates this ID token before returning. Decode only
            // that validated result, and compare subjects before changing storage.
            let claims = try decode(jwt: result.idToken)
            guard let profile = UserProfile(json: claims.body) else { throw AccountSettingsError.signedOut }
            if let expectedSubject,
               !AccountSignInFlow.matchesExistingAccount(expected: expectedSubject, returned: profile.sub) {
                throw AccountSignInError.differentAccount
            }
            // A new account must never inherit a different account's sync consent.
            // Reauthentication keeps the existing session if the browser fails.
            if expectedSubject == nil { try credentials.clear() }
            try credentials.store(credentials: result)
            user = profile
            if expectedSubject != nil {
                message = "Account sign-in confirmed. Your local settings and sync choice were kept. If you selected a passkey in the browser, you can use it again without your password."
            } else {
                sessionGeneration = UUID()
                baseline = nil; revision = 0; automaticSync = false; hasSyncBaseline = false
                message = "Signed in. Choose whether to save this Mac’s appearance or restore your cloud copy."
            }
        } catch let error as AccountSignInError {
            message = error.localizedDescription
        } catch is CancellationError {
            message = AccountSignInError.cancelled.localizedDescription
        } catch WebAuthError.userCancelled {
            message = "Sign-in was canceled. You can try again whenever you’re ready."
        } catch WebAuthError.idTokenValidationFailed {
            message = "The sign-in response couldn’t be verified. Nothing was saved; please try again."
        } catch WebAuthError.codeExchangeFailed {
            message = "The secure sign-in exchange couldn’t be completed. Please try again."
        } catch let error as SimpleKeychainError {
            // An OSStatus is safe diagnostic information; never print tokens or
            // OAuth response bodies when handling credential failures.
            NSLog("Notchscape: account Keychain operation failed (status %d)", error.status)
            message = AccountSettingsError.keychain.localizedDescription
        } catch {
            // Do not log OAuth responses, tokens, profile contents or raw errors.
            message = "Sign-in wasn’t completed. Your local settings are unchanged."
        }
    }

    func cancelSignIn() { signInAttempt?.cancel() }

    func continueWithoutAccount() {
        cancelSignIn()
        pendingSync?.cancel(); pendingSync = nil
        automaticSync = false
        // Guest use never clears an existing login or changes cloud settings.
    }

    func signOut() {
        guard !busy else { return }
        do { try credentials?.clear() }
        catch { message = AccountSettingsError.keychain.localizedDescription; return }
        sessionGeneration = UUID()
        pendingSync?.cancel(); pendingSync = nil
        user = nil; baseline = nil; revision = 0; automaticSync = false; hasSyncBaseline = false
        message = "Signed out on this Mac. Local settings are unchanged."
    }

    func refreshAccountStatus() async { await operation {
        guard self.user != nil, let credentials = self.credentials else { throw AccountSettingsError.signedOut }
        // The SDK renews and persists credentials. This cached profile is for
        // display; the settings service independently validates access tokens.
        _ = try await credentials.renew()
        self.user = try credentials.userProfile()
        self.message = self.user?.emailVerified == true ? "Email verified. Your account is ready to sync." :
            "Please follow the verification link in your email, then refresh again."
    }}

    func setAutomaticSync(_ enabled: Bool) {
        guard hasSyncBaseline, user != nil else { return }
        automaticSync = enabled
        if enabled { preferencesChanged() } else { pendingSync?.cancel(); pendingSync = nil }
    }

    /// Both first-time choices are explicit. No cloud copy is silently applied on login.
    func saveThisMac() async { await operation {
        let cloud: CloudSettings = try await self.request("GET")
        let snapshot = try self.capture().validated()
        let result: CloudSettings = try await self.request("PUT", document: snapshot, expected: cloud.revision)
        self.acceptBaseline(snapshot, revision: result.revision)
        self.message = "This Mac’s appearance and layout are saved."
    }}

    func restoreCloud() async { await operation {
        let result: CloudSettings = try await self.request("GET")
        guard let document = result.settings else { self.message = "No cloud settings yet. Save this Mac first."; return }
        try self.apply(document)
        self.acceptBaseline(document, revision: result.revision)
        self.message = "Cloud appearance and layout restored. HUD permissions and private data stayed local."
    }}

    func deleteCloudSettings() async { await operation {
        let cloud: CloudSettings = try await self.request("GET")
        let _: CloudSettings = try await self.request("DELETE", expected: cloud.revision)
        self.automaticSync = false; self.baseline = nil; self.hasSyncBaseline = false; self.revision = 0
        self.message = "Cloud settings deleted. Your account and local settings were not deleted."
    }}

    private func operation(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do { try await work() }
        catch let error as AccountSettingsError { message = error.localizedDescription }
        catch { message = "Couldn’t reach the settings service. Your local settings are unchanged." }
    }

    private func preferencesChanged() {
        guard automaticSync, !applying, let baseline, let current = try? capture(), current != baseline else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, !Task.isCancelled, self.automaticSync else { return }
            await self.syncIfSafe()
        }
    }

    func syncIfSafe() async { await operation {
        guard self.automaticSync, let baseline = self.baseline else { return }
        let cloud: CloudSettings = try await self.request("GET")
        // A user may change a preference while the request is in flight. Compare
        // the current copy, not a pre-request snapshot, before applying cloud data.
        let local = try self.capture()
        if cloud.revision != self.revision {
            guard local == baseline, let document = cloud.settings else {
                self.automaticSync = false
                throw AccountSettingsError.conflict
            }
            try self.apply(document)
            self.acceptBaseline(document, revision: cloud.revision)
        } else if local != baseline {
            let result: CloudSettings = try await self.request("PUT", document: local, expected: self.revision)
            self.acceptBaseline(local, revision: result.revision)
        }
        self.message = "Settings are up to date."
    }}

    private func acceptBaseline(_ document: AccountSettingsDocument, revision: Int) {
        self.baseline = document; self.revision = revision; hasSyncBaseline = true
        // If another local edit arrived during a network call, keep it queued.
        preferencesChanged()
    }

    private struct CloudSettings: Decodable {
        var revision: Int
        var settings: AccountSettingsDocument?
    }

    private func request(_ method: String, document: AccountSettingsDocument? = nil, expected: Int? = nil) async throws -> CloudSettings {
        guard user != nil, let credentials else { throw AccountSettingsError.signedOut }
        guard let config = configuration, let url = config.settingsURL else { throw AccountSettingsError.cloudNotConfigured }
        let generation = sessionGeneration
        let auth = try await credentials.credentials(minTTL: 60)
        var request = URLRequest(url: url.appendingPathComponent("v1/me/settings"))
        request.httpMethod = method; request.timeoutInterval = 20
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let expected { request.setValue("\"\(expected)\"", forHTTPHeaderField: "If-Match") }
        if let document {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try document.encoded()
        }
        // An ephemeral session avoids cookie/cache persistence. The delegate
        // refuses redirects so a bearer token never follows a changed endpoint.
        let network = URLSessionConfiguration.ephemeral
        network.timeoutIntervalForRequest = 20
        network.timeoutIntervalForResource = 30
        network.httpShouldSetCookies = false
        let session = URLSession(configuration: network, delegate: NoAccountRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard generation == sessionGeneration else { throw AccountSettingsError.signedOut }
        guard let http = response as? HTTPURLResponse else { throw AccountSettingsError.rejected }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 16_384 else { throw AccountSettingsError.invalidDocument }
            data.append(byte)
        }
        guard generation == sessionGeneration else { throw AccountSettingsError.signedOut }
        guard http.statusCode == 200 else {
            if http.statusCode == 409 { automaticSync = false; throw AccountSettingsError.conflict }
            if http.statusCode == 401 { automaticSync = false; throw AccountSettingsError.signedOut }
            if http.statusCode == 403,
               (try? JSONDecoder().decode([String: String].self, from: data))?["error"] == "verify_email" {
                throw AccountSettingsError.verifyEmail
            }
            throw AccountSettingsError.rejected
        }
        let result = try JSONDecoder().decode(CloudSettings.self, from: data)
        guard result.revision >= 0, result.revision <= 10_000_000_000,
              (result.revision == 0) == (result.settings == nil) else { throw AccountSettingsError.invalidDocument }
        _ = try result.settings?.validated()
        return result
    }

    private func capture() throws -> AccountSettingsDocument {
        var values: [String: AccountSettingValue] = [:]
        func add(_ key: Defaults.Key<Bool>) { values[key.name] = .bool(Defaults[key]) }
        [Defaults.Keys.appIconFollowsTheme, .automaticSeasonalThemes, .seasonalHalloween, .seasonalChristmas,
         .weatherOnLiveTab, .tileShowLabels, .playerColorTinting, .useMusicVisualizer, .showShuffleAndRepeat,
         .coloredSpectrogram, .showBatteryIndicator, .showBatteryPercentage, .showPowerStatusIcons,
         .hideBatteryWhenAbsent, .hideCompletedReminders].forEach(add)
        values["appTheme"] = .string(Defaults[.appTheme].rawValue)
        values["appIconVariant"] = .string(Defaults[.appIconVariant].rawValue)
        values["seasonHemisphere"] = .string(Defaults[.seasonHemisphere].rawValue)
        values["batteryPresentation"] = .string(Defaults[.batteryPresentation].rawValue)
        values["batteryIndicatorDisplay"] = .string(Defaults[.batteryIndicatorDisplay].rawValue)
        values["homeWidgetOrder"] = .strings(Defaults[.homeWidgetOrder].map(\.rawValue))
        values["hiddenHomeWidgets"] = .strings(Defaults[.hiddenHomeWidgets].map(\.rawValue).sorted())
        return try AccountSettingsDocument(values: values).validated()
    }

    private func apply(_ document: AccountSettingsDocument) throws {
        _ = try document.validated() // Validate everything before applying anything.
        applying = true
        defer { applying = false }
        func applyBool(_ key: Defaults.Key<Bool>) {
            if case .bool(let value) = document.values[key.name] { Defaults[key] = value }
        }
        [Defaults.Keys.appIconFollowsTheme, .automaticSeasonalThemes, .seasonalHalloween, .seasonalChristmas,
         .weatherOnLiveTab, .tileShowLabels, .playerColorTinting, .useMusicVisualizer, .showShuffleAndRepeat,
         .coloredSpectrogram, .showBatteryIndicator, .showBatteryPercentage, .showPowerStatusIcons,
         .hideBatteryWhenAbsent, .hideCompletedReminders].forEach(applyBool)
        if case .string(let raw) = document.values["appTheme"], let value = AppTheme(rawValue: raw) {
            Defaults[.appTheme] = value
            if let variant = value.whiteHouseVariant { Defaults[.whiteHousePreferredVariant] = variant }
        }
        if case .string(let raw) = document.values["appIconVariant"], let value = AppIconVariant(rawValue: raw) { Defaults[.appIconVariant] = value }
        if case .string(let raw) = document.values["seasonHemisphere"], let value = SeasonHemisphere(rawValue: raw) { Defaults[.seasonHemisphere] = value }
        if case .string(let raw) = document.values["batteryPresentation"], let value = BatteryPresentationStyle(rawValue: raw) { Defaults[.batteryPresentation] = value }
        if case .string(let raw) = document.values["batteryIndicatorDisplay"], let value = BatteryIndicatorDisplay(rawValue: raw) { Defaults[.batteryIndicatorDisplay] = value }
        if case .strings(let raw) = document.values["homeWidgetOrder"] { Defaults[.homeWidgetOrder] = raw.compactMap(HomeWidget.init(rawValue:)) }
        if case .strings(let raw) = document.values["hiddenHomeWidgets"] { Defaults[.hiddenHomeWidgets] = Set(raw.compactMap(HomeWidget.init(rawValue:))) }
    }
}

private final class NoAccountRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
