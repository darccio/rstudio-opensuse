#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
need git
destination=${1:-"$WORK_DIR/rstudio"}
if [[ -e $destination ]]; then
    check_source "$destination"
    printf 'Using verified checkout: %s\n' "$destination"
    exit 0
fi
mkdir -p -- "$(dirname -- "$destination")"
temporary=$(mktemp -d "${destination}.fetch.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
export GIT_TERMINAL_PROMPT=0
git -c advice.detachedHead=false clone --depth 1 --branch "$RSTUDIO_TAG" \
    https://github.com/rstudio/rstudio.git "$temporary"
[[ $(git -C "$temporary" rev-parse HEAD) == "$RSTUDIO_COMMIT" ]] || die 'Upstream tag has moved.'
git -C "$temporary" submodule update --init --recursive --depth 1
check_source "$temporary"
mv -T -- "$temporary" "$destination"
printf 'Verified %s at %s\n' "$RSTUDIO_TAG" "$RSTUDIO_COMMIT"
