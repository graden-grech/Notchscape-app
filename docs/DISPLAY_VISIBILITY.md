# External-display visibility

General → Display style and sizing → **Show on external displays** controls
whether this Mac creates notch/island windows on non-built-in screens. It is on
by default so existing installations keep their behavior.

When off:

- Both single-display and all-display modes exclude external screens, including
  their expanded drag-detection areas.
- A connected built-in display remains eligible. A saved preferred external
  display does not override the off switch, even with automatic switching off.
- A desktop Mac or a MacBook with only external screens available shows no
  notch/island. Open the app from Applications to reach Settings again.
- External style/height, all-display, preferred-display and automatic-switching
  controls are disabled and visibly dimmed. Their saved values are not reset.
- The visibility choice remains local and is rejected by the cloud-settings
  allowlist. Another Mac cannot restore its display preferences here.

Turning the switch on restores the existing display-selection policy and saved
choices. Built-in detection uses `CGDisplayIsBuiltin`, not the presence of a
physical camera notch. Changes and display-configuration events use the same
window-selection policy.

## Local verification (2026-10-15)

The signed local preview passed:

- Pure policy tests for multiple external screens, built-in fallback, clamshell
  and desktop cases, missing preferred screens, automatic switching, and no
  connected screens.
- Running UI off/on tests in single-display and all-display modes. Controls have
  disabled accessibility state and visibly dimmed labels/controls.
- Off-state persistence across a full quit and cold launch, with the built-in
  notch still usable. Original display choices were restored after testing.
- Signing/helper identity and updater-key preservation, plus protected HUD,
  Dock, theme and layout preference comparisons.
- Exactly one enabled media-key interceptor after cold launch, Restart HUD and
  closing Settings. The user confirmed a real volume key shows the notch HUD.

Only the built-in Retina display was connected during this verification. Actual
external-monitor hiding/reappearance, hot-plug and clamshell behavior still need
hardware checks. No new GitHub release, CI result or Sparkle update-path test is
implied by a local installation.
