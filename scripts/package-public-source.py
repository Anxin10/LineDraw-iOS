#!/usr/bin/env python3
"""Snapshot reviewed source only; leave this checkout and local signing untouched."""
import hashlib
import pathlib
import re
import shutil
import subprocess
import tempfile
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'ios-app/exports/github-v1.1.8'
out.mkdir(parents=True, exist_ok=True)
paths = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
forbidden = {'.git', '.runtime', '.build', 'exports', 'node_modules', 'target', 'xcuserdata', '__pycache__'}
forbidden_suffixes = {'.ipa', '.p12', '.p8', '.mobileprovision', '.provisionprofile', '.key', '.pem', '.log', '.pyc'}
with tempfile.TemporaryDirectory(prefix='linedraw-public-') as temporary:
    stage = pathlib.Path(temporary) / 'LineDraw-iOS'
    for name in sorted(set(paths)):
        if not name:
            continue
        rel = pathlib.PurePosixPath(name)
        source = root / rel
        if (forbidden.intersection(rel.parts) or rel.suffix in forbidden_suffixes
                or name.startswith('ios-wda/data/') or name.startswith('.env') and name != '.env.example'
                or source.is_symlink() or not source.is_file()):
            continue
        destination = stage / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    # Generated local project retains a Team and Apple DDI reference. Remove
    # both in the staging copy; generation on the recipient's Mac restores DDI.
    subprocess.run(['ruby', '-rxcodeproj', '-e', '''
p=Xcodeproj::Project.open(ARGV[0]);
p.targets.each{|t|t.build_configurations.each{|c|c.build_settings['DEVELOPMENT_TEAM']=''}};
(p.root_object.attributes['TargetAttributes'] || {}).each_value{|v|v.delete('DevelopmentTeam')};
p.files.select{|f|f.path.to_s.include?('BundledDDI')}.each{|f|f.remove_from_project};p.save
''', str(stage / 'ios-app/LineDraw.xcodeproj')], check=True)
    for path in stage.rglob('*'):
        if path.is_file() and path.suffix in {'.swift', '.rb', '.md', '.pbxproj', '.json', '.yml'}:
            text = path.read_text(errors='replace')
            if re.search(r'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}|/Users/[^/]+/', text):
                raise SystemExit(f'Personal configuration requires review: {path.relative_to(stage)}')
    archive = out / 'LineDraw-1.1.8-source.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
        for file in sorted(stage.rglob('*')):
            if file.is_file():
                package.write(file, pathlib.Path(stage.name) / file.relative_to(stage))
    (out / 'SHA256SUMS.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
    print(archive)
