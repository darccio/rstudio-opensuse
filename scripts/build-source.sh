#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_platform
[[ $EUID != 0 ]] || die 'Compile and package as a regular user.'
for program in git R cmake cpack rpmbuild ant javac python3 tar; do need "$program"; done
source_dir=$(realpath -- "${1:?Usage: build-source.sh SOURCE_DIR OUTPUT_DIR}")
mkdir -p -- "${2:?Usage: build-source.sh SOURCE_DIR OUTPUT_DIR}"
output=$(realpath -- "$2")
check_source "$source_dir"
[[ ! -e $output/SUCCESS ]] || die "Output already contains a completed build: $output"
exec > >(tee "$output/build.log") 2>&1
trap 'status=$?; if (( status != 0 )); then printf "Build failed (exit %s). See %s/build.log\n" "$status" "$output" >&2; fi' EXIT

export RSTUDIO_VERSION RPM_RELEASE
version_base=${RSTUDIO_VERSION%+*}
IFS=. read -r RSTUDIO_VERSION_MAJOR RSTUDIO_VERSION_MINOR RSTUDIO_VERSION_PATCH <<< "$version_base"
export RSTUDIO_VERSION_MAJOR RSTUDIO_VERSION_MINOR RSTUDIO_VERSION_PATCH
export RSTUDIO_VERSION_SUFFIX="+${RSTUDIO_VERSION##*+}"
export CMAKE_BUILD_TYPE=Release CMAKE_GENERATOR=Ninja
export CMAKE_INSTALL_PREFIX=/usr/lib/rstudio
# The uppercase SUSE substring selects upstream's openSUSE dependency branch.
export PACKAGE_OS=openSUSE-Tumbleweed OS=opensuse-tumbleweed ARCH=x86_64 PRODUCT=electron
export MAKEFLAGS="-j$JOBS" CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
export CMAKE_POLICY_VERSION_MINIMUM=3.5
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git -C "$source_dir" show -s --format=%ct HEAD)
export RSTUDIO_BUILD_PACKAGE=0
unset SCCACHE_ENABLED JENKINS_URL

{
    printf 'tag=%s\ncommit=%s\nversion=%s\nrpm_release=%s\njobs=%s\n' \
        "$RSTUDIO_TAG" "$RSTUDIO_COMMIT" "$RSTUDIO_VERSION" "$RPM_RELEASE" "$JOBS"
    cat /etc/os-release
    cmake --version
    gcc --version
    R --version
    java -version 2>&1
    git -C "$source_dir" submodule status --recursive
} > "$output/provenance.txt"
rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' | sort > "$output/build-packages.tsv"
cp -- "$RECIPE_DIR/release.env" "$output/"
cp -- "$source_dir/COPYING" "$source_dir/NOTICE" "$output/"

# Archive tracked source and initialized submodules before package scripts edit it.
cd "$source_dir"
git ls-files --recurse-submodules -z | \
    tar --null --verbatim-files-from --files-from=- --sort=name \
        --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
        -czf "$output/rstudio-$RSTUDIO_VERSION-source.tar.gz"
tar -C "$RECIPE_DIR" --exclude=__pycache__ -czf "$output/build-recipe.tar.gz" \
    release.env Containerfile .dockerignore build.sh Makefile README.md scripts packaging tests docs

cd "$source_dir/package/linux"
python3 "$RECIPE_DIR/scripts/run-upstream-build.py" "$source_dir"

# Locate the release script's actual build directory rather than guessing it.
mapfile -d '' configs < <(find "$source_dir/package" -name CPackConfig.cmake \
    -not -path '*/_CPack_Packages/*' -print0)
[[ ${#configs[@]} == 1 ]] || die "Expected one CPack configuration; found ${#configs[@]}. Use a clean checkout."
upstream_config=${configs[0]}
package_config="$(dirname -- "$upstream_config")/TumbleweedCPack.cmake"
printf 'include([==[%s]==])\ninclude([==[%s]==])\n' \
    "$upstream_config" "$RECIPE_DIR/packaging/tumbleweed.cmake" > "$package_config"
cpack --config "$package_config" -G RPM -B "$output/package"
mapfile -d '' packages < <(find "$output/package" -maxdepth 1 -name '*.rpm' -print0)
[[ ${#packages[@]} == 1 ]] || die 'CPack did not produce exactly one binary RPM.'
cp -- "${packages[0]}" "$output/"
artifact="$output/$(basename -- "${packages[0]}")"
bash "$RECIPE_DIR/scripts/check-rpm.sh" "$artifact"
cd "$output"
sha256sum -- ./*.rpm ./*.tar.gz > SHA256SUMS
printf 'RPM built and metadata checked. Clean-container installation is still required.\n' > SUCCESS
printf 'Package: %s\n' "$artifact"
