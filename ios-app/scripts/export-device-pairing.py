#!/usr/bin/env python3
"""Export one already-trusted USB device's pairing record without printing credentials."""
import socket,struct,plistlib,pathlib,os,argparse
p=argparse.ArgumentParser();p.add_argument('--udid',required=True);p.add_argument('--output',required=True);a=p.parse_args()
out=pathlib.Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
if out.exists():raise SystemExit('Destination already exists; refusing to overwrite a credential.')
request=plistlib.dumps({'MessageType':'ReadPairRecord','PairRecordID':a.udid,'ClientVersionString':'LineDraw','ProgName':'LineDraw','kLibUSBMuxVersion':3})
def read(s,n):
 b=b''
 while len(b)<n:
  chunk=s.recv(n-len(b))
  if not chunk:raise SystemExit('usbmuxd closed connection')
  b+=chunk
 return b
with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
 s.settimeout(10);s.connect('/var/run/usbmuxd');s.sendall(struct.pack('<IIII',16+len(request),1,8,1)+request)
 length,version,kind,tag=struct.unpack('<IIII',read(s,16))
 if not 16<=length<=1_000_000:raise SystemExit('Invalid usbmuxd response size')
 reply=plistlib.loads(read(s,length-16))
 raw=reply.get('PairRecordData')
 if not raw:raise SystemExit('No trusted pairing record; unlock and trust this Mac first.')
 record=plistlib.loads(raw);record['UDID']=a.udid
 with os.fdopen(os.open(out,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'wb') as f:plistlib.dump(record,f)
print('Pairing record saved to the requested protected destination; contents omitted.')
