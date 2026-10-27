# Shared installation and first-run defaults

Notchscape belongs at `/Applications/Notchscape.app`, not a user's private
`~/Applications` folder. That shared app can be opened by other local accounts.
Each account retains its own preferences, permissions, local data and optional
login item. Installing the app does not auto-launch it in every account, share
private content, grant Accessibility/Notes/location permissions or install a
privileged/background system service.

## Fresh users versus upgrades

For a genuinely new user, Weather starts **off** and Show on all displays starts
**on**, with external displays eligible. A user's later choices remain their
own. The one-time presentation-defaults migration preserves explicit settings
and the old implicit defaults of accounts that completed onboarding. Merely
changing a registered Key default would have silently changed those accounts.
The migration runs after legacy sandbox preference recovery, before normal app
startup, and writes through Defaults so its cache agrees.

The standalone `AppPresentationPolicyTests` suite exercises fresh/partial/old
preference dictionaries without touching the real app domain. Header tests
also reserve eight points above every expanded control on physical-notch and
notchless displays; closed island, physical-notch and open-menu size stay the
same.

## Installer

`.github/scripts/package_shared_installer.sh` builds a native macOS `.pkg` that
only allows the Local System domain and installs exactly `Notchscape.app` in
shared `/Applications`. Bundle relocation is disabled, so a copy in Downloads
or a private Applications folder cannot redirect the installation. The payload
has recommended shared ownership. No installer scripts, automatic permission
grants, credential handling, account changes, or login-item changes are used.
macOS retains its normal administrator authorization when needed.

For 2.9.2/build 295 and later, the target volume must have macOS 15 or later,
matching the app's media framework and declared minimum. This is a declarative
Installer OS check, not a custom installation script. The ZIP/archive gate also
rejects a candidate advertising a lower or missing minimum.

Both ZIP and installer packaging run `verify_shared_install.py` in addition to
the existing branding/signing/account gates. It rejects owner-only resources,
untraversable directories, owner-only executables, world-writable content and
broken/out-of-bundle symlinks. This proves filesystem availability, not that a
second account's privacy grants or a complete OS/hardware matrix were tested.

The installer packaging entry point requires a **Developer ID Installer**
identity for distribution. An explicit `--unsigned-preview` is available only
for an unpublished local structural test. The current Apple Development app
signature is not an installer identity and does not satisfy notarization.
Customer installer signing, notarization and an actual authorized install are
separate release gates. No Gatekeeper/quarantine bypass is part of packaging.
Sparkle's immutable ZIP and update feed remain separate and unchanged by
building a shared installer.

## Local preview verification — 26 October 2026

The installed signed 2.9.2/build 293 bundle passed the shared permissions gate
across 369 entries. A native package was built using `--unsigned-preview` and
expanded without installing it. Its generated metadata targets `/Applications`,
requires root authorization, disables relocation and has no install scripts.
The expanded payload passed identity/permissions checks and its executable
matches the installed app and extracted ZIP. This verifies package structure
and filesystem access; it is not an administrator-install or second-account
launch test. Exact hashes and remaining signing/release gates are in
[the preview report](releases/2.9.2-preview.md).
