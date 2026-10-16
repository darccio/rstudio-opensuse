# Publishing RStudio with openSUSE Build Service

Open Build Service (OBS) builds packages from uploaded inputs and publishes a
repository that Zypper can use. This repository targets a personal OBS project,
such as `home:YOUR_USERNAME:rstudio`, with an `openSUSE_Tumbleweed` repository
for `x86_64`.

The existing Docker/Podman workflow compiles RStudio from its pinned upstream
source. The OBS route packages that compiled payload offline. It carries the
upstream source archive, original compilation recipe, and provenance as source
RPM inputs. **OBS does not recompile RStudio in this workflow.** This distinction
matters on Tumbleweed: regenerate the Docker build when updating RStudio or
when a runtime ABI change requires recompilation. Building RStudio itself on
OBS would require an offline dependency bundle or separately packaged build
dependencies; the current upstream installer downloads tools and npm packages.

OBS secure workers have no external network access. The generated spec uses
local `Source` files, checks their hashes, extracts the compiled RPM payload,
and lets RPM regenerate dependency metadata. The package retains the original
file attributes and install/uninstall scripts. This is a home-project binary
repackaging route, not a Factory submission or an OBS source-compilation recipe.
See the [packaging policy](PACKAGING.md) for `spec-cleaner`, `rpmlint`, and the
changes needed before distribution review, and [licensing](LICENSING.md) for
the distinction between recipe and payload licenses.

## 1. Build and validate locally

Follow the [README workflow](../README.md#build-validate-and-install). The RPM
must have a current `*.rpm.VERIFIED` marker from clean-container validation.

Use the release variables and RPM path from that workflow:

```bash
export CONTAINER_ENGINE=docker
make validate RPM="$RSTUDIO_RPM"
```

Host tools for source preparation are Bash, Python 3, RPM, and `rpmspec` (from
`rpm-build`). Install the OBS client/build tools before a clean local OBS build:

```bash
sudo zypper install osc build rpm-build
```

Create an account at [build.opensuse.org](https://build.opensuse.org/) and
configure `osc` following its [official setup
instructions](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-osc).
Keep credentials in the client configuration, outside Git.

## 2. Prepare the OBS inputs

From the repository root, choose a fresh directory and prepare a verified RPM:

```bash
export OBS_DIR="$WORK_DIR/obs"
make obs-prepare RPM="$RSTUDIO_RPM"
```

Without `RPM=`, the preparer requires one RPM directly in `OUTPUT_DIR`. It
checks the local package identity, verification marker, source archive, and
recorded release/commit before preparing inputs. An existing `OBS_DIR` is
refused; choose another directory for a new preparation.

Companion archives are found beside the RPM or one directory above it. They
can be specified explicitly with Make/environment overrides:

```bash
make obs-prepare RPM="$RSTUDIO_RPM" \
  SOURCE_ARCHIVE="$OUTPUT_DIR/rstudio-${RSTUDIO_TAG#v}-source.tar.gz" \
  RECIPE_ARCHIVE="$OUTPUT_DIR/build-recipe.tar.gz" \
  PROVENANCE="$OUTPUT_DIR/provenance.txt"
```

`RECIPE_ARCHIVE` is the recipe saved with the compilation, rather than a new
snapshot of the working directory. Prepared files include:

| File | Role |
| --- | --- |
| `rstudio.spec`, `rstudio.changes`, `_constraints` | RPM recipe, changelog, and worker requirements. |
| `rstudio-*.x86_64.rpm` | Locally compiled and validated input payload. |
| `rstudio-*-source.tar.gz` | Pinned upstream source, including tracked submodule files. |
| `rstudio-build-recipe.tar.gz`, `build-provenance.txt` | Original compilation recipe and environment record. |
| `postinstall.sh`, `postuninstall.sh`, `rstudio.files` | Original scriptlets and file attributes extracted from the input RPM. |
| `SHA256SUMS` | Hashes of the packaging inputs, checked in `%prep`. |

These generated/downloaded inputs belong in `work/` or `artifacts/`, which Git
ignores. They must be uploaded to OBS for its worker and source RPM to have
the inputs; excluding them from Git does not exclude them from the OBS upload.

## 3. Validate with a clean local OBS build

```bash
make test
make obs-build
```

`make obs-build` invokes:

```bash
cd "$OBS_DIR"
osc build --local-package --alternative-project openSUSE:Tumbleweed \
  standard x86_64 rstudio.spec
```

The explicit alternative project lets a prepared directory build before it has
an OBS checkout. `standard` is the repository of `openSUSE:Tumbleweed`; the
home project later names its repository `openSUSE_Tumbleweed`.

`osc` downloads distribution build dependencies and builds in an isolated target
environment. The local builder may request root privileges to create its build
root. Use the paths printed by `osc` to find the resulting binary and source
RPMs. `osc localbuildlog` shows the local build log.

From the repository root, validate the resulting binary RPM:

```bash
make obs-validate RPM=/path/printed/by/osc/rstudio-VERSION-RELEASE.x86_64.rpm
```

OBS supplies the RPM `Release` counters, so OBS output uses
`./build.sh check-obs` / `./build.sh verify-obs`. The package name, architecture,
upstream version, desktop layout, launcher mechanism, and dependency checks
remain enforced. `make obs-validate` runs the recipe tests and clean-container
installation check. A local `rpmbuild -ba` can check the recipe on the host, but
does not establish that an isolated OBS build or remote publishing succeeded.

## 4. Create the home project and upload

Set up a home subproject with the OBS Web UI. Use
[`project.xml.example`](../packaging/obs/project.xml.example) as a reference:
replace both `YOUR_USERNAME` placeholders, use `openSUSE:Tumbleweed/standard`
as the repository path, enable `x86_64`, and enable publishing. The UI's project
metadata editor accepts this XML. Keep an existing project's other metadata
when adding the repository.

After configuring the project, check it out into a separate work directory:

```bash
export OBS_PROJECT='home:YOUR_USERNAME:rstudio'
export OBS_CHECKOUT="$PWD/work/obs-checkout"
mkdir -p "$OBS_CHECKOUT"
cd "$OBS_CHECKOUT"
osc checkout "$OBS_PROJECT"
cd "$OBS_PROJECT"
osc mkpac rstudio
cd rstudio
cp -- "$OBS_DIR"/rstudio.spec "$OBS_DIR"/rstudio.changes \
  "$OBS_DIR"/_constraints "$OBS_DIR"/SHA256SUMS .
while read -r checksum filename; do
  cp -- "$OBS_DIR/$filename" .
done < "$OBS_DIR/SHA256SUMS"
osc addremove
osc diff
osc status
osc commit -m 'Package locally source-built RStudio for Tumbleweed'
```

The copy loop selects the recorded source inputs and excludes local build-cache
files that `osc build` may have written into the preparation directory.

For an existing OBS package, use `osc checkout "$OBS_PROJECT" rstudio` and
update that checkout instead of `osc mkpac`. Source updates and package removals
must be recorded with `osc addremove`. Review its output before committing so
the prepared input files are included. `osc commit` uploads to OBS and triggers
the server build; it is separate from committing this repository with Git.

Track the result from the OBS package checkout:

```bash
osc results
osc buildlog openSUSE_Tumbleweed x86_64
osc repourls
```

Wait for the server build and repository publication to finish. A URL may
return 404 while publishing is pending. OBS builds/signs/publishes its own
output package; the unsigned local input RPM is a source input.

## 5. Install from the published repository

Use the Tumbleweed `.repo` URL printed by `osc repourls`. In your host terminal:

```bash
sudo zypper addrepo --refresh 'PASTE_TUMBLEWEED_REPO_URL_HERE' rstudio-home
sudo zypper refresh rstudio-home
sudo zypper install --from rstudio-home rstudio
rstudio
```

Check the repository signing-key fingerprint when Zypper asks to trust the
key. An OBS-built package can have a lower release counter or a different
vendor from the locally built RPM of the same version. If Zypper declines that
explicit migration, use `sudo zypper install --from rstudio-home
--allow-vendor-change --oldpackage rstudio` after reviewing the selected package.
Later updates can be installed with `sudo zypper update rstudio`.

The launcher and menu entry appear after this host installation. Container
validation is separate; run the README's GUI checks on your desktop too.

## Updating and cleaning

Update `release.env` as described in the README, compile and validate a fresh
RPM, and prepare a new `OBS_DIR`. Record the release in
`packaging/obs/rstudio.changes` before preparing inputs. Copy the new preparation
into the OBS package checkout, remove obsolete versioned inputs with
`osc addremove`, review, and run `osc commit`. Keep `release.env` at the version
being validated; checks intentionally reject another upstream version.

`make clean` removes configured local work/output/OBS directories. Save source
archives and provenance you wish to keep before cleaning. This removes local
copies; OBS revisions and published packages are managed through OBS.

## Official references

- [Basic OBS workflow](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-basicworkflow): project repositories, spec/changelog inputs, and source uploads.
- [Local building](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-local-building): isolated `osc build` and build results.
- [Tumbleweed osc manual](https://manpages.opensuse.org/Tumbleweed/osc/osc.1.en.html): `--alternative-project`, local builds, and command options.
- [Source services](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-source-services): secure workers and the network boundary.
- [Beginner's guide](https://openbuildservice.org/help/manuals/obs-user-guide/art-obs-bg): published repository URLs and Zypper installation.
