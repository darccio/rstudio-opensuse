#!/usr/bin/env bash
# Intended for the disposable build image, or an explicitly prepared native host.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_platform
[[ $EUID == 0 ]] || die 'Dependency installation requires root.'
source_dir=$(realpath -- "${1:?Usage: install-dependencies.sh SOURCE_DIR}")
check_source "$source_dir"

case ${2:---all} in
    --all) bash "$RECIPE_DIR/scripts/install-system-dependencies.sh" ;;
    --upstream-only) ;;
    *) die 'Usage: install-dependencies.sh SOURCE_DIR [--all|--upstream-only]' ;;
esac

# The working directory matters: the upstream scripts use relative paths.
export CMAKE_POLICY_VERSION_MINIMUM=3.5
export MAKEFLAGS="-j$JOBS"
bash "$RECIPE_DIR/scripts/run-upstream-dependencies.sh" "$source_dir"

# Do not silently accept an installer which leaves an incomplete checkout.
command -v R >/dev/null
command -v javac >/dev/null
test -f "$(R RHOME)/lib/libR.so"
