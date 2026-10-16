# Packaging policy

## Supported workflow

This independent recipe targets Tumbleweed x86_64. Docker/Podman compiles pinned
RStudio source using upstream's dependency downloads. The OBS home-project route
repackages that compiled RPM without network access on the worker. Both paths
keep upstream's application layout and scriptlets and regenerate ELF dependency
metadata. The [README](../README.md) and [OBS guide](OBS.md) contain the commands.

The recipe follows openSUSE conventions where they fit this workflow: SPDX
license identifiers, a separate `.changes` file, OBS-managed release counters,
an explicit architecture, clean-environment checks, and published repository
signatures. Source preparation retains input checksums and provenance. The
project metadata template assigns both a maintainer and bugowner.

## Review with ecosystem tools

Install the standard tools on your development host:

```bash
sudo zypper install osc build rpm-build rpmlint spec-cleaner
```

After `make obs-prepare`, review a temporary copy of the generated spec with
`spec-cleaner`. Keep the version placeholders in `packaging/obs/rstudio.spec.in`:

```bash
review_dir=$(mktemp -d)
cp "$OBS_DIR/rstudio.spec" "$review_dir/rstudio.spec"
spec-cleaner -i "$review_dir/rstudio.spec"
diff -u "$OBS_DIR/rstudio.spec" "$review_dir/rstudio.spec"
rm -rf -- "$review_dir"
```

`diff` returns 1 when it finds changes; review those changes and apply the
appropriate ones to the template. Run `rpmlint` on the generated spec and,
after a clean OBS build, on both resulting RPMs:

```bash
rpmlint "$OBS_DIR/rstudio.spec"
rpmlint /path/to/rstudio.src.rpm /path/to/rstudio.x86_64.rpm
```

A recipe test passing does not replace these tools or the worker's build checks.
Retain the findings with the release validation. Correct each issue or document
why it follows from the current payload-reuse design. This repository supplies
no blanket `rpmlintrc` suppressions.

## Changes needed for distribution inclusion

The current home-project recipe is not a Factory submission. Before proposing
inclusion through a suitable devel project, arrange with its maintainers to:

1. Build RStudio and its required components from source inside OBS, with build
   dependencies and sources available offline. Replace downloading npm and
   tool installers during the build with reviewed source inputs or packages.
2. Review bundled libraries, Electron/Node tools, and their licensing with the
   devel project. Prefer distribution dependencies where supported and record
   the source of unavoidable bundles.
3. Replace the current binary-preservation overrides with normal distribution
   build checks and debug information. Review the upstream `/usr/lib/rstudio`
   layout, launcher, sandbox permissions, desktop integration, and scriptlets
   against the target project's policies.
4. Install and mark license texts with `%license`, complete the corresponding
   source review, resolve `rpmlint`/worker findings, and test upgrades and removal.
5. Use OBS review and submit requests after the devel-project build is accepted.
   Keep release counters managed by OBS and changelog entries in `.changes`.

This is the path toward distribution review; it is not a claim of acceptance
or a reason to rename a home project as an official openSUSE package.

## References

- [SUSE introduction to RPM packaging](https://documentation.suse.com/sbp/systems-management/html/SBP-RPM-Packaging/index.html): automatic dependencies, build checks, and `.changes`.
- [OBS basic workflow](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-basicworkflow): projects and package review.
- [OBS source services](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-source-services): worker network restrictions.
- [spec-cleaner](https://github.com/rpm-software-management/spec-cleaner): spec formatting and openSUSE style.
- [rpmlint](https://github.com/rpm-software-management/rpmlint): spec, binary, and source RPM checks.
- [openSUSE specfile guidelines](https://en.opensuse.org/openSUSE:Specfile_guidelines) and [packaging guidelines](https://en.opensuse.org/openSUSE:Packaging_guidelines): target-project review references.
