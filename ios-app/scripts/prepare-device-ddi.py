#!/usr/bin/env python3
"""Copy only the installed Xcode Cryptex DDI payloads for this user's own phone.
Does not download, publish, modify Apple's original files, or mount/unmount anything.
"""
import argparse, pathlib, plistlib, shutil, hashlib

KEYS={"Cryptex1,GenericDmg":"Image.dmg", "Cryptex1,GenericTrustCache":"Image.dmg.trustcache",
      "Cryptex1,CryptexInfoPlist":"Image.dmg.cryptex_info", "Cryptex1,GenericVolume":"Image.dmg.root_hash"}

def prepare(source:pathlib.Path,destination:pathlib.Path):
    source=source.resolve()
    manifest=source/'BuildManifest.plist'
    data=plistlib.loads(manifest.read_bytes())
    identities=[x for x in data.get('BuildIdentities',[]) if x.get('Info',{}).get('Variant','').endswith('Developer Disk Image Cryptex')]
    if len(identities)!=1:raise ValueError('Expected exactly one Cryptex DDI build identity')
    payloads=[]
    for key,name in KEYS.items():
        raw=pathlib.PurePosixPath(identities[0]['Manifest'][key]['Info']['Path'])
        if raw.is_absolute() or '..' in raw.parts:raise ValueError('Unsafe manifest payload path')
        path=(source/str(raw)).resolve()
        if not path.is_relative_to(source) or not path.is_file() or path.stat().st_size==0:raise ValueError('Missing or unsafe DDI payload')
        if hashlib.sha384(path.read_bytes()).digest()!=identities[0]['Manifest'][key]['Digest']:raise ValueError('DDI payload digest does not match manifest')
        payloads.append((path,name))
    destination.mkdir(mode=0o700,parents=False,exist_ok=False)
    for path,name in payloads+[(manifest,'BuildManifest.plist')]:
        output=destination/name;shutil.copyfile(path,output);output.chmod(0o600)
    print('Prepared five local DDI files. Keep these out of source archives.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--restore-dir',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path)
    args=p.parse_args();prepare(args.restore_dir,args.output)
