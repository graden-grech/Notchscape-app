# Contributing to Notchscape

Graden Grech maintains this edition. Open issues and pull requests against
`graden-grech/Notchscape-app`, using `main` as the base branch. There is no
active `dev` branch or automatic Crowdin setup in this repository.

Before a major feature, open an issue describing the user need and how it fits
the shared Home, Tools, Wallpapers or Settings experience. Keep native macOS
controls, consistent spacing and clear disabled/error states. Include screenshots
for visual changes and note any untested hardware or permissions.

For code changes, use a feature branch, preserve existing preferences and data,
and add proportionate tests. Run:

```sh
python3 -m unittest discover -s .github/scripts/tests -q
git diff --check
```

Read [AGENTS.md](AGENTS.md) before building or packaging. App identity, signing,
the update key, installed path and helper requirements must remain compatible;
do not clear macOS permissions to hide a regression. The
[HUD release checks](docs/HUD_RELEASE_CHECKS.md) require real runtime testing,
not just a successful compile. Ordinary source changes do not authorize a
public release or replacement of existing release assets.

Translation changes can be submitted as pull requests with the relevant locale
and source string identified. Do not submit them to the former upstream
translation service on this project's behalf.

Bug reports should include the app version/build, macOS version, chip, display
setup, steps to reproduce, expected behavior, and relevant screenshots. Remove
personal notes, clipboard content, tokens and other credentials from reports.

Preserve GPL and third-party copyright/license notices. New branding and a
fresh development history do not change the original source's authorship. See
[attribution](docs/ATTRIBUTION.md) and [LICENSE](LICENSE).
