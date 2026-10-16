# Recipe changelog

This file records changes to the build recipe. RPM packaging history is kept in
[`packaging/obs/rstudio.changes`](packaging/obs/rstudio.changes); RStudio itself
has [upstream release notes](https://docs.posit.co/ide/news/).

## Unreleased

- Prepare the recipe for public collaboration: MIT licensing and REUSE metadata,
  contribution/security guidance, maintainership, issue templates, and CI.
- Document the current OBS home-project scope and work toward distribution review.
- Include the recipe license in future compilation-recipe archives.

## 2026-10-16

- Pin RStudio 2026.10.0+233 and retain the local `1.tw` packaging release.
- Remove the optional Copilot SDK Linux ARM64 bundle from x86_64 RPMs and cover
  both old and new native-bundle layouts in the packaging fixture.
- Validate the recovered RPM in a clean Tumbleweed container; desktop checks
  remain manual.

## 2026-10-15

- Build and validate RStudio from pinned source on Tumbleweed using Docker or Podman.
- Add Make targets and an offline OBS home-project repackaging workflow.
