import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {ROOT} from '../src/server.mjs';
const run=(args,options={})=>execFileSync('xcrun',args,{encoding:'utf8',...options});
const devices=JSON.parse(run(['simctl','list','devices','available','-j']));
let device=Object.values(devices.devices).flat().find(d=>d.name==='LineDraw_WDA_Lab');
if(!device) {
  const udid=run(['simctl','create','LineDraw_WDA_Lab','com.apple.CoreSimulator.SimDeviceType.iPhone-17','com.apple.CoreSimulator.SimRuntime.iOS-26-2']).trim();
  device={udid,state:'Shutdown'};
}
fs.mkdirSync(path.join(ROOT,'.runtime'),{recursive:true});
fs.writeFileSync(path.join(ROOT,'.runtime/simulator-udid'),device.udid);
if(device.state!=='Booted')run(['simctl','boot',device.udid]);
run(['simctl','bootstatus',device.udid,'-b'],{stdio:'inherit'});
run(['simctl','install',device.udid,path.join(ROOT,'.runtime/LineDrawFixture.app')]);
run(['simctl','launch',device.udid,'com.beybladehunter.linedraw.fixture.ios']);
console.log('LineDraw_WDA_Lab ready. No personal devices or LINE accounts were touched.');
