"""Private research snapshots of explicitly configured installed addon sources.

Never executes source files, modifies the installed addon, or promotes code to a
Suite runtime. A consumer must validate the selected snapshot before packaging.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {'.lua', '.xml', '.toc', '.md', '.txt', '.tga', '.blp', '.png', '.ttf', '.otf'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    os.replace(temp, path)


def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def files_at(source):
    if not source.is_dir() or source.is_symlink():
        raise ValueError('Addon source folder is missing or a symlink')
    result = {}
    for directory, dirs, files in os.walk(source, followlinks=False):
        base = Path(directory)
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'SavedVariables', 'WTF', '__pycache__', 'Logs', 'Screenshots'}]
        for name in dirs + files:
            p = base / name
            if p.is_symlink() or getattr(p.lstat(), 'st_file_attributes', 0) & 0x400:
                raise ValueError('Linked/reparse files are not accepted')
        for name in files:
            p = base / name
            if (p.suffix.lower() in EXTENSIONS or name in {'LICENSE', 'COPYING', 'NOTICE'}) and not name.startswith('.'):
                result[p.relative_to(source).as_posix()] = p.read_bytes()
    if not result:
        raise ValueError('No source files found')
    return result


def validate(files, addon):
    toc = files.get(addon + '.toc', b'').decode('utf-8-sig')
    version = re.search(r'^## Version:\s*(.+)$', toc, re.M)
    if not version:
        raise ValueError('Missing addon TOC/version')
    if addon == 'Pawn':
        for name in ['Pawn.lua', 'Core.lua', 'ClassicHawsJon.lua', 'TooltipParsing.lua', 'Readme.md']:
            if name not in files:
                raise ValueError('Incomplete Pawn source: ' + name)
        text = files['Pawn.lua'].decode('utf-8-sig')
        for fn in ['PawnGetItemData', 'PawnGetSingleValueFromItem', 'PawnGetItemValue', 'PawnIsReady']:
            if not re.search(r'\bfunction\s+' + fn + r'\s*\(', text):
                raise ValueError('Pawn scoring interface changed: ' + fn)
    # Validate TOC runtime references without evaluating any source.
    for line in toc.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        relative = line.split(' [', 1)[0].replace('\\', '/')
        if relative not in files:
            raise ValueError('Missing TOC reference: ' + relative)
    return version[1].strip()


def inventory(files):
    return {name: sha(data) for name, data in sorted(files.items())}


class Sources:
    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.state = self.root / '.local' / 'addon-sources'

    def folder(self, addon):
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,63}', addon):
            raise ValueError('Invalid addon name')
        return self.state / addon

    def snapshot(self, addon, digest):
        if not re.fullmatch(r'[a-f0-9]{64}', digest):
            raise ValueError('Invalid snapshot identifier')
        folder = self.folder(addon) / 'snapshots' / digest
        manifest = load_json(folder / 'snapshot.json')
        files = files_at(folder / 'source')
        if inventory(files) != manifest['files']:
            raise ValueError('Snapshot was edited or corrupted; refusing to use it')
        if sha(json.dumps(manifest['files'], sort_keys=True).encode()) != digest:
            raise ValueError('Snapshot manifest does not match its identifier')
        validate(files, addon)
        return folder, manifest

    def status(self, addon):
        pointer = self.folder(addon) / 'current.json'
        if not pointer.exists():
            return {'addon': addon, 'status': 'not captured'}
        state = load_json(pointer)
        _, manifest = self.snapshot(addon, state['active'])
        return {'addon': addon, 'status': 'source captured, runtime integration not promoted', **state,
                'version': manifest['version'], 'files': len(manifest['files']), 'bytes': manifest['bytes']}

    def refresh(self, addon, source):
        destination = self.folder(addon)
        files = files_at(Path(source))
        version = validate(files, addon)
        hashes = inventory(files)
        digest = sha(json.dumps(hashes, sort_keys=True).encode())
        pointer = destination / 'current.json'
        previous = load_json(pointer) if pointer.exists() else {}
        if previous.get('active'):
            self.snapshot(addon, previous['active'])
        if previous.get('active') == digest:
            self.snapshot(addon, digest)
            return {**self.status(addon), 'changed': False}
        destination.mkdir(parents=True, exist_ok=True)
        snapshots = destination / 'snapshots';snapshots.mkdir(exist_ok=True)
        target = snapshots / digest
        manifest = {'addon': addon, 'version': version, 'files': hashes,
                    'bytes': sum(map(len, files.values())), 'purpose': 'private noncommercial research',
                    'source': 'installed addon folder; no SavedVariables', 'capturedAt': int(time.time())}
        if not target.exists():
            # Build privately and rename the complete snapshot into place. Old
            # snapshots are immutable; changing upstream never overwrites them.
            with tempfile.TemporaryDirectory(dir=snapshots) as temp:
                staging = Path(temp) / 'complete';staging.mkdir()
                for name, data in files.items():
                    p = staging / 'source' / name;p.parent.mkdir(parents=True, exist_ok=True);p.write_bytes(data)
                write_json(staging / 'snapshot.json', manifest)
                if inventory(files_at(Path(source))) != hashes:
                    raise ValueError('Installed addon changed during capture; retry after its update finishes')
                staging.rename(target)
        self.snapshot(addon, digest)
        write_json(pointer, {'active': digest, 'previous': previous.get('active')})
        # Commit only hashes/version, never machine paths, private observations or
        # vendored third-party source. Private snapshots remain in ignored .local.
        write_json(self.root / 'upstream' / (addon + '.lock.json'), manifest | {'snapshot': digest})
        return {**self.status(addon), 'changed': True}

    def rollback(self, addon):
        pointer = self.folder(addon) / 'current.json';state = load_json(pointer)
        previous = state.get('previous')
        if not previous:
            raise ValueError('No previous snapshot to restore')
        _, manifest = self.snapshot(addon, previous)
        write_json(pointer, {'active': previous, 'previous': state['active']})
        write_json(self.root / 'upstream' / (addon + '.lock.json'), manifest | {'snapshot': previous})
        return self.status(addon)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['refresh', 'watch', 'status', 'rollback'])
    p.add_argument('addon', default='Pawn', nargs='?')
    p.add_argument('--addons', type=Path, default=os.environ.get('SMYRNA_ADDONS_DIR'))
    p.add_argument('--interval', type=int, default=60)
    a = p.parse_args();sources = Sources()
    try:
        if a.command in {'refresh', 'watch'}:
            if not a.addons:
                p.error('Set SMYRNA_ADDONS_DIR or pass --addons (your installed Interface/AddOns folder)')
            if a.command == 'watch' and a.interval < 10:
                p.error('Watch interval must be at least 10 seconds')
            last_error = None
            first = True
            while True:
                try:
                    result = sources.refresh(a.addon, a.addons / a.addon)
                    if first or result['changed'] or last_error:
                        print(json.dumps(result), flush=True)
                    last_error = None
                except (ValueError, OSError) as error:
                    if a.command != 'watch':
                        raise
                    if str(error) != last_error:
                        print(json.dumps({'error': str(error), 'previousSnapshotPreserved': True}), flush=True)
                    last_error = str(error)
                first = False
                if a.command != 'watch':
                    break
                time.sleep(a.interval)
        else:
            print(json.dumps(getattr(sources, a.command)(a.addon)))
    except (ValueError, OSError) as error:
        p.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
