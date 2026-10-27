# White House architectural theme

This is follow-up work, not part of the immutable 2.9.1 branding release or the
earlier local 2.9.2/build 291 preview. It is now integrated in the signed local
2.9.2/build 293 preview. See [the integration results](releases/2.9.2-preview.md)
for installed UI, preference, packaging and HUD checks, and remaining release
gates. The public release/update feed and signing identity remain unchanged.

## Experience

Settings → Appearance → Menu theme has **one White House card**. It opens a
native grouped sheet with:

- **Photo & accent style:** Neutral (limestone/navy/gold), Republican (red), or
  Democrat (blue). The selected photos now have matching décor and lighting,
  not just a different button tint or an overall photo filter. Neutral is the
  initial choice. These are decorative, explicitly chosen styles, not inferred
  affiliations or campaign content.
- **Rooms & views:** Exterior, Oval Office, East Room, and Blue Room, each with
  its own original, generated photographic-style scene. The illustrations are
  architectural interpretations, not documentary photographs of current rooms.
- **Christmas decorations:** an independent, opt-in toggle. Every room has a
  festive version in all three color styles, with trees and lights indoors and
  fresh snow outside. Turning it on or off keeps the room and color choice.

Any of the three styles works with any of the four scenes and either decoration
setting. Changing one retains the others. The twenty-four combinations are
atomic `AppTheme` values, so existing
theme/accent/Home observers update together. `whiteHousePreferredVariant`
remembers the last combination when another theme is selected, including after
relaunch. All twelve existing raw theme identifiers still mean their original
room/style without Christmas; they are not reinterpreted or migrated. Appearance
recipes/import/export retain the exact combination, manual
accent, icon mode, and Home order/visibility. Recipe previews use local state and
do not apply anything until the user confirms Apply.

All scenes use the existing single Home backdrop layer and themed Home sizing.
No extra photo tile, portrait overlay, calendar resizing, menu-height change,
timer, video, particle system, network request, or live activity is added.
Native segmented controls/buttons retain keyboard and VoiceOver support;
existing Reduce Motion, Reduce Transparency, and low-impact rendering remain
authoritative. The optional icon uses the existing Notchscape mark in a neutral
limestone/navy/gold treatment, with transparent rounded edges. It does not use a
party mark, official seal, political figure, or endorsement claim. Four new
red/blue and Christmas icons can follow the selected style and decorations;
Neutral retains the original icon. The separate global Christmas theme and
manual icon choices are not overridden. See [icon artwork and matching
behavior](WHITE_HOUSE_ICON_ARTWORK.md).

Picker photos use full-image, aspect-preserving previews: 16:9 White House
scenes and approximately 3:1 existing seasonal/Star Wars panoramas. Native
scrolling accommodates the taller architectural thumbnails instead of chopping
off roofs and trees. Actual Home remains one full-bleed, intentionally shallow
panorama with the same size/calendar layout, right-aligned and vertically
centered for White House so its building/tree central band stays visible.
See [the complete framing audit](THEME_PHOTO_AUDIT.md) for the distinction.

## Independent preferences

- A manually selected accent continues to override every theme. The sheet
  explains this and points to Appearance → Accent color → Match theme.
- Match icon to theme selects the corresponding neutral/red/blue/Christmas
  White House icon. Room changes keep that icon family. A manual icon is not
  overwritten, and a hidden Dock tile is not recreated. The installed bundle's
  global default icon remains unchanged.
- Picking this theme stops automatic seasonal switching, just like other manual
  themes. It does not enable any feature, permission, live activity, or account.
- Account settings token allowlists are kept consistent for a future account
  build. **Accounts remain disabled; no account backend is deployed here.**
- Original license/credits and stable internal compatibility identifiers remain.

## Generated artwork provenance

The twenty added photo variants (four recovered neutral Christmas edits and
sixteen matching red/blue edits) are documented separately in
[WHITE_HOUSE_PHOTO_ARTWORK.md](WHITE_HOUSE_PHOTO_ARTWORK.md), with machine-readable
source/output/prompt manifests. Existing photos and the optional icon below
remain unchanged. No photo generation runs inside the app.

All six outputs below came from the **built-in `image_gen.imagegen` tool**,
not an image CLI, SDK, external image API, or user-provided API key. The exact
local output directory is:

`/Users/gradengrech/.codex/generated_images/01a16f38-3c2f-7581-bb9e-5b446e782d6a/`

Each source filename below is relative to that directory. The asset paths are
relative to `Notchscape/Assets.xcassets/`. All consumed files are byte-identical
to the corresponding retained generated outputs (SHA-256 comparison).
The complete verbatim prompt set and concatenation rule are preserved in
[WHITE_HOUSE_ARTWORK_PROMPTS.md](WHITE_HOUSE_ARTWORK_PROMPTS.md). The generation
tool did not create prompt sidecars; this versioned record was transcribed from
the artwork agent's actual tool-call arguments, not reconstructed from pictures.

| Output | Retained generated source | Asset catalog destination |
| --- | --- | --- |
| Exterior | `exec-11b0e035-7c3a-485c-adb0-94a074221a64.png` | `WhiteHouseExteriorBackdrop.imageset/WhiteHouseExteriorBackdrop.png` |
| Oval Office | `exec-cd787260-cac7-4335-9516-81f5d12f819c.png` | `WhiteHouseOvalOfficeBackdrop.imageset/WhiteHouseOvalOfficeBackdrop.png` |
| East Room | `exec-d1ba07ca-7900-4998-8f2e-888f587804ec.png` | `WhiteHouseEastRoomBackdrop.imageset/WhiteHouseEastRoomBackdrop.png` |
| Blue Room | `exec-cf08cab6-44df-4981-a6c9-7dd1f1aa5568.png` | `WhiteHouseBlueRoomBackdrop.imageset/WhiteHouseBlueRoomBackdrop.png` |
| Original icon v1 | `exec-087d695b-dc52-4de1-ae65-2a52655fffb0.png` | Superseded; retained in Git commit `0b70314d625c2afcf9afd4e2daa8679fb45fc6e1` as `AppIconWhiteHouse.imageset/AppIconWhiteHouse.png` |
| Transparent-edge icon v2 | `exec-b9444b5f-9fe9-4a7d-93e6-ca95920facec.png` | `AppIconWhiteHouse.imageset/AppIconWhiteHouse-v2.png` |

The four scenes were separate **new-image** calls with
`transparent_background: false`; both `referenced_image_paths` and
`num_last_images_to_include` were omitted. All four are 1672 × 940/941 PNGs. The
original icon was an **edit** with `transparent_background: true`, referencing
only the existing `AppIconStandard.imageset/AppIconStandard.png` in the isolated
worktree. The cleaned v2 was a separate targeted **edit** with
`transparent_background: true`, referencing only v1; no call used
`num_last_images_to_include`. Both icon outputs are 1254 × 1254 RGBA PNGs.
The edit-target base path for both calls was exactly
`/private/tmp/notchscape-whitehouse-work.LjXPTn/worktree/Notchscape/Assets.xcassets/`;
the v2 reference was `AppIconWhiteHouse.imageset/AppIconWhiteHouse.png` beneath
that path, before removal of the superseded catalog copy.

The targeted edit removed exterior colored speckles while retaining the mark,
rounded outline, and limestone/navy/gold finish. Native-pixel samples outside
the outline at `(507,70)`, `(506,68)`, and `(1174,850)` are fully transparent in
v2; all four corners remain transparent. The original had very faint 1/255 alpha
at sampled top speckles, which the preview exaggerated. The v1 binary was not
overwritten: only its superseded catalog copy was removed, and `Contents.json`
now consumes v2. The generated original and its committed historical copy are
recoverable. The consumed v2 SHA-256 is
`95e49079c42c5960a6616058a5ced7c76ceb9f001baa2fed1add8660d4b5aeed`.

## Verification

Standalone customization tests cover all twenty-four combinations, persistence,
and every independent style/scene/Christmas transition. Appearance tests cover every
combination with manual/theme-following icons and a custom accent. Account
allowlist fixtures accept only the known bounded tokens. Python regression
checks verify one family entry, no cross-setting writes, local complete PNG
assets, and unchanged global defaults. The isolated feature checks used a
compile-only Release build; signed installation was handled separately below.

Isolated feature checks: 597 customization policy checks, 220 appearance recipe
checks, 114 account allowlist checks, all 87 Python helper/integration tests and
all 9 isolated Node account-service fixtures passed. Asset checks verify every local
reference, native PNG dimensions/aspect, exactly one consumed image per set,
twenty-four distinct photo hashes, a bounded total payload, and full-photo
preview framing. Older 3:1 panoramas retain their source dimensions/artwork.
The icon/defaults checks still require the original neutral defaults and the
unchanged optional White House icon. All 24 photos are present, have distinct
hashes and total 51,210,523 PNG bytes. The subsequent signed build and live
UI/HUD results are recorded in [the integration report](releases/2.9.2-preview.md);
the isolated artwork change itself did not install or publish an app.

Before publication, the parent release process still needs visual review of
Home, settings, opening/closing transitions and a relaunch on notched/notchless
displays, custom-accent/manual-icon combinations, reduced-accessibility modes,
and a newly signed archive with the normal updater/HUD checks. A successful
compile is not a live visual, hardware, notarization, or update-path test.
