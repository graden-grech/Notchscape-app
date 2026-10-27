# Optional accounts and cloud settings

## Release hold (2026-10-17)

The owner requested account-free use and asked not to publish account features
yet. `NotchAccountsEnabled` is explicitly false in the signed app configuration.
Settings omits the Account page and onboarding goes directly from **Continue
Without an Account** to the normal optional-permission steps. Missing or malformed
feature flags fail closed. An old/restored Account step is skipped as well.

The disabled configuration does not initialize account credential storage,
observe preferences for cloud saves, start sign-in, or run account sync. Existing
Keychain credentials and saved cloud settings are not erased or signed out.
When accounts are intentionally enabled for future development, the onboarding
skip action stays available even during a pending sign-in: it cancels that
attempt and pauses automatic saves without deleting an existing login.

The signed build entry point and CI run `verify_public_feature_flags.py` to
reject any build whose flag is not explicitly false. Account code remains in
the repository for future work; this is a release/feature hold, not deletion of
source history, identities, Auth0/Cloudflare services or the owner's settings.
The previously published optional 2.9.0-beta.1 account preview was returned to
draft rather than deleting its assets or tag. Stable 2.8.3 and its update feed
remain unchanged. Do not publish or re-enable accounts without a new request.

The signed local 2.9.0-beta.2/build 286 account-free build passed the source and
built-bundle release gates, 71 account-policy checks, sign-in cancellation tests,
107 customization checks and 46 workflow/helper tests. The running Settings
sidebar was visually inspected and has no Account entry. Twelve stored protected
preferences, including first-launch state, are unchanged. The enabled HUD tap
passed after cold launch, Restart HUD and closing Settings. Fresh-device
onboarding, a new real volume-key test and a Sparkle installation were not
repeated. The disabled configuration does not load or clear saved credentials.
The withdrawn preview's unauthenticated ZIP download returns HTTP 404; previously
downloaded copies cannot be recalled. No new app release was published.

Accounts do not replace macOS accounts, confer operating-system privileges, or
grant HUD access. The app remains usable without signing in. This feature uses
Auth0 Universal Login (its maintained Swift SDK, authorization code + PKCE) and
a separate, small Cloudflare Worker/D1 settings service. There are no app-owned
password forms, password database, embedded client secrets, or public admin API.

## Owner/admin panel

Use the **User Management → Users** section of the Auth0 tenant dashboard:

https://manage.auth0.com/dashboard/us/dev-f31y4vcdyhkcfqf0/

This dashboard manages identities, verified email status, blocking/deletion and
authentication logs. Protect the owner account with MFA. Dashboard membership is
separate from app user accounts. Never add an admin role based on display names,
email strings, editable metadata, or the first person to register. The public app
does not receive Auth0 Management API credentials. This is a managed admin panel,
not a custom all-data or remote-control dashboard.

Passwords and private passkey keys cannot be viewed. Calendar contents, files,
AI transcripts and exact location are not uploaded to this settings service.
Auth0 and Cloudflare have their own service-level authentication/access records;
do not describe the feature as collecting no personal information at all.

## Public configuration

`Notchscape/Info.plist` contains the tenant domain, native application's public
client ID, API audience, HTTPS settings endpoint and the Apple-connection readiness
flag. These are identifiers, not secrets. Credentials are stored by Auth0's
CredentialsManager in macOS Keychain, namespaced to this client and tenant.
Do not add a client secret to the Mac app, this repository, or GitHub Actions.

Custom-scheme callbacks are exact-allowlisted to the existing bundle ID. The SDK
handles PKCE, state, nonce and ID-token validation. The app requests an ephemeral
browser session; support depends on the system browser. A visible Cancel Sign-In
control and a ten-minute deadline recover from abandoned browser windows. Late
callbacks after cancellation are ignored and cannot save a session. The browser
is anchored to the current app window when one is available. Local
sign-out clears this Mac's stored credentials without signing the user out of
their Apple Account or deleting their cloud settings.

## Auth0 setup requirements

- Native application: **NotSoboringNotch** (no client authentication/secret).
- Callback/logout URL:
  `theboringteam.boringnotch://dev-f31y4vcdyhkcfqf0.us.auth0.com/macos/theboringteam.boringnotch/callback`.
- Database connection: email/password; no required username; brute-force protection.
- Passkeys: enable passkey button/autofill and progressive enrollment; use
  Identifier First with New Universal Login. Keep passwords/recovery available.
- Refresh tokens: enable rotation in the native application and offline access
  for the API. Tokens must have bounded idle and absolute lifetimes.
- API audience: `https://notsoboringnotch.app/settings`, RS256, five-minute access
  tokens, explicit user consent, user-delegated access only for the native app.
- API scopes: `read:settings`, `write:settings`. No machine-to-machine or anonymous
  application grants are needed. Do not enable a user's ability to administer
  identities merely to let them sync settings.
- Deploy `services/accounts/auth0/post-login.js` as a Login/Post Login Action and
  add it to the tenant Login trigger. The Worker fails closed if its verified-email
  claim is missing. After verifying email, sign in again to obtain a fresh claim.
- Sign in with Apple needs the owner's Apple Developer Services ID, verified
  return URL, key and connection configuration in Auth0. Keep
  `NotchAppleSignInEnabled` false until that configuration and a real login pass.
  Do **not** change the installed app's signing identity/bundle ID to improvise
  this setup: follow `HUD_RELEASE_CHECKS.md`.
- Complete production email sender/branding, recovery, account-linking and owner
  MFA tests before public rollout. Never auto-link identities by matching emails;
  linking different login methods must prove control of both accounts.

## Sync contract and privacy

`AccountSettingsPolicy.swift` and `services/accounts/src/policy.js` implement the
same small, versioned allowlist. It covers theme/icon, seasonal preferences, Home
widget arrangement and selected media/battery display options. It does not yet
sync every preference, including the custom accent-color archive.

No permission, startup item, display ID/geometry, executable shortcut, Shelf file,
calendar identifier/content, location, AI history, arbitrary URL, updater setting,
or credential can be applied from cloud settings. Unknown keys, unsupported
versions, type confusion, invalid enums, duplicate widgets and oversized payloads
are rejected before application. String blacklists are not a security boundary.
There are no app usernames to turn `admin` or SQL-looking input into authority.

The Worker verifies signature, fixed issuer/audience/RS256, expiry, required claims,
the native client ID, scope and signed verified-email claim before any DB request.
Ownership always comes from the verified token subject, never a request body or
query parameter. SQL uses bound parameters. Responses are not cached and there
are no cookie sessions or arbitrary-origin CORS. Requests are rate-limited by
Cloudflare IP and authenticated subject. Tokens and settings are not logged by
application code; Worker observability is disabled by default.

On first login the user must choose **Save This Mac** or **Restore Cloud**. Optional
automatic saves are debounced for 10 seconds, check for conflicting changes and
use revision preconditions. Incoming changes are checked when the Account page
opens or an automatic save runs. Auto-sync is intentionally paused after app
restart or sign-out; no other account inherits consent. The user can explicitly
delete their cloud copy, independently of local settings or their identity.

An owner blocking an identity prevents future login/token refresh; an already
issued access token can remain valid until its short expiry. Account deletion in
Auth0 does not automatically delete its D1 row: clear the user's settings first or
perform an authorized, audited subject-specific deletion. Do not claim automatic
cross-service deletion or end-to-end encryption. Add a signed deletion webhook or
operator workflow before exposing self-service account deletion publicly.

## Service development and deployment

From `services/accounts`:

```sh
npm ci
npm test
npm run check
```

Authenticated deployment is separate from a GitHub/app release. Wrangler uses
encrypted local credentials with its key stored in macOS Keychain. It needs only
account/user read, Workers scripts write and D1 write permissions. Never broaden
these to unrelated email, DNS, AI, network or billing settings to silence CLI warnings.

```sh
npx wrangler d1 migrations apply notsoboringnotch-settings --remote
npx wrangler deploy
```

The configured D1 database and Worker are exclusively for this feature. Do not
reset or delete a database to test an update. Unit tests use an in-memory SQLite
adapter and locally generated test signing keys, not customer accounts.

Before public rollout verify actual signup/email verification, password reset,
passkey enrollment/recovery, Sign in with Apple, token expiry/refresh, sign-out,
account switching and two-Mac conflict behavior. A successful compile or passing
local fixtures alone does not establish any of these live flows.

## Local preview verification (2026-10-15)

The signed local preview, not a new public release, has passed:

- An actual managed Google-connected test login, verified-email enforcement and
  authenticated save to the deployed settings service.
- Restoring the cloud copy after deliberately changing one allowlisted battery
  display choice; the original value was restored.
- SDK refresh-token renewal and cached sign-in surviving a full app restart.
- Cancel Sign-In recovery in the running app; synthetic timeout, duplicate and
  late-callback regressions, plus first-login Keychain regressions against the SDK.
- App/helper signing identity and Sparkle key preservation. HUD event-tap checks
  after cold launch, Restart HUD and closing Settings. Protected appearance,
  display, Dock and HUD preferences were preserved.

This does not establish email/password signup/recovery, passkey enrollment,
Sign in with Apple, account switching or real two-Mac conflict behavior.
Apple login remains hidden until owner-side Apple Developer configuration is
complete. The account inspected on 2026-10-15 showed the free developer landing
page and no identifier/key management. The owner explicitly declined paying for
Apple membership, so leave Apple login disabled; do not start enrollment or change
the app's identity to work around this. Email/password and hosted passkeys do not
depend on that membership. Sign-out was also verified in the running preview;
the email/password signup and passkey flows still need a completed user test.
The test Google connection still uses Auth0 development keys; replace
those credentials or disable that connection for this app before public rollout.
Owner MFA enrollment and a production email sender also need verification. No
new GitHub release, updater-path test or GitHub CI run is implied by this preview.

### Follow-up verification (2026-10-15)

- A fresh browser sign-in returned to the installed app with a verified email.
  Refresh Account Status successfully renewed the session. This observation
  does not identify which sign-in method the user completed.
- The saved minimum password length was visually confirmed as 8, as explicitly
  requested by the owner. Other password protections were not changed.
- Passkeys were found disabled, despite their prerequisites showing Ready.
  They are now saved as Active with Passkey Button & Autofill, progressive
  enrollment and local enrollment. Password authentication remains active.
  Actual user-controlled passkey enrollment and login still need testing.
- Google Cloud sign-in completed for the authorized owner account, but the
  project creator requires a parent organization/folder and its resource picker
  fails to load. No Google project or OAuth client was created, no billing was
  enabled, and company access controls were not changed. The Auth0 Google
  connection still has its development-key warning.
- Use my own email provider is off in the live Auth0 dashboard. The owner has
  no app domain yet. A production sender/provider and any domain or mailbox
  authority must be resolved before configuring customer emails; signing in
  with a work address does not authorize using it as an automated sender.
- The owner explicitly prohibited using `grechlawfirm.com` for the app's
  hosting, customer emails, DNS configuration or cloud projects. Use separate
  app-owned resources. Existing owner sign-in identities are not authorization
  to deploy inside the law firm's organization. Do not purchase a domain,
  migrate owner logins, delete accounts or change company settings without the
  appropriate specific authorization.

### Passkey fallback in the local preview

The owner deferred email-based password recovery in favor of a saved passkey.
The installed preview now offers **Sign In with a Passkey** as its primary
account entry point. It opens the existing database connection's Universal
Login screen, where the person chooses **Continue with a passkey**. Existing
password/provider login remains under **Sign In Another Way**. No custom
WebAuthn implementation, purchased domain or Apple Developer entitlement is
needed for this hosted route.

For email/password accounts, **Sign-in & Recovery → Set Up or Check a Passkey** forces a
fresh hosted sign-in. Its SDK-validated returned subject must exactly match the
current account before credentials can be replaced. A different account,
cancellation, timeout or rejected response leaves the current session and sync
baseline intact. Reauthentication does not inherit or enable sync for a different
identity. The app cannot tell which hosted method was selected, so it reports
account sign-in confirmation, not an independently proven passkey event.

External-provider accounts show plain-language sign-in guidance instead of
pretending to attach a database passkey to that identity. The current owner
login was confirmed as Google in Auth0's Users list. The owner delegated the
choice of a safe approach: keep that existing identity and its cloud settings,
without changing the work Google account's security, creating a second account,
or linking accounts. The page now says to continue with Google and does not
present an inapplicable passkey-backup setup card. No provider passkey was
created, no accounts were linked, and the owner login survived the install.

The simplified page was verified in the signed installed preview. The existing
Google session survived a full app replacement/relaunch and renewed successfully.
Provider-display fixtures, exact-subject checks and the real SDK storage tests
pass. The app/helper identity and update key are unchanged; the HUD has exactly
one enabled interceptor after cold launch, Restart HUD and closing Settings.
Before/after preference exports match for the stored protected HUD, display,
Dock, theme and layout keys. This pass did not repeat a real volume-key test or
exercise a Sparkle update. It did not create or authenticate a real passkey.

Passkey routing, exact-subject guards, callback cancellation/timeout and Keychain
regressions pass. The signed build and signing-identity gate pass. Actual
passkey enrollment and biometric/device confirmation require the human user and
remain pending. Losing both the password and all passkeys can lock a person out.
This fallback does not itself reset a password or prove ownership of a typed
email address. It does not disable the existing server email-verification gate,
change email templates, send recovery emails, or establish production readiness.

The normal-release requirements remain incomplete. Following the owner's later
request to publish, version 2.9.0-beta.1 is prepared as an optional prerelease,
with an Account Preview notice in Settings and onboarding. Stable 2.8.3 and its
automatic-update feed stay unchanged. A prepared archive is not evidence of
publication; release, download and CI status must be verified separately.
Permission to log in to relevant services is not
a substitute for user-controlled credentials, payments, company resource access,
or a new privileged account-deletion integration approval.

Before public account rollout, also provide a verified way for a person to
request deletion of their login identity and associated settings. **Delete Cloud
Settings** deliberately removes only the synced settings document; it does not
satisfy account deletion. Any management credential for a coordinated deletion
flow must remain server-side with narrowly scoped access and appropriate
reauthentication. Do not ship the account preview as fully production-ready
while these requirements remain outstanding.

Local regressions (from the repository root):

```sh
bash .github/scripts/test_account_storage.sh
swiftc -parse-as-library -swift-version 6 \
  Notchscape/managers/AccountSignInAttempt.swift \
  tests/AccountSignInAttemptTests.swift -o /tmp/notch-account-sign-in-tests
/tmp/notch-account-sign-in-tests
```

Primary documentation:

- https://github.com/auth0/Auth0.swift
- https://auth0.com/docs/authenticate/database-connections/passkeys
- https://auth0.com/docs/authenticate/identity-providers/social-identity-providers/apple-native
- https://developers.cloudflare.com/d1/worker-api/prepared-statements/
- https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
