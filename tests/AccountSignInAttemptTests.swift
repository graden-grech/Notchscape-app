import Foundation

@main struct AccountSignInAttemptTests {
    @MainActor static func main() async throws {
        precondition(AccountSignInProvider(subject: "auth0|alice") == .email)
        precondition(AccountSignInProvider(subject: "google-oauth2|alice") == .google)
        precondition(AccountSignInProvider(subject: "apple|alice") == .apple)
        for unknown in ["", "auth0|", "auth0", "google-oauth2|", "google-oauth2-fake|alice", "AUTH0|alice", "other|alice"] {
            precondition(AccountSignInProvider(subject: unknown) == .other)
        }
        precondition(AccountSignInFlow.standard.connection == nil)
        precondition(AccountSignInFlow.standard.parameters.isEmpty)
        precondition(AccountSignInFlow.signUp.parameters == ["screen_hint": "signup", "prompt": "login"])
        precondition(AccountSignInFlow.signUp.connection == nil) // Existing signup options remain available.
        precondition(AccountSignInFlow.passkey.connection == "Username-Password-Authentication")
        precondition(AccountSignInFlow.passkey.parameters == ["prompt": "login"])
        precondition(AccountSignInFlow.passkeyCheck.connection == AccountSignInFlow.passkey.connection)
        precondition(AccountSignInFlow.passkeyCheck.parameters == ["prompt": "login", "max_age": "0"])
        precondition(AccountSignInFlow.matchesExistingAccount(expected: "auth0|alice", returned: "auth0|alice"))
        for other in ["auth0|bob", "google-oauth2|alice", "AUTH0|alice", "", "auth0|alice "] {
            precondition(!AccountSignInFlow.matchesExistingAccount(expected: "auth0|alice", returned: other))
        }
        precondition(!AccountSignInFlow.matchesExistingAccount(expected: "", returned: ""))
        var cancellations = 0
        let success = AccountSignInAttempt<String> { cancellations += 1 }
        let result = try await success.run { callback in
            callback(.success("synthetic"))
            callback(.failure(AccountSignInError.cancelled)) // Duplicate callback is ignored.
        }
        precondition(result == "synthetic" && cancellations == 0)
        success.cancel()
        precondition(cancellations == 0)

        let cancelled = AccountSignInAttempt<String> { cancellations += 1 }
        do {
            _ = try await cancelled.run { callback in
                cancelled.cancel()
                callback(.success("late synthetic result"))
            }
            preconditionFailure("Cancellation must win over a late success")
        } catch AccountSignInError.cancelled { }
        precondition(cancellations == 1)
        cancelled.cancel()
        precondition(cancellations == 1)

        let timeout = AccountSignInAttempt<String> { cancellations += 1 }
        do {
            _ = try await timeout.run(timeout: .milliseconds(10)) { _ in }
            preconditionFailure("Missing browser callback must time out")
        } catch AccountSignInError.timedOut { }
        precondition(cancellations == 2)

        let taskAttempt = AccountSignInAttempt<String> { cancellations += 1 }
        let task = Task { @MainActor in try await taskAttempt.run { _ in } }
        await Task.yield()
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancelled task must not succeed") }
        catch is CancellationError { }
        catch AccountSignInError.cancelled { }
        print("Passed sign-in checks: provider presentation, passkey routing, exact-account guard, success, duplicate and late callbacks, cancellation and timeout")
    }
}
