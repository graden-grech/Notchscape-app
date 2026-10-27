# White House palette and Christmas icons

Four optional Notchscape icon variants extend the existing neutral White House
icon. The original neutral image and the app bundle's default icon are retained.
All four use the same rounded glass silhouette, architectural columns and black
Notchscape mark; palette changes are deep red or sapphire blue, with contained
evergreen details, snow and warm lights in the Christmas versions.

| Theme choice | Matching icon asset |
| --- | --- |
| Neutral, any room, either decoration setting | Existing `AppIconWhiteHouse` |
| Republican, any room | `AppIconWhiteHouseRepublican` |
| Democrat, any room | `AppIconWhiteHouseDemocrat` |
| Republican + Christmas, any room | `AppIconWhiteHouseRepublicanChristmas` |
| Democrat + Christmas, any room | `AppIconWhiteHouseDemocratChristmas` |

Settings → Appearance → App icon contains one matching switch and a White House
group with all five manual choices. Choosing a manual icon disables matching;
later room, style and Christmas changes retain that manual choice. Turning
matching back on immediately chooses the current theme's icon. Startup resolves
the matching icon again, so existing theme-following installations adopt the
new red/blue artwork. A manually chosen neutral icon remains neutral.

These choices update the running Dock icon only when Show Dock icon is enabled.
They do not recreate a hidden Dock tile, modify Finder's installed bundle icon,
rewrite the signed app, alter a custom accent or enable accounts. Existing
appearance recipes retain their schema and can save/restore the new icon tokens.
The inactive account allowlists contain the same bounded choices; no account
service is deployed or enabled by this feature.

## Artwork paths and generation records

All four assets are workspace-bound PNGs beneath
`Notchscape/Assets.xcassets/`, each in its matching `.imageset` directory:

- `AppIconWhiteHouseRepublican.imageset/AppIconWhiteHouseRepublican.png`
- `AppIconWhiteHouseDemocrat.imageset/AppIconWhiteHouseDemocrat.png`
- `AppIconWhiteHouseRepublicanChristmas.imageset/AppIconWhiteHouseRepublicanChristmas.png`
- `AppIconWhiteHouseDemocratChristmas.imageset/AppIconWhiteHouseDemocratChristmas.png`

The **built-in `image_gen.imagegen` tool** produced targeted transparent-image
edits; no CLI, external image API or user API key was used. Exact prompts, edit
targets, generated source paths, consumed asset paths, dimensions and hashes are
recorded in [the Republican manifest](WHITE_HOUSE_REPUBLICAN_ICON_ARTWORK.json)
and [the Democrat manifest](WHITE_HOUSE_DEMOCRAT_ICON_ARTWORK.json). Final PNGs
are copied byte-for-byte from accepted generated outputs, retaining real alpha.

These are decorative Notchscape variants, with no official seal, party emblem,
political figure or endorsement claim. No image generation runs inside the app.

## Local integration verification — 26 October 2026

Signed Notchscape 2.9.2/build 294 is installed locally. The app/helper identity,
Sparkle trust key, customer-facing names, disabled-account flag and shared bundle
permissions passed their gates. Original neutral/default icon bytes are unchanged.

All four 1254×1254 RGBA variants were visually inspected, then checked at real
picker size in the installed app. The grouped picker exposes the complete
accessible names and selected states, with two-line Christmas labels. Generated
sources and consumed files match byte-for-byte; the blue manifest records its
remaining extremely faint alpha-1/255 margin samples.

Live checks exercised all four automatic palette/Christmas mappings, a manual
icon surviving a different theme choice, turning matching back on, and persistence
after relaunch. The app remained in hidden-Dock accessory mode throughout; a
visible Dock icon was not enabled for testing. The original theme and all 28
checked effective presentation/HUD settings were retained, allowing only the
intentional new palette icon when matching was already enabled.

645 customization checks, 230 appearance-recipe checks, 118 account allowlist
checks, 97 Python helper/integration tests and nine isolated Node fixtures passed.
Independent review found no substantive integration issue. Exactly one enabled
HUD interceptor remained after cold launch, Restart HUD, closing Settings and
relaunch. A physical volume key was confirmed on build 293, not repeated on 294.

This is an unpublished Apple Development signed local preview. No GitHub push,
release, feed change, account activation, notarization or customer updater test
was performed for this icon follow-up. The public release remains 2.9.1, and the
separately prepared build-293 ZIP/installer are not this build's artifacts. The
installed executable SHA-256 for build 294 is
`9a9ca2ea556045ed6c82255fe268279da905048ce10b0f2d94052fa057da7385`.
