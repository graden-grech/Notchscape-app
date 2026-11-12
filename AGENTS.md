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
- The Face Unlock broker currently uses a seven-day, device-bound Personal Team
  development profile. It is for local testing only. Do not upload that profile
  or package it as a generally usable public app; require suitable distribution
  signing/provisioning before including Face Unlock in public downloads. Keep
  local build/installation verification distinct from distribution validation.
- Report release, updater, HUD, and CI outcomes separately. Clearly state any live
  hardware, permission, or update-path testing that remains unverified.
- This is a new standalone repository with fresh history. Preserve source and
  dependency licenses/credits. Do not import old Git history, forks or release
  tags as a shortcut when preparing this checkout.
- The user deleted both prior repositories and explicitly requested a fresh
  repository without restoring either one. The active `Notchscape-app` was
  recreated at the same URL with repository ID `1437626275`. Do not restore or
  recreate the deleted legacy `Notchscape` repository or its former aliases.
  Preserve the exact republished 2.9.3/2.9.4 archives and current update address.
  Older installations whose embedded feeds point to the deleted legacy URLs
  need a manual download; do not claim those compatibility feeds still work.

## Collaboration and continuation

- Reuse an idle subagent before starting another agent for a related specialty.
  Delegate independent requests added during active work and keep the main chat
  progressing on its existing task. Coordinate file ownership before edits.
- Do not create automatic follow-ups, heartbeat timers or usage-reset wake-ups.
  The user explicitly stopped them because they consume usage. Save an exact
  checkpoint when needed and wait for the user's next message. Only schedule
  again if the user explicitly asks for a new scheduled action.
