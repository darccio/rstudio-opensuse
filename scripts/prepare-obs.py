#!/usr/bin/env python3
"""Prepare offline OBS packaging inputs from a verified, locally compiled RPM."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, text=True)


def release_values(text):
    values = {}
    for line in text.splitlines():
        if line.startswith(('RSTUDIO_TAG=', 'RSTUDIO_COMMIT=', 'RPM_RELEASE=')):
            key, value = line.split('=', 1)
            words = shlex.split(value, comments=True)
            if len(words) != 1:
                raise ValueError(f'Invalid {key} in release.env')
            values[key] = words[0]
    return values


def rpm_value(artifact, tag):
    return run('rpm', '-qp', '--qf', f'%{{{tag}}}', str(artifact))


def file_list(artifact):
    query = '[%{FILENAMES}\t%{FILEMODES:octal}\t%{FILEFLAGS}\t%{FILEUSERNAME}\t%{FILEGROUPNAME}\n]'
    lines = []
    for row in run('rpm', '-qp', '--qf', query, str(artifact)).splitlines():
        path, mode, flags, owner, group = row.split('\t')
        if not path.startswith('/usr/') or '..' in Path(path).parts:
            raise ValueError(f'Unexpected package path: {path}')
        if any(character in path for character in '\r\n\t"\\*?[]'):
            raise ValueError(f'Unsupported RPM file-list path: {path}')
        if owner != 'root' or group != 'root':
            raise ValueError(f'Unexpected package owner: {path}')
        mode, flags = int(mode, 8), int(flags)
        # Fail if a future upstream RPM introduces attributes we do not handle.
        if flags & ~(1 | 2 | 16 | 64 | 128):
            raise ValueError(f'Unsupported RPM file flags {flags}: {path}')
        directives = [f'%attr({stat.S_IMODE(mode):04o},{owner},{group})']
        if stat.S_ISDIR(mode):
            directives.append('%dir')
        if flags & 1:
            directives.append('%config(noreplace)' if flags & 16 else '%config')
        if flags & 2:
            directives.append('%doc')
        if flags & 64:
            directives.append('%ghost')
        if flags & 128:
            directives.append('%license')
        directives.append('"' + path.replace('%', '%%') + '"')
        lines.append(' '.join(directives))
    return '\n'.join(lines) + '\n'


def archive_members(path, required):
    with tarfile.open(path) as archive:
        missing = set(required) - set(archive.getnames())
        if missing:
            raise ValueError(f'{path} is missing: {", ".join(sorted(missing))}')
        if 'release.env' in required:
            return release_values(archive.extractfile('release.env').read().decode())
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rpm', default=os.environ.get('RPM'))
    parser.add_argument('--source-archive', default=os.environ.get('SOURCE_ARCHIVE'))
    parser.add_argument('--recipe-archive', default=os.environ.get('RECIPE_ARCHIVE'))
    parser.add_argument('--provenance', default=os.environ.get('PROVENANCE'))
    default_work = Path(os.environ.get('WORK_DIR', str(ROOT / 'work')))
    parser.add_argument('--output', default=os.environ.get('OBS_DIR', str(default_work / 'obs')))
    arguments = parser.parse_args()
    release = release_values((ROOT / 'release.env').read_text())
    tag, revision, package_release = (release[name] for name in
                                    ('RSTUDIO_TAG', 'RSTUDIO_COMMIT', 'RPM_RELEASE'))
    if not re.fullmatch(r'v\d{4}\.\d{2}\.\d+\+\d+', tag) or not re.fullmatch(r'[a-f0-9]{40}', revision):
        raise ValueError('Invalid pinned upstream release')
    if not re.fullmatch(r'[a-zA-Z0-9_.]+', package_release):
        raise ValueError('Invalid RPM release')
    version = tag[1:]
    output_dir = Path(os.environ.get('OUTPUT_DIR', str(ROOT / 'artifacts')))
    if arguments.rpm:
        artifact = Path(arguments.rpm).resolve(strict=True)
    else:
        candidates = list(output_dir.glob('*.rpm'))
        if len(candidates) != 1:
            raise ValueError('Specify RPM=path/to/package.rpm; expected one RPM in OUTPUT_DIR')
        artifact = candidates[0].resolve(strict=True)
    marker = Path(str(artifact) + '.VERIFIED')
    if not marker.is_file() or marker.stat().st_mtime_ns < artifact.stat().st_mtime_ns:
        raise ValueError('Run make validate RPM=... first; a current .VERIFIED marker is required')
    subprocess.run(['bash', str(ROOT / 'scripts/check-rpm.sh'), str(artifact)], check=True)
    # Prefer companions next to the RPM; recovered RPMs may have them one level up.
    def companion(explicit, filename):
        if explicit:
            return Path(explicit).resolve(strict=True)
        for directory in (artifact.parent, artifact.parent.parent):
            path = directory / filename
            if path.is_file():
                return path
        raise ValueError(f'Missing {filename}; specify its archive/provenance override')
    source = companion(arguments.source_archive, f'rstudio-{version}-source.tar.gz')
    recipe = companion(arguments.recipe_archive, 'build-recipe.tar.gz')
    provenance = companion(arguments.provenance, 'provenance.txt')
    archive_members(source, ('CMakeLists.txt', 'COPYING', 'NOTICE', 'package/linux/make-package'))
    recorded_release = archive_members(recipe, ('release.env', 'scripts/build-source.sh',
                                                'packaging/tumbleweed.cmake'))
    if recorded_release != release:
        raise ValueError('The original compilation recipe does not match release.env')
    recorded = dict(line.split('=', 1) for line in provenance.read_text().splitlines()[:5])
    expected = dict(tag=tag, commit=revision, version=version, rpm_release=package_release)
    if any(recorded.get(key) != value for key, value in expected.items()):
        raise ValueError('Compilation provenance does not match release.env')
    for name in ('PREIN', 'PREUN', 'PRETRANS', 'POSTTRANS', 'VERIFYSCRIPT'):
        if rpm_value(artifact, name) not in ('', '(none)'):
            raise ValueError(f'Unsupported upstream scriptlet: {name}')
    destination = Path(arguments.output).resolve()
    if destination.exists():
        raise ValueError(f'OBS output already exists; choose a fresh OBS_DIR: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.obs-prepare-', dir=destination.parent) as temporary:
        prepared = Path(temporary) / 'package'
        prepared.mkdir()
        inputs = ((artifact, f'rstudio-{version}-{package_release}.x86_64.rpm'),
                  (source, f'rstudio-{version}-source.tar.gz'),
                  (recipe, 'rstudio-build-recipe.tar.gz'),
                  (provenance, 'build-provenance.txt'))
        for path, name in inputs:
            shutil.copy2(path, prepared / name)
        for name, scriptlet in (('postinstall.sh', 'POSTIN'), ('postuninstall.sh', 'POSTUN')):
            script = rpm_value(artifact, scriptlet)
            if script in ('', '(none)'):
                raise ValueError(f'Missing upstream scriptlet: {scriptlet}')
            (prepared / name).write_text(script)
        (prepared / 'rstudio.files').write_text(file_list(artifact))
        template = (ROOT / 'packaging/obs/rstudio.spec.in').read_text()
        (prepared / 'rstudio.spec').write_text(template.replace('@VERSION@', version)
                                             .replace('@RELEASE@', package_release))
        for name in ('rstudio.changes', '_constraints'):
            shutil.copy2(ROOT / 'packaging/obs' / name, prepared / name)
        manifest = []
        for path in sorted(prepared.iterdir()):
            if path.name in ('rstudio.spec', 'rstudio.changes', '_constraints'):
                continue
            with path.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            manifest.append(f'{digest}  {path.name}\n')
        (prepared / 'SHA256SUMS').write_text(''.join(manifest))
        run('rpmspec', '--parse', str(prepared / 'rstudio.spec'))
        prepared.rename(destination)
    print(f'OBS inputs prepared: {destination}')
    print('RStudio was compiled locally; OBS will build the RPM packaging offline.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, tarfile.TarError) as error:
        raise SystemExit(f'OBS preparation failed: {error}')
