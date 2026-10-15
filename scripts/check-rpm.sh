#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
need rpm
artifact=$(realpath -- "${1:?Usage: check-rpm.sh PACKAGE.rpm [--obs]}")
[[ -f $artifact ]] || die "No RPM at $artifact"
rpm --checksig --nosignature "$artifact"
[[ $(rpm -qp --qf '%{NAME}' "$artifact") == rstudio ]] || die 'Unexpected package name.'
[[ $(rpm -qp --qf '%{ARCH}' "$artifact") == x86_64 ]] || die 'Unexpected package architecture.'
[[ $(rpm -qp --qf '%{VERSION}' "$artifact") == "$RSTUDIO_VERSION" ]] || die 'Unexpected package version.'
package_release=$(rpm -qp --qf '%{RELEASE}' "$artifact")
case ${2:-} in
    '') [[ $package_release == "$RPM_RELEASE" ]] || die 'Unexpected package release.' ;;
    --obs)
        # OBS supplies its own source/build counters in the RPM Release field.
        [[ $package_release =~ ^[[:alnum:]_+.]+$ ]] || die 'Invalid OBS package release.' ;;
    *) die 'Usage: check-rpm.sh PACKAGE.rpm [--obs]' ;;
esac
rpm -qp --requires "$artifact" > "$artifact.requires.txt"
rpm -qpl "$artifact" > "$artifact.files.txt"
rpm -qp --scripts "$artifact" > "$artifact.scripts.txt"
python3 - "$artifact" <<'PY'
from pathlib import Path
import subprocess
import sys

rpm = Path(sys.argv[1])
requires = Path(str(rpm) + '.requires.txt').read_text().splitlines()
files = set(Path(str(rpm) + '.files.txt').read_text().splitlines())
for dependency in ('R-base', 'libxkbcommon-x11-0', 'libsqlite3-0'):
    if not any(line.split()[0] == dependency for line in requires if line.strip()):
        raise SystemExit(f'Missing runtime dependency: {dependency}')
for dependency in ('libxkbcommon-x11', 'sqlite'):
    if any(line.split()[0] == dependency for line in requires if line.strip()):
        raise SystemExit(f'Unexpected non-SUSE dependency: {dependency}')
for path in ('/usr/lib/rstudio/rstudio',
             '/usr/lib/rstudio/resources/app/bin/rsession',
             '/usr/share/applications/rstudio.desktop'):
    if path not in files:
        raise SystemExit(f'Missing package file: {path}')
# Upstream creates this symlink in %post rather than shipping it in the payload.
if '/usr/bin/rstudio' not in files:
    postinstall = subprocess.check_output(
        ['rpm', '-qp', '--qf', '%{POSTIN}', str(rpm)], text=True)
    launcher = 'ln -f -s /usr/lib/rstudio/rstudio /usr/bin/rstudio'
    if launcher not in (line.strip() for line in postinstall.splitlines()):
        raise SystemExit('Missing /usr/bin/rstudio launcher and upstream postinstall symlink.')
if not any(line.startswith('libc.so.6') for line in requires):
    raise SystemExit('Automatic ELF dependency discovery did not run.')
if any(line.startswith('ld-linux-aarch64.so.1') for line in requires):
    raise SystemExit('ARM64 runtime dependencies found in the x86_64 RPM.')
print('RPM identity, desktop files, and openSUSE dependencies checked.')
PY
