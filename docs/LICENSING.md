# Licensing and redistribution

## This repository

The original build scripts, packaging templates, tests, and documentation are
copyright 2026 Dario Castañé <cc@dario.cat> and provided under [MIT](../LICENSE).
`REUSE.toml` assigns SPDX license and copyright metadata to those files;
`LICENSES/MIT.txt` contains the license text for REUSE tooling.

This license covers the recipe. Downloading or packaging another project's
software does not change its license. Repository source archives contain the
recipe and documentation; large build inputs and generated packages stay
outside Git.

## RStudio and the package payload

RStudio's open source code is under AGPL-3.0-only, as recorded in the pinned
upstream `COPYING` file. The package's `License:` field describes RStudio; the
recipe's MIT license does not replace it. Other bundled components retain their
respective licenses and notices.

The build exports upstream `COPYING` and `NOTICE`, the tracked source and
submodules, the compilation recipe, checksums, and provenance beside the RPM.
The installed payload also retains RStudio's `resources/app/COPYING` and
`resources/app/NOTICE` and bundled component notices. Keep these with distributed
builds. Future build-recipe archives include this repository's MIT license and
REUSE metadata too.

When distributing binaries, review the exact build's license notices and provide
the corresponding source and build information required by those licenses.
Include any recipe patches used to recover or modify a package after compilation.
An archive of RStudio's tracked source alone does not contain all the third-party
sources or downloaded build tools: review those components separately. The OBS
repackaging SRPM carries the inputs uploaded by the maintainer; its existence
does not establish that all bundled software's corresponding source is present.

## Names and affiliation

RStudio and Posit names identify the software being packaged. openSUSE and SUSE
names identify the target platform and tools. This independent recipe does not
grant trademark rights or imply endorsement by those projects or companies.

## References

- [SPDX MIT license identifier and text](https://spdx.org/licenses/MIT.html).
- [REUSE specification](https://reuse.software/spec-3.3/).
- [Pinned RStudio COPYING](https://github.com/rstudio/rstudio/blob/v2026.10.0%2B233/COPYING).
- [Pinned RStudio NOTICE](https://github.com/rstudio/rstudio/blob/v2026.10.0%2B233/NOTICE).
