#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/scripts/common.sh"
command=${1:-build}
if (( $# > 0 )); then shift; fi
case "$command" in
    help|--help|-h)
        cat <<'EOF'
Usage: ./build.sh [build|doctor|fetch|native|check RPM|verify RPM|test]
                 [obs-prepare|obs-build|check-obs RPM|verify-obs RPM]
  build       Build Desktop from source in Tumbleweed, then verify the RPM.
  doctor      Report tools, dependencies, network, and container access.
  fetch       Fetch and verify the pinned upstream checkout into work/rstudio.
  native      Build using work/rstudio and dependencies already installed.
  check RPM   Check RPM metadata without installing anything.
  verify RPM  Install and check the RPM in a clean Tumbleweed container.
  test        Run offline build-recipe checks.
  obs-prepare Prepare offline OBS inputs from a verified RPM (RPM=path).
  obs-build   Build prepared inputs with osc for Tumbleweed x86_64.
  check-obs   Check an OBS RPM, allowing OBS-managed release counters.
  verify-obs  Install and check an OBS RPM in a clean Tumbleweed container.
Environment: JOBS=4, CONTAINER_ENGINE=docker|podman, BASE_IMAGE=..., WORK_DIR=...,
             OUTPUT_DIR=... (default: artifacts/). Native builds need Tumbleweed.
EOF
        exit 0 ;;
    test) exec python3 -m unittest discover -s "$RECIPE_DIR/tests" -v ;;
    check) exec bash "$RECIPE_DIR/scripts/check-rpm.sh" "${1:?Specify an RPM}" ;;
    check-obs) exec bash "$RECIPE_DIR/scripts/check-rpm.sh" "${1:?Specify an OBS RPM}" --obs ;;
    obs-prepare) exec python3 "$RECIPE_DIR/scripts/prepare-obs.py" "$@" ;;
    obs-build)
        need osc
        cd -- "${OBS_DIR:-$WORK_DIR/obs}"
        exec osc build --local-package --alternative-project openSUSE:Tumbleweed \
            standard x86_64 rstudio.spec ;;
esac
mkdir -p -- "$WORK_DIR" "$OUTPUT_DIR"
WORK_DIR=$(realpath -- "$WORK_DIR")
OUTPUT_DIR=$(realpath -- "$OUTPUT_DIR")
export WORK_DIR OUTPUT_DIR JOBS

if [[ $command == doctor ]]; then
    failures=0
    cat /etc/os-release
    printf '\nBuild tools:\n'
    for program in git curl cmake ninja rpmbuild R ant javac patchelf; do
        if command -v "$program" >/dev/null; then
            printf '  OK      %s\n' "$program"
        else
            printf '  MISSING %s\n' "$program"
            failures=$((failures + 1))
        fi
    done
    printf '\nDownload access:\n'
    if ! curl --fail --silent --show-error --head --location --connect-timeout 5 --max-time 15 \
        https://github.com/rstudio/rstudio >/dev/null; then failures=$((failures + 1)); fi
    printf '\nContainer access:\n'
    engine=${CONTAINER_ENGINE:-docker}
    if ! command -v "$engine" >/dev/null || ! "$engine" info >/dev/null 2>&1; then
        printf '  Cannot access %s. Native build is also available.\n' "$engine"
        failures=$((failures + 1))
    else
        printf '  OK %s\n' "$engine"
    fi
    printf '\nPin: %s (%s)\n' "$RSTUDIO_TAG" "$RSTUDIO_COMMIT"
    printf 'Unavailable prerequisites: %s\n' "$failures"
    (( failures == 0 ))
    exit
fi

case "$command" in
    fetch) exec bash "$RECIPE_DIR/scripts/fetch-source.sh" "$WORK_DIR/rstudio" ;;
    native)
        bash "$RECIPE_DIR/scripts/fetch-source.sh" "$WORK_DIR/rstudio"
        exec bash "$RECIPE_DIR/scripts/build-source.sh" "$WORK_DIR/rstudio" "$OUTPUT_DIR" ;;
    build|verify|verify-obs) ;;
    *) die "Unknown command: $command (see ./build.sh help)" ;;
esac
engine=${CONTAINER_ENGINE:-}
if [[ -z $engine ]]; then
    if command -v podman >/dev/null; then engine=podman; else engine=docker; fi
fi
[[ $engine == docker || $engine == podman ]] || die 'CONTAINER_ENGINE must be docker or podman.'
need "$engine"
"$engine" info >/dev/null 2>&1 || die "Cannot access $engine. Run on a host with container access, or use the native build."

if [[ $command == build ]]; then
    [[ $(uname -m) == x86_64 ]] || die 'This recipe currently targets x86_64.'
    [[ $(id -u) != 0 ]] || die 'Run build.sh as a regular user with container access.'
    [[ ! -e $OUTPUT_DIR/SUCCESS ]] || die 'Choose a new OUTPUT_DIR for a new build.'
    image="localhost/rstudio-tumbleweed:${RSTUDIO_COMMIT:0:12}-$(id -u)"
    "$engine" build --file "$RECIPE_DIR/Containerfile" --tag "$image" \
        --build-arg "BASE_IMAGE=$BASE_IMAGE" --build-arg "BUILD_UID=$(id -u)" \
        --build-arg "BUILD_GID=$(id -g)" --build-arg "JOBS=$JOBS" "$RECIPE_DIR" \
        2>&1 | tee "$OUTPUT_DIR/image-build.log"
    "$engine" image inspect "$image" > "$OUTPUT_DIR/build-image.json"
    user_args=()
    if [[ $engine == podman ]]; then user_args=(--userns=keep-id); fi
    "$engine" run --rm "${user_args[@]}" --env "JOBS=$JOBS" \
        --volume "$OUTPUT_DIR:/output:rw" "$image"
    mapfile -d '' packages < <(find "$OUTPUT_DIR" -maxdepth 1 -name '*.rpm' -print0)
    [[ ${#packages[@]} == 1 ]] || die 'Expected one RPM in OUTPUT_DIR.'
    artifact=${packages[0]}
else
    artifact=$(realpath -- "${1:?Specify an RPM to verify}")
    [[ -f $artifact ]] || die "No RPM at $artifact"
    rm -f -- "$artifact.VERIFIED"
    metadata_options=()
    if [[ $command == verify-obs ]]; then metadata_options=(--obs); fi
    bash "$RECIPE_DIR/scripts/check-rpm.sh" "$artifact" "${metadata_options[@]}"
fi
"$engine" run --rm --user 0 --env RSTUDIO_DISPOSABLE_CONTAINER=1 \
    --volume "$(dirname -- "$artifact"):/packages:ro" \
    --volume "$RECIPE_DIR:/recipe:ro" --entrypoint /bin/bash "$BASE_IMAGE" \
    /recipe/scripts/verify-installed.sh "/packages/$(basename -- "$artifact")" \
    2>&1 | tee "$artifact.verify.log"
printf 'Clean Tumbleweed install and library verification passed.\n' > "$artifact.VERIFIED"
