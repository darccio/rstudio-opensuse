#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
source_dir=$(realpath -- "${1:?Usage: run-upstream-dependencies.sh SOURCE_DIR}")
linux_dir="$source_dir/dependencies/linux"
upstream="$linux_dir/install-dependencies-zypper"
[[ -f $upstream ]] || die "Missing upstream dependency installer: $upstream"

# Keep the copy beside the original: upstream uses relative paths and may use
# dirname(BASH_SOURCE). Never edit tracked source in the pinned checkout.
temporary=$(mktemp "$linux_dir/.tumbleweed-dependencies.XXXXXX")
trap 'rm -f -- "$temporary" "${temporary}.packages"' EXIT
python3 - "$upstream" "$temporary" <<'PY'
from pathlib import Path
import re
import shlex
import sys

source, destination = map(Path, sys.argv[1:])
text = source.read_text()
# Translate obsolete package names in the release's SUSE installer.
aliases = {
    'libpq-devel': 'postgresql-devel',
    'libsqlite-devel': 'sqlite3-devel',
    'mesa-devel': 'Mesa-devel',
}
for old, new in aliases.items():
    text = re.sub(r'(?<![\w-])' + re.escape(old) + r'(?![\w-])', new, text)
destination.write_text(text)

# Preflight the installer's literal package requests together. This catches all
# missing names in these commands before its individual install calls run.
packages = []
for line in text.replace('\\\n', ' ').splitlines():
    if 'zypper' not in line:
        continue
    lexer = shlex.shlex(line, posix=True, punctuation_chars=';&|<>')
    lexer.whitespace_split = True
    tokens = list(lexer)
    for index, token in enumerate(tokens):
        if token not in ('zypper', '/usr/bin/zypper'):
            continue
        command = tokens[index + 1:]
        end = next((i for i, arg in enumerate(command)
                    if arg in (';', '&&', '||', '|', '>', '>>', '<')), len(command))
        command = command[:end]
        action = next((i for i, arg in enumerate(command) if arg in ('install', 'in')), None)
        if action is None:
            continue
        skip_value = False
        for arg in command[action + 1:]:
            if skip_value:
                skip_value = False
                continue
            if arg in ('--repo', '--from', '--type', '-r', '-t'):
                skip_value = True
                continue
            if arg.startswith('-'):
                continue
            if any(symbol in arg for symbol in ('$', '`', '*', '?')):
                print(f'Preflight cannot expand upstream package expression: {arg}', file=sys.stderr)
                continue
            if arg not in packages:
                packages.append(arg)
Path(str(destination) + '.packages').write_bytes(
    b''.join(package.encode() + b'\0' for package in packages))
PY
bash -n "$temporary"
mapfile -d '' packages < "${temporary}.packages"
if (( ${#packages[@]} > 0 )); then
    printf 'Checking upstream package requests: %s\n' "${packages[*]}"
    zypper --non-interactive install --dry-run --no-recommends -- "${packages[@]}"
fi
cd "$linux_dir"
bash "$temporary"
