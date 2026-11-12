# Open-source notices and credits

Notchscape is maintained by Graden Grech. It is an independently maintained
derivative of [Boring Notch](https://github.com/TheBoredTeam/boring.notch), created
by the original project authors and contributors, including TheBoredTeam.
This edition is not an official TheBoredTeam release and is not endorsed by
Apple or by the original project authors.

The original source copyright notices are preserved in the source files.
The [GNU General Public License v3](../LICENSE) and
[third-party license notices](../THIRD_PARTY_LICENSES) remain in force. A new
product name or Git history does not transfer or erase the original authorship.

Credits preserved from the original README include:

- [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter), for
  macOS Now Playing integration.
- [NotchDrop](https://github.com/Lakr233/NotchDrop), an important basis for the
  first Shelf implementation.
- [maxtron95](https://github.com/maxtron95), original-project icon credit.
- [himanshhhhuv](https://github.com/himanshhhhuv), original-project website credit.

The optional Face Unlock preview uses the official OpenCV Zoo SFace model under
Apache 2.0, contributed by Yaoyao Zhong with the original ONNX conversion credited
to Chengrui Wang. Notchscape independently converted it to Core ML; it does not
include InsightFace code, history or weights. Camera-preview hosting now adapts
small MIT-licensed components from [Glance](https://github.com/DesusLove/Glance)
and [FaceUnlock](https://github.com/HasBrain/FaceUnlock); their model weights and
password-injection code are not included. Full notices are bundled in
`Notchscape/Resources/FacePreviewNotices.txt`. The pinned provenance,
unchanged source license and conversion notice are bundled in
`Notchscape/Resources/FaceModels`. See [the model notice](../Notchscape/Resources/FaceModels/MODEL_NOTICE.md)
and [the full license](../Notchscape/Resources/FaceModels/LICENSE).

The current seasonal and Star Wars scene assets have their own provenance and
limitations in the adjacent asset documentation. In particular, no generated
Vader character scene is supplied: the rejected online substitute was removed.
Wallpaper artwork is downloaded from its catalog sources and is not claimed as
original Notchscape artwork. Artwork and provider rights need review before
commercial distribution.

Some internal compatibility identifiers and the existing Apple Notes folder
retain the former name to avoid resetting permissions, losing settings, breaking
existing sync mappings or invalidating signed updates. These are migration
boundaries, not the product's public brand.
