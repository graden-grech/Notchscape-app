# Theme photo and framing audit

## Scope and findings

All five existing seasonal photos (Fall, Halloween, Christmas, Winter, Easter),
the three existing Star Wars scene photos, and the four original White House
room photos were visually inspected. The artwork agents inspect each of the
twenty recovered/new White House variants as they finalize them. The finished
catalog has 32 bundled scene photos: eight existing 3:1 panoramas and twenty-four
White House 16:9 scenes. All scene files are local, non-animated PNGs.

The existing seasonal and Star Wars sources are intentionally wide, roughly
3:1 compositions. Their main decoration/lightsaber is on the right and their
left side is calm enough for Home content. The White House sources are 16:9.
The old fixed 78-point room thumbnail and 82-point theme banner treated both
types like a very wide strip, unnecessarily cropping architectural roofs,
chandeliers, and Christmas trees. No stretching or low-resolution substitute
was needed to correct that mismatch.

## Framing policy

| Surface | Policy | Reason |
| --- | --- | --- |
| White House room chooser and hero | Complete photo, 16:9, aspect-fit | Shows the entire source scene; no chopped focal architecture. |
| Appearance theme cards | Complete photo; 16:9 White House, 3:1 original panoramas | Respects each source family instead of forcing a single crop. |
| Saved Appearance preview | Same complete-photo policy | Import/creation preview matches the chosen artwork without applying preferences. |
| Actual Home | Existing full-bleed shallow panorama; White House right-aligned and vertically centered | Keeps the building/tree central band visible rather than mostly upper sky, without changing menu height, calendar dimensions, content readability or clipping behavior. Some intentional panorama cropping remains here. |

Picker surfaces scroll natively. No enlarged notch, additional photo tile,
stretch, second decorative layer, continuous blur, particle effect, video,
network image service, polling loop, or animation timer is introduced.
The outer theme cards expand to their shared grid-row height and align at the
top. Their photos retain their separate natural aspect-fit frames; equal card
backgrounds do not require a large filler image, color wash, or photo crop.

## White House color and Christmas mapping

The 24 atomic theme values select 24 distinct photos. Changing color, room, or
Christmas keeps the other two choices. Neutral preserves limestone/navy/gold;
Republican and Democrat choose separately edited red/blue décor and lighting,
not a flat full-image color wash. Christmas adds realistic decorations and
outside snow in each palette. The original twelve identifiers/defaults remain
valid, and icon/custom-accent preferences keep their own owners.

Exact generated-source, edit-target, prompt, asset path and hash provenance is
in [WHITE_HOUSE_PHOTO_ARTWORK.md](WHITE_HOUSE_PHOTO_ARTWORK.md) and its manifests.

## Automated checks and remaining live QA

Regression checks require all 24 White House image sets, native PNG files,
16:9 aspect, bounded file sizes, unique photo hashes and unchanged optional icon.
They also validate the eight existing panoramic sources, the full-image preview
branches, a single White House family card and all 24 bounded import tokens.
Policy tests exercise style/room/Christmas changes and serialization, including
manual icons and custom accents, without reading any user account or preference
store. Accounts remain disabled; no backend is deployed.

Completed local checks: 597 customization, 220 appearance recipe, 114 account
allowlist, 87 Python helper/integration tests, and nine isolated Node service
fixtures passed. The 24 White House photos are distinct PNGs totaling
51,210,523 bytes; native canvases are 1672–1673 × 940–941 pixels. No source
resizing, crop, default-icon replacement or runtime generation was used to
produce the matching variants.

The optional `StarWarsVaderSceneBackdrop` character image is absent in this
checkout. Its existing availability check safely falls back to the Dark Side
lightsaber source; that pre-existing optional-art gap is not represented as a
newly repaired character feature. The original Desert photo intentionally has a
beam exiting its source frame; layout containment cannot restore pixels not in
the source. Existing artwork was not silently regenerated during this audit.

Source/asset checks are not a substitute for live verification on notched and
notchless displays. The parent still owns signed integration, small-screen
scrolling/controls, calendar and music readability, theme transitions/relaunch,
Reduce Motion/Transparency, HUD/identity checks and any release/update tests.
No publication or installed-app mutation was part of the isolated audit commit.
The parent subsequently installed and checked signed build 293; see
[the integration results](releases/2.9.2-preview.md) for the exact live checks
and remaining display/accessibility/animation coverage.
