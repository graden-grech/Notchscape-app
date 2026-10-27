# Notchscape build and release rules

- Preserve user preferences and app signing/update identity. New public app
  bundles, executables, source folders and installers are named Notchscape.
  An existing install-path rename needs a recoverable, tested migration. Do not reset
  macOS permissions or modify global Dock settings as part of a build or update.
- Use `.github/scripts/build_custom_signed_app.sh` for local install/release builds,
  with a previously trusted app as the identity baseline. Never install unsigned
  or ad-hoc CI products over the permission-approved app.
- Before packaging, run `.github/scripts/verify_custom_app_identity.sh`. A failed
  signing-identity or Sparkle-key comparison requires explicit migration planning,
  not disabling the gate.
- Follow `docs/HUD_RELEASE_CHECKS.md`. Check the enabled HUD event tap after a cold
  launch, Restart HUD, closing Settings, and a real update/relaunch. A successful
  compile or Sparkle installation alone is not a passed HUD regression test.
- Publish only to `personal` (`graden-grech/Notchscape-app`) with user authority.
  Never replace a published archive with a different build. Use a new version for
  post-release corrections and retain old update-feed items.
- Report release, updater, HUD, and CI outcomes separately. Clearly state any live
  hardware, permission, or update-path testing that remains unverified.
- This is a new standalone repository with fresh history. Preserve source and
  dependency licenses/credits. Do not import old Git history, forks or release
  tags as a shortcut when preparing this checkout.
- Keep `graden-grech/Notchscape` and its prior rename redirects publicly readable
  for existing downloads and signed migration feeds. A compatibility-feed update
  there is separate from publishing new app releases here. Do not delete, rename
  or privatize the legacy repository or replace any published archive.
