#!/usr/bin/env python3
"""Build a self-contained Swimble DMG and persist its Finder presentation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from ds_store import DSStore
from mac_alias import Alias

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / 'assets/swimble-dmg/Finder-layout.json'


def run(*args, capture=False):
    result = subprocess.run([str(x) for x in args], check=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def dependencies(binary):
    lines = run('otool', '-L', binary, capture=True).decode().splitlines()[1:]
    return [line.strip().split(' (', 1)[0] for line in lines]


def architectures(binary):
    return set(run('lipo', '-archs', binary, capture=True).decode().split())


def require_universal(binary, label):
    """Release builds must run on both Apple Silicon and Intel Macs."""
    missing = {'arm64', 'x86_64'} - architectures(binary)
    if missing:
        raise RuntimeError(
            f'{label} is not universal; missing {" ".join(sorted(missing))}: {binary}')


def prepare_app(source, destination, signing_identity="-", notary_profile=None):
    run('ditto', source, destination)
    # Cloud-backed working copies may add these to build products. They are
    # invalid in a signed bundle; remove them only from our disposable copy.
    for attribute in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
        run('xattr', '-rd', attribute, destination)
    info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
    executable = destination / 'Contents/MacOS' / info['CFBundleExecutable']
    require_universal(executable, 'App executable')
    for dep in dependencies(executable):
        if Path(dep).name != 'libopus.0.dylib' or dep.startswith('@'):
            continue
        # Keep the unversioned name: build_opus.sh installs libopus.0.dylib as
        # a symlink to libopus.0.<abi>.dylib, and the app links the former.
        original = Path(dep)
        if not original.is_file():
            raise RuntimeError(f'Missing Opus library: {dep}')
        frameworks = destination / 'Contents/Frameworks'
        frameworks.mkdir(exist_ok=True)
        bundled = frameworks / original.name
        shutil.copy2(original, bundled)
        bundled.chmod(0o755)
        require_universal(bundled, 'Bundled Opus')
        run('install_name_tool', '-id', '@rpath/' + original.name, bundled)
        run('install_name_tool', '-change', dep,
            '@executable_path/../Frameworks/' + original.name, executable)
        notices = destination / 'Contents/Resources/Licenses'
        notices.mkdir(exist_ok=True)
        shutil.copy2(original.parent.parent / 'COPYING', notices / 'Opus-COPYING.txt')
        run('codesign', '--force', '--sign', signing_identity, *(['--timestamp', '--options', 'runtime'] if signing_identity != '-' else []), bundled)
    for candidate in [executable, *destination.glob('Contents/Frameworks/*.dylib')]:
        for dep in dependencies(candidate):
            if dep.startswith(('/opt/', '/usr/local/', '/Users/')):
                raise RuntimeError(f'Nonportable dependency: {candidate}: {dep}')
    rpc = ROOT / 'rust-core/target/release/swimble-rpc'
    if not rpc.is_file():
        raise RuntimeError('Missing release swimble-rpc executable; run build_bridge.sh first')
    shutil.copy2(rpc, destination / 'Contents/MacOS/swimble-rpc')
    require_universal(destination / 'Contents/MacOS/swimble-rpc', 'swimble-rpc')
    run('codesign', '--force', '--sign', signing_identity, *(['--timestamp', '--options', 'runtime'] if signing_identity != '-' else []), destination / 'Contents/MacOS/swimble-rpc')
    # User-selected native positional plugins can have another developer's
    # signature. Other hardened-runtime protections remain enabled.
    sign_options = ['--timestamp', '--options', 'runtime', '--entitlements', ROOT / 'MacClient/Swimble.entitlements'] if signing_identity != '-' else []
    run('codesign', '--force', '--sign', signing_identity, *sign_options, destination)
    run('codesign', '--verify', '--deep', '--strict', destination)
    if notary_profile:
        archive = destination.parent / 'Swimble-notarization.zip'
        run('ditto', '-c', '-k', '--keepParent', destination, archive)
        run('xcrun', 'notarytool', 'submit', archive, '--keychain-profile', notary_profile, '--wait')
        run('xcrun', 'stapler', 'staple', destination)
        archive.unlink()


def attach(image, mountpoint, readonly=False):
    args = ['hdiutil', 'attach', image, '-nobrowse', '-noautoopen',
            '-mountpoint', mountpoint, '-plist']
    if readonly:
        args.append('-readonly')
    run(*args, capture=True)


def write_finder_metadata(volume, layout, background):
    size = layout['contentSize']
    # Finder's frame includes its 28-point title bar; content stays 800 x 500.
    bounds = '{{200, 160}, {%d, %d}}' % (size['width'], size['height'] + 28)
    background_alias = Alias.for_file(str(volume / '.background' / background)).to_bytes()
    with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
        store['.']['bwsp'] = {
            'ShowStatusBar': False, 'ShowToolbar': False, 'ShowTabView': False,
            'ContainerShowSidebar': False, 'ShowSidebar': False,
            'WindowBounds': bounds,
        }
        store['.']['icvp'] = {
            'viewOptionsVersion': 1, 'backgroundType': 2,
            'backgroundImageAlias': background_alias,
            'backgroundColorRed': 231 / 255, 'backgroundColorGreen': 244 / 255,
            'backgroundColorBlue': 234 / 255,
            'iconSize': float(layout['iconSize']), 'textSize': 14.0,
            'gridSpacing': 100.0, 'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
            'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
            'showIconPreview': True, 'showItemInfo': False,
            'labelOnBottom': True, 'arrangeBy': 'none',
        }
        store['.']['vstl'] = ('type', b'icnv')
        store['.']['vSrn'] = ('long', 1)
        for name, center in layout['iconCenters'].items():
            store[name]['Iloc'] = tuple(center)
        for name in ['.background', '.VolumeIcon.icns', '.fseventsd', '.Trashes']:
            store[name]['Iloc'] = (1100, 100)


def verify(volume, layout, background):
    image = volume / '.background' / background
    assert image.is_file(), 'Missing background'
    assert (volume / 'Applications').is_symlink(), 'Missing Applications link'
    assert os.readlink(volume / 'Applications') == '/Applications'
    with DSStore.open(str(volume / '.DS_Store'), 'r') as store:
        options = store['.']['icvp']
        assert options['backgroundType'] == 2, 'Finder background is not an image'
        assert options['iconSize'] == layout['iconSize']
        saved = Alias.from_bytes(options['backgroundImageAlias'])
        actual = Alias.for_file(str(image))
        assert saved.target.cnid == actual.target.cnid, 'Broken background file alias'
        for name, center in layout['iconCenters'].items():
            assert store[name]['Iloc'] == tuple(center), f'Incorrect position for {name}'
    app = volume / 'Swimble.app'
    run('codesign', '--verify', '--deep', '--strict', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    deps = dependencies(executable)
    opus = '@executable_path/../Frameworks/libopus.0.dylib'
    assert opus in deps and (app / 'Contents/Frameworks/libopus.0.dylib').is_file()
    require_universal(executable, 'App executable')
    require_universal(app / 'Contents/MacOS/swimble-rpc', 'swimble-rpc')
    require_universal(app / 'Contents/Frameworks/libopus.0.dylib', 'Bundled Opus')
    print('Verified: embedded background alias, icon positions, Applications link, '
          'bundled universal Opus, universal app/rpc, and app signature.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--signing-identity', default=os.environ.get('SWIMBLE_SIGNING_IDENTITY', '-'))
    parser.add_argument('--notary-profile', default=os.environ.get('SWIMBLE_NOTARY_PROFILE'))
    args = parser.parse_args()
    if args.notary_profile and args.signing_identity == '-':
        parser.error('Notarization requires a Developer ID signing identity')
    source = args.app.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        parser.error(f'Output already exists: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    layout = json.loads(LAYOUT.read_text())
    background = layout['background']
    # Stage outside cloud-backed workspaces, whose Finder attributes can make
    # codesign reject an otherwise valid application bundle.
    with tempfile.TemporaryDirectory(prefix='swimble-dmg-') as tmp:
        tmp = Path(tmp)
        stage, mount = tmp / 'source', tmp / 'mounted'
        stage.mkdir(); mount.mkdir()
        prepare_app(source, stage / 'Swimble.app', args.signing_identity, args.notary_profile)
        os.symlink('/Applications', stage / 'Applications')
        (stage / '.background').mkdir()
        shutil.copy2(LAYOUT.parent / background, stage / '.background' / background)
        shutil.copy2(ROOT / 'assets/swimble-icon/Swimble.icns', stage / '.VolumeIcon.icns')
        writable = tmp / 'installer-rw.dmg'
        run('hdiutil', 'create', '-srcfolder', stage, '-volname', 'Swimble',
            '-fs', 'HFS+', '-format', 'UDRW', writable)
        attach(writable, mount)
        try:
            run('xcrun', 'SetFile', '-a', 'C', mount)
            write_finder_metadata(mount, layout, background)
            verify(mount, layout, background)
        finally:
            run('hdiutil', 'detach', mount)
        run('hdiutil', 'convert', writable, '-format', 'UDZO', '-o', output)
        run('hdiutil', 'verify', output)
        attach(output, mount, readonly=True)
        try:
            verify(mount, layout, background)
        finally:
            run('hdiutil', 'detach', mount)
    if args.signing_identity != '-':
        run('codesign', '--force', '--sign', args.signing_identity, '--timestamp', output)
    if args.notary_profile:
        run('xcrun', 'notarytool', 'submit', output, '--keychain-profile', args.notary_profile, '--wait')
        run('xcrun', 'stapler', 'staple', output)
        run('xcrun', 'stapler', 'validate', output)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.dmg.sha256').write_text(f'{checksum}  {output.name}\n')
    print(f'Created {output}', flush=True)


if __name__ == '__main__':
    main()
