"""Offline checks of the driver and real CPack/RPM policy, not an RStudio build."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


class DriverTests(unittest.TestCase):
    def test_shell_syntax(self):
        for script in [ROOT / 'build.sh', *sorted((ROOT / 'scripts').glob('*.sh'))]:
            with self.subTest(script=script.name):
                result = run('bash', '-n', str(script))
                self.assertEqual(result.returncode, 0, result.stdout)

    def test_bad_concurrency_fails_before_work(self):
        result = run('bash', str(ROOT / 'build.sh'), 'help', env={**os.environ, 'JOBS': '0'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('positive integer', result.stdout)

    def test_failed_container_build_never_reports_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            engine = directory / 'docker'
            engine.write_text('#!/bin/bash\n'
                              'printf "%s\\n" "$1" >> "$CALL_LOG"\n'
                              'case "$1" in info) exit 0;; build) exit 42;; *) exit 99;; esac\n')
            engine.chmod(0o755)
            environment = {**os.environ, 'PATH': f'{directory}:{os.environ["PATH"]}',
                           'WORK_DIR': str(directory / 'work'),
                           'OUTPUT_DIR': str(directory / 'out'),
                           'CONTAINER_ENGINE': 'docker', 'CALL_LOG': str(directory / 'calls')}
            result = run('bash', str(ROOT / 'build.sh'), 'build', env=environment)
            # A root test runner is rejected before invoking any build, by design.
            if os.geteuid() == 0:
                self.assertIn('regular user', result.stdout)
            else:
                self.assertEqual(result.returncode, 42, result.stdout)
                self.assertEqual((directory / 'calls').read_text().splitlines(), ['info', 'build'])
                self.assertTrue((directory / 'out/image-build.log').exists())
            self.assertFalse((directory / 'out/SUCCESS').exists())
            self.assertFalse(list((directory / 'out').glob('*.VERIFIED')))

    def test_failed_source_fetch_cleans_partial_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            git = directory / 'git'
            git.write_text('#!/bin/bash\nexit 29\n')
            git.chmod(0o755)
            environment = {**os.environ, 'PATH': f'{directory}:{os.environ["PATH"]}',
                           'WORK_DIR': str(directory / 'work'),
                           'OUTPUT_DIR': str(directory / 'out')}
            result = run('bash', str(ROOT / 'build.sh'), 'fetch', env=environment)
            self.assertEqual(result.returncode, 29, result.stdout)
            self.assertFalse((directory / 'work/rstudio').exists())
            self.assertEqual(list((directory / 'work').glob('*.fetch.*')), [])


class UpstreamDependencyTests(unittest.TestCase):
    def run_installer_fixture(self, returncode, preflight_failure=0):
        with tempfile.TemporaryDirectory(prefix='rstudio-upstream-deps-') as temporary:
            directory = Path(temporary)
            source = directory / 'source'
            linux = source / 'dependencies/linux'
            linux.mkdir(parents=True)
            installer = linux / 'install-dependencies-zypper'
            text = ('#!/bin/bash\nset -e\n'
                    'test "$PWD" = "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"\n'
                    'zypper --non-interactive install libpq-devel\n'
                    'zypper --non-interactive install "libpq-devel"\n'
                    'zypper --non-interactive install libsqlite-devel\n'
                    'zypper --non-interactive install "libsqlite-devel"\n'
                    '# zypper install obsolete-comment-only-package\n'
                    'zypper --non-interactive install \\\n mesa-devel\n'
                    'zypper --non-interactive install "mesa-devel"\n'
                    './sibling-helper\n')
            installer.write_text(text)
            sibling = linux / 'sibling-helper'
            marker = directory / 'helper-ran'
            sibling.write_text(f'#!/bin/bash\ntouch "$HELPER_MARKER"\nexit {returncode}\n')
            sibling.chmod(0o755)
            commands = directory / 'bin'
            commands.mkdir()
            zypper = commands / 'zypper'
            zypper.write_text('#!/usr/bin/env python3\n'
                              'import json, os, sys\n'
                              'with open(os.environ["CALL_LOG"], "a") as log:\n'
                              '    log.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                              'if "--dry-run" in sys.argv:\n'
                              '    sys.exit(int(os.environ["PREFLIGHT_FAILURE"]))\n')
            zypper.chmod(0o755)
            calls = directory / 'calls'
            environment = {**os.environ, 'PATH': f'{commands}:{os.environ["PATH"]}',
                           'CALL_LOG': str(calls), 'HELPER_MARKER': str(marker),
                           'PREFLIGHT_FAILURE': str(preflight_failure)}
            result = run('bash', str(ROOT / 'scripts/run-upstream-dependencies.sh'),
                         str(source), env=environment)
            self.assertEqual(result.returncode, preflight_failure or returncode, result.stdout)
            expected = [['--non-interactive', 'install', '--dry-run', '--no-recommends', '--',
                         'postgresql-devel', 'sqlite3-devel', 'Mesa-devel']]
            if not preflight_failure:
                for package in ('postgresql-devel', 'sqlite3-devel', 'Mesa-devel'):
                    expected.extend([['--non-interactive', 'install', package]] * 2)
            self.assertEqual([json.loads(line) for line in calls.read_text().splitlines()], expected)
            self.assertEqual(marker.exists(), not preflight_failure)
            self.assertEqual(installer.read_text(), text)
            self.assertFalse(list(linux.glob('.tumbleweed-dependencies.*')))

    def test_package_translations_keep_source_and_relative_paths(self):
        self.run_installer_fixture(0)

    def test_upstream_failure_is_propagated_and_temporary_copy_removed(self):
        self.run_installer_fixture(37)

    def test_preflight_failure_stops_before_installing_packages(self):
        self.run_installer_fixture(0, preflight_failure=104)


class UpstreamBuildTests(unittest.TestCase):
    def run_build_fixture(self, returncode, gyp_main=None):
        with tempfile.TemporaryDirectory(prefix='rstudio-native-addons-') as temporary:
            source = Path(temporary)
            desktop = source / 'src/node/desktop'
            (desktop / 'src/native').mkdir(parents=True)
            (desktop / 'addon.c').write_text('int addon(void) { return 42; }\n')
            targets = [dict(target_name=name, type='loadable_module',
                            product_extension='node', product_prefix='', sources=['addon.c'])
                       for name in ('desktop', 'dock')]
            targets.append(dict(target_name='copy', type='none', dependencies=['desktop', 'dock'],
                                copies=[dict(files=[f'<(module_root_dir)/build/Release/{name}.node'
                                                    for name in ('desktop', 'dock')],
                                             destination='<(module_root_dir)/src/native')]))
            original = json.dumps(dict(target_defaults=dict(default_configuration='Release',
                                                            configurations=dict(Release={})),
                                       targets=targets)).encode()
            bindings = desktop / 'binding.gyp'
            bindings.write_bytes(original)
            package = source / 'package/linux'
            package.mkdir(parents=True)
            builder = package / 'make-package'
            builder.write_text('#!/bin/bash\nset -e\n'
                               'test "$1" = Electron\ntest "$2" = RPM\n'
                               'touch "$BUILD_MARKER"\n'
                               'if [[ -n ${GYP_MAIN:-} ]]; then\n'
                               '  cd ../../src/node/desktop\n'
                               '  "$TEST_PYTHON" "$GYP_MAIN" binding.gyp -f make --no-parallel '
                               '--depth=. --generator-output=build -Goutput_dir=. '
                               '-Dmodule_root_dir="$PWD"\n'
                               '  make -C build BUILDTYPE=Release -j4\n'
                               'fi\n'
                               f'exit {returncode}\n')
            builder.chmod(0o755)
            marker = source / 'build-ran'
            environment = {**os.environ, 'TEST_PYTHON': sys.executable,
                           'BUILD_MARKER': str(marker), 'GYP_MAIN': str(gyp_main or '')}
            if gyp_main:
                # A clean build with upstream's absolute copy inputs must fail.
                result = run(str(builder), 'Electron', 'RPM', cwd=package, env=environment)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('No rule to make target', result.stdout)
                marker.unlink()
                shutil.rmtree(desktop / 'build')
            result = run(sys.executable, str(ROOT / 'scripts/run-upstream-build.py'),
                         str(source), env=environment)
            self.assertEqual(result.returncode, returncode, result.stdout)
            self.assertTrue(marker.exists())
            self.assertEqual(bindings.read_bytes(), original)
            if gyp_main:
                for addon in ('desktop', 'dock'):
                    built = desktop / f'build/Release/{addon}.node'
                    copied = desktop / f'src/native/{addon}.node'
                    self.assertEqual(copied.read_bytes(), built.read_bytes())

    def test_clean_native_addon_copy_with_real_gyp_and_make(self):
        candidates = []
        for command in ('node-gyp', 'npm'):
            executable = shutil.which(command)
            if executable:
                root = Path(executable).resolve().parents[1]
                candidates.extend([root / 'gyp/gyp_main.py',
                                   root / 'node_modules/node-gyp/gyp/gyp_main.py'])
        gyp_main = next((path for path in candidates if path.is_file()), None)
        if not gyp_main or not all(shutil.which(tool) for tool in ('make', 'gcc', 'g++')):
            self.skipTest('node-gyp, Make, GCC and G++ required')
        self.run_build_fixture(0, gyp_main)

    def test_upstream_build_failure_restores_bindings_and_status(self):
        self.run_build_fixture(37)


@unittest.skipUnless(all(shutil.which(tool) for tool in ('cmake', 'cpack', 'rpmbuild', 'gcc', 'ninja')),
                     'CMake, CPack, rpmbuild, GCC and Ninja required')
class RpmPolicyTests(unittest.TestCase):
    def check_obs_repack(self, directory, artifact, version, rpm_release):
        inputs = directory / 'obs-inputs'
        inputs.mkdir()
        source = inputs / 'source.tar.gz'
        with tarfile.open(source, 'w:gz') as archive:
            for name in ('CMakeLists.txt', 'COPYING', 'NOTICE', 'package/linux/make-package'):
                path = inputs / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('Fixture source\n')
                archive.add(path, arcname=name)
        recipe = inputs / 'recipe.tar.gz'
        with tarfile.open(recipe, 'w:gz') as archive:
            for name in ('release.env', 'scripts/build-source.sh', 'packaging/tumbleweed.cmake'):
                archive.add(ROOT / name, arcname=name)
        revision = run('bash', '-c', 'source "$1"; printf "%s" "$RSTUDIO_COMMIT"',
                       'release-env', str(ROOT / 'release.env')).stdout
        provenance = inputs / 'provenance.txt'
        provenance.write_text(f'tag=v{version}\ncommit={revision}\nversion={version}\n'
                              f'rpm_release={rpm_release}\njobs=4\n')
        prepared = directory / 'obs'
        command = [sys.executable, str(ROOT / 'scripts/prepare-obs.py'),
                   '--rpm', str(artifact), '--source-archive', str(source),
                   '--recipe-archive', str(recipe), '--provenance', str(provenance),
                   '--output', str(prepared)]
        result = run(*command)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('.VERIFIED', result.stdout)
        self.assertFalse(prepared.exists())
        marker = Path(str(artifact) + '.VERIFIED')
        marker.write_text('Verified fixture\n')
        original = provenance.read_text()
        provenance.write_text(original.replace(f'commit={revision}', 'commit=incorrect'))
        result = run(*command)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('provenance', result.stdout)
        self.assertFalse(prepared.exists())
        provenance.write_text(original)
        result = run(*command)
        self.assertEqual(result.returncode, 0, result.stdout)
        result = run('sha256sum', '--check', 'SHA256SUMS', cwd=prepared)
        self.assertEqual(result.returncode, 0, result.stdout)
        # Build both real OBS-style RPMs offline; do not install the fixture.
        top = directory / 'obs-rpmbuild'
        top.mkdir()
        result = run('rpmbuild', '-ba', '--nodeps', '--target', 'x86_64',
                     '--define', f'_topdir {top}', '--define', f'_sourcedir {prepared}',
                     '--define', '_tmppath /tmp', str(prepared / 'rstudio.spec'))
        self.assertEqual(result.returncode, 0, result.stdout)
        packages = list((top / 'RPMS').rglob('*.rpm'))
        self.assertEqual(len(packages), 1, result.stdout)
        self.assertEqual(len(list((top / 'SRPMS').glob('*.src.rpm'))), 1, result.stdout)
        result = run('bash', str(ROOT / 'scripts/check-rpm.sh'), str(packages[0]), '--obs')
        self.assertEqual(result.returncode, 0, result.stdout)
        query = '[%{FILENAMES}\t%{FILEDIGESTS}\t%{FILEMODES}\t%{FILEFLAGS}\t%{FILELINKTOS}\n]'
        before = run('rpm', '-qp', '--qf', query, str(artifact))
        after = run('rpm', '-qp', '--qf', query, str(packages[0]))
        self.assertEqual(before.returncode, 0, before.stdout)
        self.assertEqual(after.returncode, 0, after.stdout)
        self.assertEqual(before.stdout, after.stdout)
        for tag in ('POSTIN', 'POSTUN'):
            before = run('rpm', '-qp', '--qf', f'%{{{tag}}}', str(artifact))
            after = run('rpm', '-qp', '--qf', f'%{{{tag}}}', str(packages[0]))
            self.assertEqual(before.stdout.strip(), after.stdout.strip())
        result = run(*command)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('already exists', result.stdout)
        self.assertFalse(list(directory.glob('.obs-prepare-*')))

    def test_real_rpm_has_suse_dependencies_and_desktop_layout(self):
        with tempfile.TemporaryDirectory(prefix='rstudio-rpm-policy-') as temporary:
            directory = Path(temporary)
            source = directory / 'source'
            source.mkdir()
            build = directory / 'build'
            output = directory / 'output'
            release = run('bash', '-c',
                          'source "$1"; printf "%s\\n" "${RSTUDIO_TAG#v}" "$RPM_RELEASE"',
                          'release-env', str(ROOT / 'release.env'))
            self.assertEqual(release.returncode, 0, release.stdout)
            version, rpm_release = release.stdout.splitlines()
            (source / 'fixture.c').write_text('#include <stdio.h>\nint main(void) { puts("fixture"); return 0; }\n')
            (source / 'rstudio.desktop').write_text('[Desktop Entry]\nType=Application\nName=Fixture\nExec=rstudio\n')
            postinstall = source / 'postinst.sh'
            postinstall.write_text('#!/bin/sh\nln -f -s /usr/lib/rstudio/rstudio /usr/bin/rstudio\n')
            (source / 'postun.sh').write_text('#!/bin/sh\nif [ "$1" = 0 ]; then rm -f /usr/bin/rstudio; fi\n')
            (source / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.19)
project(PackagingFixture C)
add_executable(rstudio fixture.c)
add_executable(rsession fixture.c)
install(TARGETS rstudio DESTINATION /usr/lib/rstudio)
install(TARGETS rsession DESTINATION /usr/lib/rstudio/resources/app/bin)
install(FILES rstudio.desktop DESTINATION /usr/share/applications)
set(copilot /usr/lib/rstudio/resources/app/bin/copilot-language-server-js)
# Model the multi-architecture Copilot layout with real ELF files.
foreach(relative IN ITEMS compiled/linux bin/linux
    node_modules/@microsoft/mxc-sdk/bin)
  foreach(arch IN ITEMS arm64 x64)
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/rstudio"
      DESTINATION "${copilot}/${relative}/${arch}" RENAME bundled-tool.node)
  endforeach()
endforeach()
foreach(package IN ITEMS copilot copilot-sdk)
  foreach(arch IN ITEMS arm64 x64)
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/rstudio"
      DESTINATION "${copilot}/node_modules/@github/${package}-linux-${arch}"
      RENAME bundled-tool.node)
  endforeach()
endforeach()
set(CPACK_PACKAGE_NAME rstudio)
set(CPACK_PACKAGE_VERSION @RSTUDIO_VERSION@)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Packaging test fixture")
set(CPACK_PACKAGE_VENDOR "Local recipe test")
set(CPACK_SET_DESTDIR ON)
# Match upstream's CPack handling of its bundled third-party components.
set(CPACK_RPM_SPEC_INSTALL_POST "/bin/true")
set(CPACK_RPM_POST_INSTALL_SCRIPT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/postinst.sh")
set(CPACK_RPM_POST_UNINSTALL_SCRIPT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/postun.sh")
include(CPack)
'''.replace('@RSTUDIO_VERSION@', version))
            for command in [('cmake', '-S', str(source), '-B', str(build), '-G', 'Ninja'),
                            ('cmake', '--build', str(build))]:
                result = run(*command)
                self.assertEqual(result.returncode, 0, result.stdout)
            config = build / 'TumbleweedCPack.cmake'
            config.write_text(f'include([==[{build / "CPackConfig.cmake"}]==])\n'
                              f'include([==[{ROOT / "packaging/tumbleweed.cmake"}]==])\n')
            environment = {**os.environ, 'RSTUDIO_VERSION': version, 'RPM_RELEASE': rpm_release}
            result = run('cpack', '--config', str(config), '-G', 'RPM', '-B', str(output), env=environment)
            self.assertEqual(result.returncode, 0, result.stdout)
            packages = list(output.glob('*.rpm'))
            self.assertEqual(len(packages), 1, result.stdout)
            self.assertEqual(packages[0].name, f'rstudio-{version}-{rpm_release}.x86_64.rpm')
            result = run('bash', str(ROOT / 'scripts/check-rpm.sh'), str(packages[0]))
            self.assertEqual(result.returncode, 0, result.stdout)
            files = run('rpm', '-qpl', str(packages[0]))
            self.assertEqual(files.returncode, 0, files.stdout)
            self.assertNotIn('/usr/bin/rstudio', files.stdout.splitlines())
            self.assertNotIn('arm64', files.stdout)
            self.assertEqual(sum(path.endswith('/bundled-tool.node')
                                 for path in files.stdout.splitlines()), 5)
            scripts = run('rpm', '-qp', '--qf', '%{POSTIN}', str(packages[0]))
            self.assertIn('ln -f -s /usr/lib/rstudio/rstudio /usr/bin/rstudio', scripts.stdout)
            self.check_obs_repack(directory, packages[0], version, rpm_release)
            # A package with neither a payload launcher nor its postinstall
            # creation must still fail the metadata check.
            postinstall.write_text('#!/bin/sh\n# Missing launcher\n')
            broken = directory / 'broken'
            result = run('cpack', '--config', str(config), '-G', 'RPM', '-B', str(broken), env=environment)
            self.assertEqual(result.returncode, 0, result.stdout)
            package = next(broken.glob('*.rpm'))
            result = run('bash', str(ROOT / 'scripts/check-rpm.sh'), str(package))
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn('Missing /usr/bin/rstudio launcher', result.stdout)


if __name__ == '__main__':
    unittest.main()
