#!/usr/bin/env bash
# Distribution packages are installed separately so Docker can cache this step.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_platform
[[ $EUID == 0 ]] || die 'Dependency installation requires root.'

zypper --non-interactive refresh
zypper --non-interactive install --no-recommends \
    R-base R-base-devel gcc gcc-c++ gcc-fortran make cmake ninja gawk \
    java-17-openjdk-devel ant git curl wget sudo which tar gzip bzip2 xz unzip zip \
    patch pkgconf-pkg-config 'pkgconfig(libuv)' libopenssl-devel libcurl-devel libuuid-devel \
    libxslt-devel libxml2-devel sqlite3-devel zlib-devel pam-devel \
    libsecret-devel libdrm-devel 'pkgconfig(gbm)' libxkbcommon-x11-devel \
    gtk3-devel mozilla-nss-devel alsa-devel patchelf rpm-build cpio /usr/bin/python3 \
    binutils file findutils coreutils shadow util-linux \
    postgresql-devel libbz2-devel build jq
