# Integrated wallpapers and utility tools

The wallpaper library adapts the user's MacScapes catalog: 42 macOS wallpapers,
265 Windows wallpapers, 17 additional nature/seasonal photographs, and four official
NASA space images, for 328 unique entries. The Seasons collection curates 46 images
from those sources; Space has its own collection. A Windows-themed wallpaper is
not a Windows application; the Windows application itself is separately paused.

## One app, one update path

- Settings → Wallpapers opens the native library; its optional notch tab is off
  until enabled. Extra pages overflow into More instead of shrinking the tab rail.
- Collection, favorites, display choice, and rotation live in the same library.
- Import MacScapes Favorites reads only that app's saved favorite IDs. It never
  changes or removes the standalone app, its downloads, or its preferences.
- The integration does not import MacScapes analytics, accounts, auto-start, or
  Sparkle updater. The containing app retains its existing signed updater.
- Do not redirect the old MacScapes feed to an archive with another bundle ID.
  Existing installations need an explicit one-time app migration. Retain their
  working Mac update feed until that migration is prepared and tested.

## Theme-aware browsing, without surprise desktop changes

- The native Filters menu offers **Match Current Theme**, a season filter, and
  collection/name sorting. Search also finds photographer/source credits.
- Matching is an optional, in-memory browsing filter within the chosen collection.
  Changing the app theme never applies a wallpaper. Clear Filters restores the
  collection without changing favorites, the display target, or rotation.
- System suggests classic Mac artwork; Fall suggests autumn scenery; Halloween
  suggests pumpkins and darker landscapes; Christmas suggests festive/snowy
  scenes; neutral Winter excludes the decorated Christmas-tree photo; Easter
  suggests spring scenes.
- All Star Wars variants are covered: Jedi/Ahsoka/Yoda/Mace Windu suggest forests
  and space; Luke/Obi-Wan/Rey suggest desert landscapes; Dark Side/Vader/Maul
  suggest darker cosmic and desert scenes. These are mood suggestions, not licensed
  character artwork. No online Vader portrait or failed generated scene was added.
- **Preview and Credits** shows the full image composition with source/rights links.
  The discoverable **Surprise Preview** chooses a visible image locally and opens
  this preview only; it does not apply anything, play sounds, or run an effect loop.
- **Apply** remains explicit, and is unavailable if filters hide the selection.
  **Shuffle** is also an explicit apply action and respects the current visible
  filters, preferring their favorites. Rotation separately uses the selected
  collection/favorites, not temporary search/theme/season filters; its help states
  this distinction.
- Photo tiles stay on the content layer. Shared native Liquid Glass is restricted
  to controls, with the app's accent, reduced-transparency/motion and low-impact
  fallbacks. See [Apple's Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials).

## Curated source additions

Only URLs and attribution metadata are included in the app. Original images remain
with their sources; links and credits do not imply ownership or endorsement.

| Image | Photographer or official source |
| --- | --- |
| Cherry Blossom Overlook | [JinHui CHEN on Unsplash](https://unsplash.com/photos/61aBHL2sfhc) |
| Golden Hour Harvest | [Elijah Pilchard on Unsplash](https://unsplash.com/photos/0ZQG2WeU8KM) |
| Forest Jack-o'-Lantern | [Andrea Caramello on Unsplash](https://unsplash.com/photos/hPnP1HnNcWA) |
| Christmas in the Snow | [Alexander Lunyov on Unsplash](https://unsplash.com/photos/20u_wtTfnrI) |
| Arctic Forest Sunrise | [Harri P on Unsplash](https://unsplash.com/photos/L8p9qMMiCWs) |
| Cosmic Cliffs | [NASA, ESA, CSA, STScI](https://images.nasa.gov/details/carina_nebula) |
| Southern Ring — Two Views | [NASA, ESA, CSA, STScI](https://images.nasa.gov/details/southern_ring_nebula) |
| Andromeda in Ultraviolet | [NASA/JPL/California Institute of Technology](https://images.nasa.gov/details/PIA04921) |
| Blue Marble | [NASA/NOAA/GSFC/Suomi NPP/VIIRS/Norman Kuring](https://images.nasa.gov/details/GSFC_20171208_Archive_e001386) |

Photographs use the [Unsplash License](https://unsplash.com/license). NASA imagery
is subject to [NASA's media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)
and any image-specific third-party rights. Credits and links appear in the preview;
there is no claim that NASA endorses Notchscape. NASA asset URLs and credits were
read from its official per-image `collection.json` and `metadata.json` endpoints.
The app does not make live search/API requests or require NASA/Unsplash API keys.

Original dimensions vary: the two Webb images are about 2000 pixels wide, while
Andromeda and Blue Marble are 6200 and 8000 pixels square. The photographer images
include both landscape and portrait compositions. The preview shows the whole
composition; the system's desktop fit/cropping may differ by display aspect ratio.
No universal 4K/5K-resolution promise is made.

Three old entries were mislabeled as snowy winter scenes. Their visible names
are now Pine Forest Sunset, Green Rolling Hills, and Red Rock Desert Road, and
they no longer appear in winter matching. Their existing IDs and image URLs remain
unchanged, preserving saved favorites; they remain available in All.

## Safety and resource use

- Still images are downloaded on demand, not bundled as redistributed artwork.
  Respect the original archive/photographer terms; attribution is not a license.
- Full files come from catalog-pinned HTTPS sources. Archive previews use wsrv.nl
  for bounded thumbnails; Unsplash supplies resized previews directly; NASA images
  come only from the exact `images-assets.nasa.gov` HTTPS host.
- No arbitrary URL import, account cookies, telemetry, or background screen reads.
- Downloads are capped at 100 MB, previews at 12 MB; grid images are downsampled
  to 640 pixels and detail previews to 1600 pixels for Retina display. Both share
  a bounded 16 MB / 48-image cache.
- Reject path traversal, off-allowlist redirects, invalid/oversized images, and
  catalog payloads whose IDs or URLs do not match the bundled entry.
- Automatic rotation is off by default, minimum 30 minutes, and paused when locked
  or in Presentation/Travel Mode. A mode also cancels an in-flight automatic
  request; explicit Apply/Undo remains under the user's control.
  Prefer favorites in the chosen collection and avoid immediate repeats when possible.
- A disconnected selected display produces an error, not fallback onto another.
- Apply targets current desktops only, not every Space, lock screen, or screen saver.
  The in-session Undo restores captured previous desktop URLs/options.
- Original MacScapes must not run its own rotation concurrently. The integration
  deliberately does not silently change another app's settings.

## Utility tools

Settings → Tools → Utilities offers a Clean Link preview and Apple's native
NSColorSampler. Links never open or upload automatically. Known tracking parameters
are removed while functional query bytes and fragments are preserved. Signed URLs
are left intact. Pasting and copying are explicit actions; input/results are not
saved and clear when the tool view closes. Clipboard recording remains independent
and off unless the user enables it.

## Verification

Standalone policy tests: `tests/NotchUtilitiesPolicyTests.swift`.
Optional real network smoke test: `tests/WallpaperDownloadSmoke.swift`, compiled
with the wallpaper models/store and NSScreen+UUID.swift. `--download` validates a
real full-resolution file but never changes a desktop or enables rotation.

Native UI checks must separately cover search, favorites, empty states, selection,
theme/season filters, sort, preview/credits, Surprise Preview, display targeting,
Apply/Undo, color sampling, optional-tab overflow, reduced
transparency/motion, and low-impact mode. Build success does not establish a full
UI, physical-notch, real media-key, or Sparkle installation pass.

The October 2026 catalog check fetched all nine new images' grid preview, detail
preview, and original endpoints (27 HTTP-200/ImageIO-valid images). The largest
original was 17.22 MB and 64 megapixels, below the existing 100 MB/100 MP limits.
All 16 existing theme IDs produced nonempty suggestions across the complete
catalog, neutral Winter excluded the Christmas image, sorting round-tripped, and
all 328 IDs were unique. These network checks do not change any desktop.
