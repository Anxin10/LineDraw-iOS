#!/usr/bin/env python3
"""Create bundled dependency attribution from cargo's locked metadata, not private files."""
import pathlib,json,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
cargo=pathlib.Path.home()/'.cargo/bin/cargo'
raw=subprocess.check_output([str(cargo),'metadata','--locked','--format-version','1','--manifest-path',str(root/'DeviceBridge/Cargo.toml')])
data=json.loads(raw);sections=['Rust bridge third-party notices. LineDraw original code retains PolyForm Noncommercial 1.0.0.\nThe following dependencies retain their own licenses.']
for p in sorted(data['packages'],key=lambda p:p['name']):
 if p['name']=='linedraw-device-bridge':continue
 folder=pathlib.Path(p['manifest_path']).parent
 sections.append('\n'+('='*72)+'\n'+p['name']+' '+p['version']+'\nLicense expression: '+str(p.get('license'))+'\n'+str(p.get('repository') or ''))
 files=[]
 for pattern in ['LICENSE*','LICENCE*','COPYING*','NOTICE*']:
  files.extend(f for f in folder.glob(pattern) if f.is_file())
 if p.get('license_file'):
  f=folder/p['license_file']
  if f.is_file():files.append(f)
 for f in sorted(set(files)):sections.append('\n--- '+f.name+' ---\n'+f.read_text(errors='replace'))
(root/'Resources/Rust-THIRD_PARTY_NOTICES.txt').write_text('\n'.join(sections))
print('Dependency notices generated; '+str(len(data['packages'])-1)+' packages in locked metadata.')
