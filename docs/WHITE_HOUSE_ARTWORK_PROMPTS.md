# White House artwork prompt set

Verbatim prompt text from the built-in `image_gen.imagegen` calls. The six
generated output paths, edit targets, transparency options, and consumed asset
paths are recorded in [WHITE_HOUSE_THEME.md](WHITE_HOUSE_THEME.md).

For each of the four scene calls, the exact prompt argument is the common prefix
below, followed by **one ASCII space**, followed by the corresponding suffix.
The code blocks omit that trailing prefix space to avoid an invisible formatting
dependency. Both icon prompts were standalone strings, not appended to the
scene prefix. All six calls used the built-in tool; no external API or image
CLI was used. Original generated PNGs were retained.

## Common scene prefix

```text
Use case: photorealistic-natural. Asset type: premium architectural background artwork for the expanded Home panel of a dark macOS productivity app. Create one unified full-bleed landscape photograph-like decorative architectural illustration, not a UI mockup. Wide 16:9 composition. Natural believable materials, plausible architecture, refined restrained white, warm limestone, muted navy, and subtle gold palette. Aim for real architectural photography rather than CGI: real stone grain, fabric, wood, nuanced bounced light, subtle everyday material variation. Important recognizable scene detail sits mainly in the right half and within the central horizontal band, allowing a wide shallow crop. Left and center remain calmer and darker with low detail for a foreground calendar and music controls that will be added separately. Quiet dark top navigation zone, no harsh white highlights there. No people, politicians, portraits of real people, text, signage, campaign symbols, party emblems, official presidential seal, flags, watermark, logos, embedded UI, screens, borders, split panels, card, vignette frame, or extra foreground objects. This is an independently imagined White House-inspired architectural scene, not a claim about any current administration's actual decoration.
```

## Exterior suffix

```text
Scene/backdrop: the recognizable north exterior of the White House at peaceful blue hour, viewed from a modest three-quarter angle over the lawn. The warmly illuminated pale limestone facade and iconic classical portico sit right-of-center, evenly spaced windows and coherent columns, midnight-blue sky, distant mature trees softly silhouetted. A broad darker lawn and natural shadows make the left foreground calm; building readable, not tiny, its complete portico within the middle horizontal crop. Elegant restrained real exposure, no excessive bloom, no snow, no dramatic storm.
```

## Oval Office suffix

```text
Scene/backdrop: an unoccupied classic Oval Office-inspired oval room viewed from one side, with tall gracefully arched windows, cream curtains, pale curved walls, warm parquet, a restrained muted navy rug without a seal or writing. A handsome polished walnut executive desk sits on the right, natural small warm table-lamp illumination and soft dusk daylight. No clutter, no papers, no nameplate. The curved wall, window rhythm, desk, and high-quality real fabric make the room recognizable. Quiet darker wall and a low-detail corner toward left/center, refined evening room photography with realistic perspective, not wide-angle distortion.
```

## East Room suffix

```text
Scene/backdrop: an unoccupied White House East Room-inspired grand ceremonial room, luminous but restrained ivory-and-gold neoclassical interiors, tall cream walls with elegant molding, warm parquet floor, tall windows and simple pale gold curtains, refined crystal chandeliers concentrated to the right. Balanced classical wall proportions and straight verticals, no stage, portraits, lectern, chairs, banquet tables, emblems, or banners. Camera from a corner leaves a calmer dimmer expanse at left/center; recognizable grand architectural details on right. Soft warm evening bounce light and a subtle cool window tint, believable luxury architectural photograph, never a gaudy palace fantasy.
```

## Blue Room suffix

```text
Scene/backdrop: an unoccupied White House Blue Room-inspired oval reception room. Muted deep navy-blue silk walls, cream classical trim and gold accents, tall windows with understated ivory curtains, finely woven pale patterned rug without a seal, one graceful cream-and-gold settee and small refined table set toward right. Coherent oval geometry, authentic-looking period joinery and fabric, no portraits, no clutter or excessive ornaments. Camera from one side, subdued blue wall and soft shadow left/center for foreground controls; right half has the recognizable room details. Warm late-evening lamp glow and gentle blue window light, sophisticated natural interior photography, not theatrical or over-saturated.
```

## Original icon v1 edit

```text
Use case: precise-object-edit. Asset type: optional 1024-style macOS app icon theme variant. Input image 1 is the edit target and exact brand identity reference: the Notchscape rounded-square glass icon with its distinctive broad black pill/notch cutout. Create a premium restrained White House-inspired variant of THIS SAME ICON, not a new unrelated logo. Preserve the outer rounded-square silhouette, strong balanced icon padding, complete transparent outside background, and especially the exact broad black central pill with its smooth shallow top-center notch shape. Retain elegant high-quality physical glass/metal edges with clean natural specular highlights and no pixelated sparkle. Change the silver-blue/purple palette to subtle warm limestone ivory and midnight navy with fine champagne-gold edge highlights, no purple/cyan glow. The face can have a faint tasteful classical-limestone architectural material, like a gentle portico-column reflection in the upper glass area, subordinate to the black Notchscape mark, not a detailed illustration or prominent second logo. Authentic fine stone/metal/glass texture but simple legible at small size. Independently imagined app branding, no official seal, crest, flag, eagle, government logo, presidential faces, party marks, text, signage, watermark, badge, added border, extra objects, or opaque rectangular canvas outside the rounded icon. True alpha around rounded icon, no baked shadow rectangle. Keep only the existing icon and change its finish and restrained material accents.
```

## Targeted transparent-edge icon v2 cleanup

```text
Use case: precise-object-edit. Input image 1 is the edit target. ONE TARGETED CLEANUP ONLY: remove isolated red, green, yellow and blue fringe speckles or stray pixels outside the rounded-square icon silhouette, especially just above the top edge and around the exterior bottom-left outline. Every pixel outside the clean continuous rounded-square silhouette must be truly fully transparent, with at most a clean neutral antialiased silhouette edge, no colored alpha fringe, no extra glow blobs or floating dots. Retain the EXACT same icon inside that silhouette: identical central broad black Notchscape pill/notch shape and position, champagne-gold glass rim, limestone/ivory upper face with soft classical-column reflection, midnight-navy lower finish, corner curvature, lighting, material detail, overall proportions and existing padding. Do not redesign, repaint, recolor, add objects, change the mark, alter the limestone/navy/gold palette, add text or a border, or introduce an opaque canvas or checkered background. Keep genuine alpha transparency outside the cleaned icon.
```
