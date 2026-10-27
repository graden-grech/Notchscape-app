# Custom fork automation

Normal macOS builds and CodeQL security checks remain enabled on pushes.
Normal builds use the supported `macos-26-intel` runner and Xcode 26, preserving
native Liquid Glass SDK and policy checks while avoiding the ARM runner pool's
observed allocation failures. The bundled MediaRemoteAdapter supports both Intel
and Apple silicon. Hosted Intel checks complement locally signed ARM builds;
neither replaces hardware/UI testing, and a runner change alone is not proof
that a new source revision has passed CI. The first new-source Intel run remains
to be verified after publication.

Optional upstream publishing jobs are not part of the custom fork's local,
signed-release process:

- **Nightly Branch Builds** only runs for the upstream repository or after
  `ENABLE_NIGHTLY_BUILDS=true` is explicitly configured. This fork has no `dev`
  branch or hosted signing secrets. Before enabling it, adapt the repository
  links and release-app configuration, create the intended branch, and configure
  signing, Sparkle, and release credentials. Do not enable it just to clear a
  skipped status.
- **Deploy static content to Pages** only runs for upstream or after
  `ENABLE_GITHUB_PAGES=true` is configured. Enable a GitHub Actions Pages site
  first. The custom appcast is served from raw GitHub and does not need Pages.
- **Manual Build** only runs for upstream or after
  `ENABLE_HOSTED_SIGNED_BUILDS=true` is configured. The custom fork has no hosted
  signing secrets; configure them and compare app/helper signing requirements
  against the trusted installed app before opting in. Unsigned CI builds must
  not replace the permission-approved app.
- **Hosted Notchscape Release (opt-in)** only runs for upstream or after
  `ENABLE_HOSTED_RELEASES=true` is configured. This inherited pipeline still has
  upstream download URLs and a Homebrew tap destination. Adapt those, its
  appcast destination, signing and release-app credentials before opting in.
  The custom fork continues to use its local signed-release process.
- The empty **Crowdin Sync** workflow was removed because a job with no steps
  is invalid. Translation files remain unchanged. Add a complete workflow if a
  translation service is configured later.

Dependabot targets the existing `main` branch for Swift updates. CodeQL action
updates are grouped so `init` and `analyze` move together: their generated
configuration is version-specific, and mixing versions fails analysis before
any security results can be uploaded. Normal build and security checks remain
enabled; the optional publishing guards do not suppress those checks.

A source push does not create a downloadable app release or advance Sparkle's
update feed. Those require a separately versioned, signed, verified archive.
