# Display compatibility preview

This is local preview work for 2.9.5, not a claim that Notchscape replaces
Apple's Mac Dynamic Island. It is available from General → Display style and
sizing → Display Compatibility Preview, and from Help.

The preview has three disposable sample layouts: an attached notch, a floating
camera, and an external display. Sample dimensions are not new MacBook
measurements. Opening it does not change the user's saved presentation, height,
display choices, theme or activity priorities.

`DisplayGeometryPolicy` separates a system-reported top safe area/gap, an
explicit physical-camera measurement and the user's visual style. The
read-only NSScreen adapter matches each display to its own Quartz frame. It
does not infer native-island support from a product name, pixel resolution or
positive safe-area inset. Legacy sizing retains the measured gap and offset.

Click routing is off by default and has no saved enable preference. An explicit
test captures only unmodified left clicks in the two visible lanes of the
sample island in the app's own active window. The central camera lane is
protected. A captured drag cancels activation and consumes the remainder of
that captured gesture; unrelated clicks, drags, keyboard and menu input pass.
Menu tracking, leaving/moving/closing the window, lock/sleep, changed display
geometry or a disabled tap stop the test. Returning never resumes it.

Stopping during a captured press releases the tap immediately. Subsequent
physical events pass through; the app does not synthesize replacement events
or keep a capture alive after Stop. This rare mid-press boundary cannot promise
an atomic downstream gesture across teardown.

The native-island start entry point is deliberately unavailable. There is no
automatic camera-hole measurement, native island suppression, Siri/Spotlight
override, global activity feed, or verified new-Mac touch behavior here.

## Local validation on October 29, 2026

- 479 pure geometry checks and 90 click-policy checks passed. The read-only
  connected-display run passed 482 geometry checks and matched the existing
  display's 185 × 32-point gap and zero center offset.
- The signed Release build passed app/helper identity, visible-branding,
  pinned-update-key and accounts-disabled gates.
- The preview window's fixed content size was visually checked after correcting
  the hosting view's unconstrained preferred height.
- The user confirmed that enabling the test and clicking a sample symbol
  increments the counter and opens sample Home. Accessibility subsequently
  reported four routed clicks. Leaving the window paused the test.
- Cold launch and Restart HUD retained exactly one enabled media-key tap. All
  33 allowlisted user settings matched the pre-install snapshot.
- 108 Python repository checks passed. New geometry/input checks are registered
  in CI, but this unpublished source has not run on hosted CI.

This does not cover physical PROLED hardware, touch, all scaling/mirroring/
DisplayLink combinations, or Apple's system-initiated activities. No release,
download archive or update feed was published for this prototype.
