# HUD release checks

Do not treat a successful build or successful Sparkle install as proof that the HUD works.

Before installing or packaging a custom build, run:

```sh
bash .github/scripts/verify_custom_app_identity.sh "path/to/candidate.app" "path/to/previous-trusted.app"
```

For subsequent local builds, use the signed build entry point; it runs this gate
automatically and fails the build workflow if the gate fails:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  bash .github/scripts/build_custom_signed_app.sh "path/to/previous-trusted.app" "/tmp/boringnotch-sports-derived"
```

This fails on invalid/ad-hoc signing, a changed bundle identity or team, a changed
Sparkle public key, or a changed app/helper designated signing requirement.
The 2.9.1 rebrand changes the public app filename and executable to Notchscape.
Treat existing-installation renaming as a separate, tested migration; never
silently leave a second copy running. Switching from Apple Development to Developer ID
requires a deliberate permission-migration plan; do not silently switch identities.

The signed build entry point also checks that the built `CFBundleName` and
`CFBundleDisplayName` match the explicit source branding. Do not install a stale
or generated-plist artifact merely because its signature is valid. The visible
product name, executable and app filename must all agree. The identity gate
matches helpers by their stable identifier so product filenames can change
without silently weakening signing validation.

With HUD replacement enabled, identify the installed app's running PID and run:

```sh
swift tests/HUDRuntimeSmoke.swift RUNNING_APP_PID
```

Run this after a cold launch, the Restart HUD control, closing Settings, and a
real Sparkle update/relaunch. Check an actual volume/brightness key visually too.
Verify that the original HUD preference, Dock visibility, theme, and layout remain
unchanged. CI cannot grant macOS permission or perform the live media-key test;
perform these checks on the signed installed app before claiming release success.

Recovery uses bounded retries at launch/activation/wake, not a permanent watchdog.
The status checks the actual enabled event tap and its run-loop source. An existing
permission denial must still be handled by the user in macOS; never reset TCC or
grant access automatically. Do not overwrite a published release archive with a
new build; release a new version for subsequent corrections.

For local Sparkle archive signing, explicitly select the existing Keychain
account `boringNotch-custom` with `sign_update --account boringNotch-custom`.
The global default account `ed25519` is not this app's update key. Independently
verify the resulting archive signature against the `SUPublicEDKey` pinned in
the trusted app before uploading or changing the feed. A signing tool exiting
successfully does not establish that it selected the right key. Never export
private keys, change the app's pinned key, or rotate keys to bypass this gate.
