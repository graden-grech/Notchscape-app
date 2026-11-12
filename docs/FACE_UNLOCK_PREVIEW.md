# Face Unlock preview

Settings → Face Unlock is an optional, local webcam feature. Accounts are not
needed. It starts off: app launch does not open the camera or access a vault
unless the owner previously enabled automatic Face Unlock.

## Local verification checkpoint

Signed local build 304 repairs the helper's session configuration. Its harmless
Check Setup now reports “Protected storage is ready.” Real authentication,
enrollment and unlock remain separate user-controlled tests. Installed local build 305 added a guided camera sheet with a mirrored oval preview and progress ring for
explicit enrollment/recognition tests. It never displays preview frames during
automatic lock-screen scanning; pending display delivery is bounded and frames
are cleared when the capture ends.

The Add-ons Store is a catalog preview. Face Unlock is currently bundled with
this local build and is not yet a separately downloadable component. The private
development profile still prevents general customer distribution.

## Setup and everyday use

Choose Set Up Face Unlock and complete macOS authentication yourself. Add a
named face or appearance, grant Camera access if asked, and follow the center,
head-turn and return prompts. Test Recognition keeps the Mac unlocked and must
pass before the first automatic enable. Up to eight appearances are supported,
including glasses; each can be renamed, disabled or deleted. Every enabled
appearance authorizes the same Mac user account.

Enter the Mac password only in the app's secure field. It is checked locally
before saving. After reviewing the camera/key-in-memory tradeoff, turn on Use
Face Unlock. There is no timed-session length or recurring Start Session button.
Scans begin briefly when the Mac locks or wakes locked. Turning the switch off
clears the in-process authorization. After an app restart, macOS may request
fresh authentication to resume a previously enabled preference.

Check Setup is a read-only connection/configuration check. It does not create,
read or delete a Keychain item, enroll a face, request authentication or run the
camera. If a lost setup reply left a key without a vault file, Recover Setup is
an explicit, separately authenticated operation: it reads only that exact key
and creates an empty vault only while the encrypted file is still absent. It
never replaces an existing file/key or imports someone else's enrollment.

## Protected storage and identity

The existing main app/helper signing identity is preserved to retain settings,
HUD permissions and update trust. A separately provisioned, app-private XPC
service owns Data Protection Keychain operations. It validates the signed main
peer, exact user and active local session, and independently performs fresh
system authentication. The main app cannot substitute a Boolean for that grant.
The service accepts only bounded create/read/delete operations for its own
per-user vault keys; no arbitrary Keychain dictionaries, filesystem paths,
scripts or caller-selected user identities are accepted.

The full appearance manifest and optional Mac password are AES-GCM encrypted
locally with fresh nonces. The random master key uses device-only, user-presence
Keychain protection in the helper's exact private access group; nothing syncs
to iCloud. Labels and embeddings are encrypted with the credential. Camera
images are neither saved nor uploaded. Model loading has no network fallback.

Automatic mode deliberately keeps the unwrapped master key in this app's RAM
while enabled. Sleep pauses camera/output/key use while retaining that explicit
volatile authorization; wake resumes only after current session checks. Off,
quit, logout, user switching or privacy invalidation revoke it. Releasing Swift/
CryptoKit objects cannot guarantee physical RAM erasure. The ordinary protected
settings mode retains its separate five-minute limit.

The current helper uses a seven-day free-development profile for one registered
Mac. This is a local test configuration, not a generally distributable Face
Unlock release. A public download requires appropriate distribution signing and
provisioning; a source build or renewed local profile does not establish that.

## Apple Watch and native-unlock priority

Native Apple Watch, Touch ID or password unlock takes priority. The app allows
a short native-unlock grace interval, then requires current locked-session and
face evidence. An actual OS unlock immediately revokes any pending output,
cancels capture and suppresses stale success/error UI. Public companion
availability is advisory and does not attest that Mac Auto Unlock is enabled.

Password text is never copied to the clipboard or sent as keyboard text. It can
only be set on the exact verified writable secure accessibility element owned
by Apple-signed loginwindow for the current local user. The target, process birth
identity, focus, lock generation, authorization and cancellation epoch are checked
at output boundaries. AX Confirm is preferred; only a non-secret, process-targeted
Return remains as an alternative after revalidation. Readonly or unsupported
fields refuse submission. There is no global typing or alternate text fallback.

An AX request already dispatched cannot be retracted. The protection against the
previous-app-textbox race is explicit secure-element addressing, rather than a
claim that cancellation makes an already-dispatched request atomic. Submission
is reported as submitted, never as proof of a successfully unlocked Mac.

## Recognition and platform limits

This is RGB webcam convenience recognition, not Apple Face ID or Touch ID.
Movement heuristics can be fooled by video and do not establish strong liveness.
Preview thresholds/alignment have not undergone real-person false-match or spoof
calibration. One face, frame-quality/alignment/continuity gates, a randomized
head turn and six fresh matched observations are required. Capture processes at
most four frames per second and has a short deadline. A failed output is not
retried in the same lock generation. The normal Mac password remains available.

This cannot unlock FileVault, initial boot login, a different user's account or
a remote session. Locked-Home rendering has separate macOS compatibility limits.
Real system authentication, camera enrollment, matching and actual loginwindow/
Apple Watch behavior still need user-controlled testing of the installed build.
No agent test enters a real password, records a person or attempts an unlock.

## Independent implementation and verification

No Glance code, history, images or model weights were imported. The recognition
adapter uses official OpenCV Zoo SFace, independently converted to Core ML.
Apache 2.0 license, original credits, pinned provenance and conversion notice
remain bundled in Notchscape/Resources/FaceModels. Exact weights, conversion and
alignment revisions are part of the schema; incompatible enrollments cannot match.

The focused suite uses synthetic vectors/events, encrypted temporary fixtures
and mocked broker transports. It checks conversion parity, authorization,
reply/cancellation races and guarded output policies. Native Core ML parity
against the generated ONNX reference has normalized L2 error1.86e-6, which
verifies conversion, not live recognition accuracy. Current exact results,
signed build/profile gates, installation state and pending hardware tests are
recorded in the private LOCAL_VERIFICATION checkpoint and release notes.

This source is unpublished. It must not be presented as production authentication
or a verified public update merely because synthetic tests pass.


Local build 305 human follow-up (2 November 2026): the user authenticated manually and confirmed the oval camera guide opens. The user also confirmed the real volume-key HUD appears inside Notchscape. Enrollment completion, recognition quality, automatic unlock and Apple Watch races are not validated by those checks. No public release or updater test was performed for build 305.

## Setup interface refinement — local build326

Added a collapsible four-step setup checklist, optional appearance names with validated defaults, and a troubleshooting disclosure. The scan sheet now puts the current head-turn guidance above a larger oval, shows bounded progress, and keeps Cancel pinned. Its500x600 layout was checked in light and dark using exact-source synthetic components:462.5pt card inside512pt viewport. The actual locked settings screen was inspected without starting authentication or capture.28 existing preview lifecycle checks, signed wrapper/identity/profile gates,68-key preference preservation and cold/Restart-HUD/Settings-close/final-relaunch tap checks passed. Existing compiler warnings remain outside these UI changes.

No recognition thresholds, vault, camera pipeline, password submission or Apple Watch logic changed. Real enrollment, recognition and physical-key326 testing remain human checks. No public release or update-feed change. The Face helper still uses the local development profile expiring13November2026.

## Live preview repair — local build327

The sheet now directly observes the manager so published frames/guidance update the presented content. The pixel adapter downsamples larger valid frames instead of silently skipping dimensions over640. Synthetic1280x720 and1920x1080 frames become640x360; portrait previews remain bounded.73 adapter/alignment checks and38 lifecycle checks passed. Capture authorization, session identity, stale-frame rejection and automatic-lock-screen preview prohibition remain unchanged. Signed build327 installed locally; the human live camera test is pending.

## Local build 328: native interactive preview

The interactive enrollment/test picture now uses a native
`AVCaptureVideoPreviewLayer`, independently of the bounded Vision/Core ML path.
The previous SwiftUI CGImage preview ran only after the recognition interval
(default 0.35 seconds), so its effective display rate was about 2.86 fps.
Interactive capture prefers supported 1280×720; automatic lock-screen capture
retains VGA and creates no preview layer. Recognition input remains bounded
to a 640-pixel longest edge, with existing alignment, model and matching gates.
No changes to face templates, credential submission or storage migration.

The scan sheet now shows a wider view with a dimmed surround, a centered oval,
and a short directional prompt. The native preview mirrors once using layer
bounds/position so resizing does not jump. Cancel/lock/auth expiry revoke the
source and remove the view; old-session and stale events remain gated.

Small MIT preview-hosting adaptations come from Glance commit
`4ae2faee87dfd84d0721ffaaac305c8b07b57419` and FaceUnlock commit
`d1a62e5354732f1a021be0480cef842f05634753`. Full notices ship in
`Resources/FacePreviewNotices.txt`. Their model weights, global password
injection and repository histories are not included. Existing SFace model
provenance remains unchanged.

Camera-free verification: 15 native layer attachment/resize/mirroring/revocation
checks, 73 adapter/alignment checks, 38 preview-policy checks and 86 recognition
session checks. Light/dark fixtures use only an artificial color swatch; they
are not evidence of live camera quality, spoof resistance or unlock reliability.
Actual enrollment and Apple Watch/native-unlock races require human testing.
