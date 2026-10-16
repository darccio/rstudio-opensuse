# RStudio Desktop for openSUSE Tumbleweed

Build RStudio Desktop from the upstream source tree and produce an x86_64 RPM.
The recipe targets [RStudio 2026.10.0+233](https://dailies.rstudio.com/version/2026.10.0%2B233/),
tag `v2026.10.0+233`, commit `e961c6137d92315437caf5af53959f7110b517f9`.

**Status: 2026.10.0+233 compilation, RPM generation, and metadata checks passed.**
The recovered RPM contains 33 ELF files, all x86_64. Clean-container installation
passed, including library checks for 26 dynamic ELF files. GUI testing remains
manual. A clean OBS build and remote publication have not been validated.

The release pins live in [`release.env`](release.env). This repository supports
local builds and installation, plus [publishing through Open Build Service
(OBS)](docs/OBS.md). OBS packaging reuses the locally compiled payload; RStudio
compilation continues to use the existing Docker/Podman workflow.

This is an independent community project. The recipe and documentation are
[MIT licensed](LICENSE); RStudio and bundled components retain their own
[licenses](docs/LICENSING.md). See [contributing](CONTRIBUTING.md),
[maintainers](MAINTAINERS.md), [security reporting](SECURITY.md), and the
[packaging policy](docs/PACKAGING.md) for review and distribution conventions.

## Build, validate, and install

Run the following commands from the repository root in the same Bash session.

Run as a regular user on a machine with Docker access or rootless Podman and
network access to GitHub, openSUSE repositories, npm, and upstream dependency
download hosts. Allow roughly 40 GB of free disk and 16 GB of available RAM;
the actual requirements depend on concurrency and upstream dependencies. GNU
Make, Bash, Python 3, RPM tools, and a working container engine are needed on the
host. Full offline fixture coverage also needs host CMake, Ninja, GCC, CPack,
and rpmbuild; tests requiring missing tools are reported as skipped.

### 1. Select the release and output directories

Keep the existing pins, or follow [Updating the version](#updating-the-version)
first. Use separate output directories to retain previous builds:

```bash
source ./release.env
export CONTAINER_ENGINE=docker
export WORK_DIR="$PWD/work/${RSTUDIO_TAG#v}"
export OUTPUT_DIR="$PWD/artifacts/${RSTUDIO_TAG#v}-${RPM_RELEASE}"
RSTUDIO_RPM="$OUTPUT_DIR/rstudio-${RSTUDIO_TAG#v}-${RPM_RELEASE}.x86_64.rpm"
```

Use `CONTAINER_ENGINE=podman` for rootless Podman. `./build.sh doctor` can report
tools, network access, and container access. It also lists native build tools;
missing host R or Ant does not prevent the container from providing them.

### 2. Build

```bash
make test
make build
```

`make build` invokes `./build.sh build`. It compiles RStudio, checks the RPM, and
installs it into a disposable Tumbleweed container to verify the launcher, R,
ELF architectures, and shared libraries. A successful build already includes
these container checks. The host installation happens in step 4.

The default concurrency is four jobs. For a new build of the same release,
choose a fresh output directory if the existing one contains `SUCCESS`:

```bash
make build JOBS=2 OUTPUT_DIR="$PWD/artifacts/rebuild"
```

When overriding `OUTPUT_DIR` for one command, use that same directory for the
validation and installation steps below, and update `RSTUDIO_RPM` accordingly.

### 3. Validate an existing RPM

Check the recorded checksums in their output directory:

```bash
(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
```

To rerun recipe tests and container verification without compiling again:

```bash
make validate RPM="$RSTUDIO_RPM"
```

Without `RPM=`, `make validate` requires exactly one RPM directly in
`OUTPUT_DIR`. The selected RPM must match the current pins in `release.env`.

For a metadata-only check, use `./build.sh check "$RSTUDIO_RPM"`.

`SUCCESS` records compilation and RPM metadata success. A `*.rpm.VERIFIED`
marker and `*.rpm.verify.log` record successful clean-container installation
and library checks. GUI testing is a separate step.

### 4. Install on your desktop

Install the same RPM you validated, from your normal host terminal:

```bash
sudo zypper install --allow-unsigned-rpm "$RSTUDIO_RPM"
command -v rstudio
rstudio
```

Zypper installs the runtime dependencies and runs the upstream postinstall
script, which creates `/usr/bin/rstudio`. The desktop entry is installed at
`/usr/share/applications/rstudio.desktop`; search for **RStudio** in your
application menu. Launch it as your regular user.

`make validate` and `./build.sh verify` install into temporary containers that
are removed afterward. Their success does not install an application on your
desktop or put `rstudio` on your host's `PATH`.

In RStudio, check that the R console evaluates `1 + 1`, plots render, projects
reopen, and the visual editor/Quarto work.

### 5. Publish or clean up

To make the package installable and updatable from a repository, follow
[the OBS workflow](docs/OBS.md). To remove local generated files after saving
anything you want to retain:

```bash
make clean
```

Cleanup deletes the configured `WORK_DIR`, `OUTPUT_DIR`, `OBS_DIR` (default:
`WORK_DIR/obs`), and Python caches. This includes RPMs, source archives, logs,
and prepared OBS inputs under those directories. It refuses the repository
directory and its parents. Container images and their dependency cache are
retained for future builds.

## Make targets and configuration

| Command | Action |
| --- | --- |
| `make` or `make build` | Invoke `./build.sh build`, including container verification. |
| `make validate` | Run recipe tests, then verify the single RPM directly in `OUTPUT_DIR` in a clean container. |
| `make test` | Run the offline recipe tests through `./build.sh test`. |
| `make lint` | Check source licensing with REUSE. |
| `make check` | Run licensing checks and offline recipe tests. |
| `make obs-prepare` | Prepare offline OBS inputs from a verified RPM. |
| `make obs-build` | Build the prepared package with `osc` for Tumbleweed x86_64. |
| `make obs-validate RPM=...` | Run tests and verify an OBS-produced RPM, allowing OBS release counters. |
| `make clean` | Delete configured work/output/OBS directories and Python caches. |
| `make help` | Show targets and configuration variables. |

The Makefile accepts the same environment variables as `build.sh`; they can also
be set on the Make command line. Defaults are `JOBS=4`, `WORK_DIR=work`,
`OUTPUT_DIR=artifacts`, and `OBS_DIR=WORK_DIR/obs`. `CONTAINER_ENGINE` selects
Docker or Podman, and `RPM` selects an existing package for validation or OBS
preparation. See [OBS configuration](docs/OBS.md) for archive overrides.

The default base image is `registry.opensuse.org/opensuse/tumbleweed:latest`.
Set `BASE_IMAGE=...@sha256:...` to pin it. Tumbleweed repositories and some
upstream downloads still move; provenance is recorded, but builds are not
guaranteed to be bit-for-bit reproducible.

## Build implementation

`build` creates a Tumbleweed build image, fetches and verifies the source revision
and submodules, runs the release's dependency installer, and compiles RStudio as
an unprivileged user with the upstream `make-package Electron RPM` script.
CPack then generates the RPM using the settings in `packaging/tumbleweed.cmake`.
This follows [upstream's build instructions](https://github.com/rstudio/rstudio/blob/main/INSTALL)
and its [Linux packaging script](https://github.com/rstudio/rstudio/blob/v2026.10.0%2B233/package/linux/make-package).

The release's SUSE installer requests `libpq-devel`, `libsqlite-devel`, and
`mesa-devel`. A temporary copy translates those names to Tumbleweed's
`postgresql-devel`, `sqlite3-devel`, and `Mesa-devel`; tracked upstream files
stay clean. Literal upstream package requests are checked together with a
Zypper dry run before running the installer, so missing names are reported
together. Shell expressions, if present, are reported as not preflighted.
Source fetching, system-package installation, and upstream dependency setup use
separate Docker layers, so a failure in upstream setup can reuse the completed
system-package installation on the next run.

During compilation, the recipe uses GYP's `PRODUCT_DIR` for the desktop and dock
native addon copy inputs. This lets a clean Make build resolve their generated
targets. The original `binding.gyp` is restored when packaging exits; the source
archive retains the upstream file, and the build recipe records the correction.

The RPM requires R and uses openSUSE package names. Automatic ELF dependency
discovery is enabled so missing runtime libraries are visible to the package
manager. Upstream layout and install/uninstall scriptlets are retained. The
postinstall script creates `/usr/bin/rstudio`; this launcher is checked after
installation. Copilot's optional ARM64 Linux tools, including the
`@github/copilot-sdk-linux-arm64` bundle, are omitted from the staged x86_64
package so they cannot add ARM64 runtime requirements. The result is a
local unsigned package, not an openSUSE Factory submission.

After building, the driver installs the RPM into a separate clean Tumbleweed
container and checks the installed ELF files for missing libraries. Repository
signature checks remain enabled; only the locally built RPM is allowed unsigned.
The driver never installs RStudio on the host. A failure at any stage returns a
nonzero exit status and preserves logs.

CMake 4's removed pre-3.5 compatibility is handled with
`CMAKE_POLICY_VERSION_MINIMUM=3.5`.

## Build outputs

The output directory contains the binary RPM, source archive (including tracked
submodule files), build recipe, license/notice, package inventories, logs,
provenance, and `SHA256SUMS`. The recipe archive includes this project's license
and REUSE metadata. The default RPM name is
`rstudio-2026.10.0+233-1.tw.x86_64.rpm`.

Keep the RPM with its source archive, compilation recipe, notices, and
provenance when redistributing it. Logs are preserved on failure. To repeat a
failed verification, use `make validate RPM=...`; a failed verification removes
the old verification marker once the verifier reaches the package-check step.

## Updating the version

[`release.env`](release.env) is the configuration source for the version:

| Variable | Meaning |
| --- | --- |
| `RSTUDIO_TAG` | Upstream release tag, such as `v2026.10.0+233`. |
| `RSTUDIO_COMMIT` | Full 40-character commit hash to which that tag resolves. |
| `RPM_RELEASE` | Local packaging revision: start at `1.tw` for a new upstream version; increment it for packaging-only rebuilds. |

Edit `RSTUDIO_TAG` to the desired upstream tag. Look up the matching revision:

```bash
source ./release.env
git ls-remote https://github.com/rstudio/rstudio.git \
  "refs/tags/$RSTUDIO_TAG" "refs/tags/$RSTUDIO_TAG^{}"
```

For an annotated tag, use the hash on the `^{}` line; otherwise use the hash
on the tag line. Save it as `RSTUDIO_COMMIT`, set `RPM_RELEASE`, and update the
release link in the file's comment. The scripts derive the version from the
tag by removing its leading `v` and reject a tag/commit mismatch.

Then repeat steps 1–4 above with fresh output directories. For native builds,
use a new `WORK_DIR` too: the fetcher refuses an existing checkout for a
different pin. The RPM tests now read the version/release from `release.env`,
so test fixture version strings need no manual updates. Review compatibility
changes if upstream build files have changed; the native addon helper reports
an unexpected GYP layout rather than modifying an unknown rule.

For OBS releases, update `packaging/obs/rstudio.changes`, regenerate the prepared
inputs from the newly built and verified RPM, and publish a new OBS source
revision. OBS manages its own RPM release counters.

## Native build

The container route isolates dependency installation. If you intentionally want
to prepare your Tumbleweed host instead, the following dependency step installs
system packages and upstream build tools under `/opt/rstudio-tools` and/or the
source tree. Set the variables from step 1 before running these commands:

```bash
./build.sh fetch
sudo bash scripts/install-dependencies.sh "$WORK_DIR/rstudio"
./build.sh native
./build.sh verify "$RSTUDIO_RPM"
```

The native build requires a clean pinned checkout and does not elevate itself.
After a failed source fetch the temporary checkout is removed so a retry works.
Native build outputs can be reused while fixing a failure; completed builds need
a new `OUTPUT_DIR`. The container image caches dependencies, but the temporary
compile container is removed after each run, so container compilation restarts
on a retry.

RStudio's C++ backend, web frontend, and Electron application code are compiled
from source. Like upstream's standard build, this uses distribution packages and
downloads third-party components such as Electron, Node, Quarto, and Pandoc.
It does not compile those projects or the Linux toolchain from source. The
source archive is not a standalone offline SRPM: rebuilding also needs the
recorded upstream dependencies and distribution packages.

## Recipe checks

```bash
./build.sh test
```

These offline checks exercise argument/error handling and build a tiny C fixture
through CPack/rpmbuild to check RPM policy, ELF dependency discovery, Copilot
architecture filtering, and the postinstall launcher. The same fixture goes
through OBS preparation and real binary/source RPM builds, checks the payload
and scriptlets, and exercises verification/provenance failure cases. They do not
compile RStudio. When node-gyp is available, they also reproduce the native
addon copy failure with a small GYP fixture and check the corrected Make build.
Fixtures are created in temporary directories and never installed. Python 3,
CMake, Ninja, GCC, CPack and rpmbuild are needed.

GitHub CI runs the recipe checks in Tumbleweed without publishing credentials.
It does not run a full RStudio build or upload to OBS. Run `make check` for the
same fixture and licensing checks locally; see [CONTRIBUTING.md](CONTRIBUTING.md)
for dependencies and [CHANGELOG.md](CHANGELOG.md) for recipe changes.
