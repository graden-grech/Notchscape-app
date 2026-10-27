# Custom releases and updates

Notchscape publishes source and signed update archives at
`graden-grech/Notchscape-app`.

The app checks this public Sparkle feed:

`https://raw.githubusercontent.com/graden-grech/Notchscape-app/main/appcast.xml`

Update archives are signed with a dedicated Sparkle EdDSA key stored in the
local macOS Keychain under the account `boringNotch-custom`. The private key is
not committed to GitHub. `SUPublicEDKey` in `Notchscape/Info.plist` contains
only the matching public key.

For each future release:

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for both the app
   and XPC helper targets.
2. Build the Release configuration with the same Apple signing identity.
3. Run `.github/scripts/package_notchscape_release.sh` with the signed
   `Notchscape.app`, the previous trusted app, and a new staging directory.
   It produces `Notchscape.zip` containing **Notchscape.app**, verifies the
   actual bundle/executable names, preserves signing trust, and rejects an old
   product hidden inside a newly named ZIP.
4. Run Sparkle's `generate_appcast` with `--account boringNotch-custom` and a
   download URL for the matching GitHub release tag.
5. Publish the tag and ZIP, then commit and push the updated `appcast.xml`.
6. Confirm the raw appcast and release asset are publicly reachable before
   announcing the update.

The `personal` remote is the only release destination. Never push to another
remote or replace a published archive. A new source push does not publish a
download. Keep old release assets and compatibility feed redirects available
for installed clients. See [distribution readiness](docs/DISTRIBUTION_READINESS.md).
