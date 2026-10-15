#!/usr/bin/env bash
# Run only in a clean disposable Tumbleweed container, never on the user's host.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_platform
[[ ${RSTUDIO_DISPOSABLE_CONTAINER:-} == 1 && $EUID == 0 ]] ||
    die 'This verifier must run in a disposable container through ./build.sh verify.'
artifact=${1:?Usage: verify-installed.sh PACKAGE.rpm}
zypper --non-interactive refresh
zypper --non-interactive install --allow-unsigned-rpm "$artifact"
zypper --non-interactive install --no-recommends binutils /usr/bin/python3
test -f "$(R RHOME)/lib/libR.so"
R --vanilla --slave -e 'cat(R.version.string, "\n")'
python3 - <<'PY'
from pathlib import Path
import os
import subprocess

root = Path('/usr/lib/rstudio')
launcher = Path('/usr/bin/rstudio')
if not os.access(launcher, os.X_OK) or launcher.resolve() != root / 'rstudio':
    raise SystemExit('Installed /usr/bin/rstudio launcher is missing or points to the wrong executable.')
checked = 0
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    with path.open('rb') as stream:
        header = stream.read(20)
    if header[:4] != b'\x7fELF':
        continue
    if len(header) < 20 or header[4:6] != b'\x02\x01' or int.from_bytes(header[18:20], 'little') != 62:
        raise SystemExit(f'Unexpected ELF architecture in x86_64 package: {path}')
    # Static executables do not have dynamic dependencies.
    headers = subprocess.run(['readelf', '-lW', str(path)], capture_output=True, text=True, check=True)
    dynamic = subprocess.run(['readelf', '-dW', str(path)], capture_output=True, text=True, check=True)
    if 'INTERP' not in headers.stdout and '(NEEDED)' not in dynamic.stdout:
        continue
    result = subprocess.run(['ldd', str(path)], capture_output=True, text=True)
    if result.returncode or 'not found' in result.stdout + result.stderr:
        raise SystemExit(f'Unresolved runtime dependencies: {path}\n{result.stdout}{result.stderr}')
    checked += 1
if checked == 0:
    raise SystemExit('No dynamically linked ELF files were checked.')
print(f'Installed successfully; checked {checked} ELF files for unresolved libraries.')
PY
printf 'Clean Tumbleweed install and library checks passed; GUI testing remains manual.\n'
