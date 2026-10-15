#!/usr/bin/env bash
# Shared configuration; callers enable errexit, nounset, and pipefail.
RECIPE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$RECIPE_DIR/release.env"
RSTUDIO_VERSION=${RSTUDIO_TAG#v}
JOBS=${JOBS:-4}
BASE_IMAGE=${BASE_IMAGE:-registry.opensuse.org/opensuse/tumbleweed:latest}
WORK_DIR=${WORK_DIR:-"$RECIPE_DIR/work"}
OUTPUT_DIR=${OUTPUT_DIR:-"$RECIPE_DIR/artifacts"}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Required command is missing: $1"; }
check_platform() {
    source /etc/os-release
    [[ $ID == opensuse-tumbleweed ]] || die 'This build requires openSUSE Tumbleweed.'
    [[ $(uname -m) == x86_64 ]] || die 'This recipe currently targets x86_64.'
}
check_source() {
    local source_dir=$1 revision
    [[ -f $source_dir/CMakeLists.txt && -f $source_dir/package/linux/make-package ]] ||
        die "No RStudio checkout at $source_dir; run ./build.sh fetch."
    revision=$(git -C "$source_dir" rev-parse HEAD)
    [[ $revision == "$RSTUDIO_COMMIT" ]] || die "Unexpected source revision: $revision"
    [[ $(git -C "$source_dir" rev-parse "$RSTUDIO_TAG^{commit}") == "$revision" ]] ||
        die 'The release tag does not match the pinned commit.'
    git -C "$source_dir" diff --quiet HEAD -- || die 'Source has tracked changes; use a clean checkout.'
    [[ -z $(git -C "$source_dir" submodule status --recursive | sed -n '/^[-+U]/p') ]] ||
        die 'Submodules are missing or do not match the release.'
}

[[ $RSTUDIO_TAG =~ ^v[0-9]{4}\.[0-9]{2}\.[0-9]+\+[0-9]+$ ]] || die 'Invalid release tag.'
[[ $RSTUDIO_COMMIT =~ ^[a-f0-9]{40}$ ]] || die 'A full source commit hash is required.'
[[ $RPM_RELEASE =~ ^[[:alnum:]_.]+$ ]] || die 'Invalid RPM release.'
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer.'
