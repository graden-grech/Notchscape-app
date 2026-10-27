# MacScapes integration and update policy

## One combined Mac app

The wallpaper library is now an in-app page, not a second app or updater.
Notchscape retains its existing bundle identifier
`theboringteam.boringnotch`, app/helper signing requirements, signing team
`6H86CTRJCP`, and pinned Sparkle public key. Its only app update feed remains:

`https://raw.githubusercontent.com/graden-grech/Notchscape-app/main/appcast.xml`

New combined-app archives belong to releases in
`graden-grech/Notchscape-app`. Existing installations using the former repository's
feed continue to resolve through GitHub's compatibility routing; retain that
routing and all required old assets. See the [repository rename policy](UPDATES_AND_REPOSITORY_RENAME.md).
The imported wallpaper code includes neither
MacScapes' updater nor its analytics. Wallpaper image downloads are separate
from executable updates. The optional favorites import reads only the old
app's favorites; it does not change the old app or its preferences.

## Existing standalone MacScapes users

MacScapes uses a different bundle identity, `com.gradengrech.macscapes`. Do not
redirect its Sparkle feed to a Notchscape ZIP or pretend it is an ordinary
in-place update. Keep the old Mac feed and its last signed Mac artifacts
available until a deliberate migration is offered.

After a combined-app release is separately approved, signed, tested and
published, the safe migration is:

1. Explain that the wallpaper features moved into the combined app and offer
   its official release download. Do not send users to an older Boring Notch
   archive that does not contain the wallpaper page.
2. Install and open Notchscape once, using its own signing/update identity.
3. Offer the explicit **Import MacScapes Favorites** action in Wallpapers.
   Preserve the original app and settings so the user can go back.
4. Ask the user to turn off MacScapes' wallpaper rotation and launch-at-login
   if they are switching, avoiding competing wallpaper timers. Do not disable,
   quit, uninstall or erase the standalone app without their consent.
5. Future updates come through Notchscape's existing updater.

If a notice is delivered by an update to the old MacScapes app, it must remain
a genuine same-bundle MacScapes build, signed and packaged for that app's own
trust chain. That maintenance release requires separate authorization and
testing; it is not created by copying the combined app into the old feed.

## Release boundaries

The currently public Boring Notch release remains 2.8.4 (287); it does not yet
contain this local wallpaper integration. A source push alone does not publish
a new downloadable app or move the update feed. A future release must use a
new version/build, preserve previous feed items, pass the identity and public
feature gates, and separately verify download, signature, real update/relaunch
and HUD behavior. Never replace an already published archive.

The standalone Windows binaries are archived in the private
`graden-grech/macscapes-windows-private` repository. Their public update assets
are withdrawn, not redirected to the Mac app. No new Windows version is being
published as part of this integration.
