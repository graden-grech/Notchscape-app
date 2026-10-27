import Foundation

/// A display hint only. Never use the subject prefix to grant permissions,
/// establish passkey enrollment, or link identities.
enum AccountSignInProvider {
    case email, google, apple, other

    init(subject: String) {
        let parts = subject.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else { self = .other; return }
        switch parts[0] {
        case "auth0": self = .email
        case "google-oauth2": self = .google
        case "apple": self = .apple
        default: self = .other
        }
    }
}

/// Only documented Universal Login parameters. A passkey route still lets the
/// person choose the passkey in Auth0's hosted UI; it never synthesizes WebAuthn.
enum AccountSignInFlow {
    case standard, signUp, passkey, passkeyCheck

    var connection: String? {
        switch self {
        case .passkey, .passkeyCheck: "Username-Password-Authentication"
        case .standard, .signUp: nil
        }
    }

    var parameters: [String: String] {
        switch self {
        case .standard: [:]
        case .signUp: ["screen_hint": "signup", "prompt": "login"]
        case .passkey: ["prompt": "login"]
        case .passkeyCheck: ["prompt": "login", "max_age": "0"]
        }
    }

    static func matchesExistingAccount(expected: String, returned: String) -> Bool {
        !expected.isEmpty && expected == returned
    }
}

enum AccountSignInError: LocalizedError {
    case cancelled, timedOut, alreadyStarted, differentAccount

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was canceled. Your local settings are unchanged."
        case .timedOut: "The sign-in window expired. Please try again; your local settings are unchanged."
        case .alreadyStarted: "A sign-in attempt is already in progress."
        case .differentAccount: "That sign-in belongs to a different account. Your current account, saved settings and sync choice were kept. Accounts are never linked just because their email addresses match."
        }
    }
}

/// A bounded, one-shot bridge around the SDK callback. In particular, a browser
/// that disappears without a callback cannot leave onboarding disabled forever.
/// A late callback after cancellation must never store credentials.
@MainActor final class AccountSignInAttempt<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var started = false
    private let cancelBrowser: @MainActor () -> Void

    init(cancelBrowser: @escaping @MainActor () -> Void) {
        self.cancelBrowser = cancelBrowser
    }

    func run(timeout: Duration = .seconds(600),
             start: (@escaping @MainActor @Sendable (Result<Value, any Error>) -> Void) -> Void) async throws -> Value {
        guard !started else { throw AccountSignInError.alreadyStarted }
        started = true
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.cancel(reason: .timedOut)
                }
                start { [weak self] result in _ = self?.finish(result) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel(reason: AccountSignInError = .cancelled) {
        guard finish(.failure(reason)) else { return }
        cancelBrowser()
    }

    @discardableResult
    private func finish(_ result: Result<Value, any Error>) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        continuation.resume(with: result)
        return true
    }
}
