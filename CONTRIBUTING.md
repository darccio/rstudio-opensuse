# Contributing

Build fixes, packaging improvements, documentation, and reproducible bug reports
are welcome. Follow our [code of conduct](CODE_OF_CONDUCT.md).

## Scope and setup

The supported target is openSUSE Tumbleweed x86_64. The [README](README.md)
describes compilation, validation, and host installation. The [OBS guide](docs/OBS.md)
describes the separate home-project publishing route.

On Tumbleweed, the recipe tests and license check need:

```bash
sudo zypper install make gcc gcc-c++ cmake ninja rpm-build cpio tar gzip \
  /usr/bin/python3 /usr/bin/node /usr/bin/npm /usr/bin/reuse
make check
```

`make check` runs REUSE licensing checks and the offline fixtures. Test dependencies
must be installed for the CPack/RPM and GYP cases to execute. Read the test summary:
a skipped test does not establish that the corresponding behavior works.
The tests build small fixtures and do not install packages on the host.

## Reporting problems

Include the release pin, Tumbleweed snapshot, architecture, container engine,
command, and the end of the failing log. State whether the failure is in source
fetching, dependency setup, compilation, RPM creation, container verification,
or desktop use. For runtime problems include the R version and desktop session
(for example, Plasma on Wayland).

Attach the relevant `build.log`, RPM `*.requires.txt`, `*.files.txt`, or
`*.verify.log` after removing credentials, private paths, and project data.
Use [SECURITY.md](SECURITY.md) for vulnerabilities. RStudio application bugs that
also occur with Posit's packages belong in the
[upstream tracker](https://github.com/rstudio/rstudio/issues).

## Changes and review

Keep a change focused, explain its effect, and describe how it was checked.
Add a regression fixture for a build or packaging bug. Preserve support for
both Docker and Podman, the pinned upstream checkout, automatic RPM dependency
discovery, and the separation between validation and host installation.

Use four spaces in Python and shell code, two spaces in CMake/XML/YAML, and tabs
in Make recipes. Python helpers use the standard library. Keep generated RPMs,
downloaded sources, logs, credentials, and OBS checkouts outside Git. Extend
`.gitignore` when introducing new generated outputs.

For version changes, update `release.env` with the tag and matching full commit,
reset the local RPM release to `1.tw`, and use fresh output directories. Increment
`RPM_RELEASE` for a published packaging-only rebuild. Update
`packaging/obs/rstudio.changes` for package changes; openSUSE uses `.changes`
files alongside the spec. `osc vc` can create entries in an OBS checkout; carry
the entry back to this repository before regenerating inputs. Update
[CHANGELOG.md](CHANGELOG.md) for changes to the recipe's public workflow.

Run `make check` before submitting. For packaging changes also build a real RPM
and run `make validate RPM=...`; OBS output needs `make obs-validate RPM=...`.
Include the clean-container result and relevant manual desktop checks. Review
the generated spec with `spec-cleaner` and the binary/source RPMs with `rpmlint`
as described in the [packaging policy](docs/PACKAGING.md). Do not add broad lint
filters to hide findings.

GitHub CI runs the fixtures in Tumbleweed and checks license metadata. It does
not compile RStudio or publish packages. Full builds and OBS uploads remain
explicit maintainer actions. Contributors can run the same checks locally
without a GitHub account or OBS credentials.

## Licensing contributions

Original contributions to the recipe and documentation use the [MIT license](LICENSE).
Preserve attribution and license notices when adapting third-party material;
record any different terms in `REUSE.toml` or SPDX headers and supply the license
text under `LICENSES/`. Do not apply this repository's MIT license to RStudio or
its dependencies. See [licensing and redistribution](docs/LICENSING.md).

## Maintainer contact

Contact [cc@dario.cat](mailto:cc@dario.cat) for project questions or repository
access. Keep technical discussions in the issue tracker when possible so other
contributors can follow them.
