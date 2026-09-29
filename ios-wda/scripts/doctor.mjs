import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {ROOT} from '../src/server.mjs';
console.log(`Node ${process.version}\n專案：${ROOT}`);
const env = {...process.env, APPIUM_HOME:path.join(ROOT,'.runtime/appium')};
let failures=0;
for(const [name,args] of [['xcodebuild',['-version']],['xcrun',['xctrace','list','devices']],[path.join(ROOT,'node_modules/.bin/appium'),['driver','doctor','xcuitest']]]) {
  try { console.log(execFileSync(name,args,{env,timeout:45_000,encoding:'utf8'})); }
  catch { console.log(`無法執行 ${name}，請先執行「準備環境.command」。`); failures++; }
}
console.log(fs.existsSync(path.join(ROOT,'.runtime/recognize')) ? 'Vision OCR 已編譯。' : '尚未編譯 Vision OCR（執行準備環境）。');
console.log('iPhone 顯示在 Offline 不代表可測試；需接 USB、信任 Mac、開啟開發者模式。');
process.exitCode=failures?1:0;
