import {spawn} from 'node:child_process';
import {ROOT} from '../src/server.mjs';
const children=[]; let quitting=false;
function child(command,args) { const p=spawn(command,args,{cwd:ROOT,stdio:'inherit'});children.push(p);p.on('error',e=>{console.error(e.message);shutdown(1);});p.on('exit',()=>{if(!quitting)shutdown(1);});return p; }
function shutdown(code=0) { if(quitting)return;quitting=true;for(const p of children)p.kill('SIGTERM');setTimeout(()=>process.exit(code),1500).unref(); }
process.on('SIGINT',()=>shutdown());process.on('SIGTERM',()=>shutdown());
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function available(url) {try{const r=await fetch(url,{signal:AbortSignal.timeout(1000)});return r.ok;}catch{return false;}}
if(await available('http://127.0.0.1:4780/api/status')) {
  console.log('控制面板已在執行，開啟既有控制面板。');
  const opener=spawn('open',['http://127.0.0.1:4780'],{stdio:'ignore'});
  opener.on('exit',()=>process.exit(0));
} else {
if(!await available('http://127.0.0.1:4725/status')) child('bash',['scripts/appium.sh']);
for(let n=0;n<30&&!await available('http://127.0.0.1:4725/status');n++)await sleep(500);
if(!await available('http://127.0.0.1:4725/status')) {console.error('Appium 啟動失敗，請查看 .runtime/appium.log');shutdown(1);}
else {
  child(process.execPath,['src/server.mjs']);
  for(let n=0;n<30&&!await available('http://127.0.0.1:4780/api/status');n++)await sleep(300);
  if(await available('http://127.0.0.1:4780/api/status')) spawn('open',['http://127.0.0.1:4780'],{stdio:'ignore'});
  console.log('關閉本 Terminal 或按 Ctrl+C 可停止本次啟動的服務。');
}
}
