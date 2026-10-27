# White House photographic artwork variants

These are independently imagined architectural illustrations, not documentary
photographs of current White House rooms or an endorsement by a government or
political party. No political figures, official seals, party emblems, flags,
campaign text or logos are included.

## Asset family

All assets live in `Notchscape/Assets.xcassets/`, with one universal PNG per
matching `.imageset` directory and a complete `Contents.json`.

For each scene (`Exterior`, `OvalOffice`, `EastRoom`, `BlueRoom`):

| Accent | Ordinary scene | Christmas scene |
| --- | --- | --- |
| Neutral | `WhiteHouse{Scene}Backdrop` (existing) | `WhiteHouse{Scene}ChristmasBackdrop` (recovered) |
| Republican | `WhiteHouse{Scene}RepublicanBackdrop` | `WhiteHouse{Scene}RepublicanChristmasBackdrop` |
| Democrat | `WhiteHouse{Scene}DemocratBackdrop` | `WhiteHouse{Scene}DemocratChristmasBackdrop` |

The original four neutral scenes and the optional White House app icon remain
unchanged. The four neutral Christmas images were recovered from original
built-in generation outputs preserved outside the lost temporary worktree;
they were copied, not regenerated. The eight ordinary red/blue variants and
eight Christmas red/blue variants are non-destructive built-in image edits of
their exact corresponding neutral scenes.

## Visual direction

- Architecture, camera framing, room identity, furniture layout and believable
  stone, fabric and wood materials are retained to visual inspection.
- Red/blue variants change physical-looking upholstery, rug edges, drapery,
  ribbons, ornaments or localized architectural accent light. They are not a
  flat full-frame red or blue overlay. The Blue Room retains its navy walls.
- Christmas has fresh snow outside, evergreen decorations and abundant warm
  white lights. Indoor rooms have no snow; room geometry remains recognizable.
- The calmer, darker left/central area remains available for foreground Home
  controls, while important architectural and decoration detail is toward the
  right. A shallow Home crop still cannot show every detail of a complete room;
  the photo audit separately controls full-photo previews and fitting behavior.
- These are static local images. They add no video, timer, audio, animation loop
  or network dependency.

## Generation and provenance

Only built-in `image_gen.imagegen` was used for the new edits. No image CLI,
external API, API key, manual painting or Python image editing was used. Every
edit target was inspected with `view_image` first. All scene calls specified
`referenced_image_paths: [exact_target]` and `transparent_background: false`;
`num_last_images_to_include` was not used. Each variant used its own call, with
no more than two calls in flight per artist. Generated originals were retained.

Exact prompt arguments, inspected target paths, original output paths and
consumed project paths are persisted in:

- [ordinary accent edits and recovered Christmas outputs](WHITE_HOUSE_PHOTO_ARTWORK.json)
- [Christmas accent edits](WHITE_HOUSE_CHRISTMAS_ACCENT_ARTWORK.json)

The recovered neutral Christmas outputs were created by the earlier artwork
task. Their file mapping and SHA-256 are recorded; this recovery does not claim
that its original generation prompts were recovered from the discarded
temporary worktree. The new sixteen accent-edit prompts are preserved exactly.

## Validation scope

Artists visually inspect every output for room identity, realism, framing,
localized accent changes and the absence of extra text/symbols. Native `sips`
metadata and SHA-256 checks are recorded with the manifests. New images are
approximately 16:9, with native canvases of 1672–1673 × 940–941 pixels and under
8 MB each. The one-pixel canvas variation is retained without an extra crop or
resize. The integration tests additionally require all twenty-four asset
references to resolve and their image hashes to be distinct.

No app default icon, signing identity, account flag, user preference, installed
app, build version, release archive or update feed is changed by artwork work.
Successful image checks alone do not establish live Home, accessibility,
display-hardware, packaging, updater or HUD behavior.
