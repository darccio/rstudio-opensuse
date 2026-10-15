#!/usr/bin/env python3
"""Run Linux packaging with GYP copy inputs that match its generated targets."""
from pathlib import Path
import subprocess
import sys


def main():
    source = Path(sys.argv[1]).resolve(strict=True)
    bindings = source / 'src/node/desktop/binding.gyp'
    original = bindings.read_bytes()
    corrected = original
    for addon in ('desktop', 'dock'):
        old = f'<(module_root_dir)/build/Release/{addon}.node'.encode()
        new = f'<(PRODUCT_DIR)/{addon}.node'.encode()
        if corrected.count(old) != 1:
            raise SystemExit(f'Unexpected GYP copy rule for {addon}; inspect {bindings}')
        corrected = corrected.replace(old, new)

    # Absolute copy inputs do not match GYP's relative Make targets on a clean
    # build. PRODUCT_DIR follows the generated output path and configuration.
    print('Using GYP product paths for desktop native addon copies.', flush=True)
    try:
        bindings.write_bytes(corrected)
        return subprocess.call(['./make-package', 'Electron', 'RPM'],
                               cwd=source / 'package/linux')
    finally:
        # Keep native retries clean, including when upstream packaging fails.
        bindings.write_bytes(original)


if __name__ == '__main__':
    sys.exit(main())
