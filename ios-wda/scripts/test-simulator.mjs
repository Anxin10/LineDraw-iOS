import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {ROOT} from '../src/server.mjs';
import {AppiumDriver} from '../src/appium.mjs';
import {Engine} from '../src/engine.mjs';
import {Store} from '../src/store.mjs';
import {FIVE_LINKS} from '../src/catalog.mjs';
import {visionOcr} from '../src/ocr.mjs';

const udid = fs.readFileSync(path.join(ROOT,'.runtime/simulator-udid'),'utf8').trim();
const devices=JSON.parse(execFileSync('xcrun',['simctl','list','devices','-j'],{encoding:'utf8'}));
const simulator=Object.values(devices.devices).flat().find(d=>d.udid===udid);
assert.equal(simulator?.name,'LineDraw_WDA_Lab','Only the dedicated offline simulator is allowed.');
assert.equal(simulator.state,'Booted','Boot and install the fixture first.');
const bundleId='com.beybladehunter.linedraw.fixture.ios';
try { execFileSync('xcrun',['simctl','terminate',udid,bundleId],{stdio:'ignore'}); } catch { /* A freshly installed fixture may not be running yet. */ }
execFileSync('xcrun',['simctl','launch',udid,bundleId],{stdio:'ignore'});
const dir=path.join(ROOT,'.runtime/validation',new Date().toISOString().replace(/[:.]/g,'-'));
fs.mkdirSync(dir,{recursive:true});
const store=new Store(dir);
const driver=new AppiumDriver({bundleId});
const clickSources=[];
const originalTap=driver.tap.bind(driver);
driver.tap=async(target,...args)=>{await originalTap(target,...args);clickSources.push(target.source);};
const engine=new Engine({driver,store,loadMs:30_000});
const rows=FIVE_LINKS.map(row=>({...row,startsAt:'2020-01-01T00:00:00+08:00',endsAt:'2099-01-01T00:00:00+08:00'}));
let timer;
try {
  console.log('Starting actual Appium/XCTest session on the dedicated simulator…');
  await driver.connect({udid,platformVersion:'26.2',mode:'xcode'});
  console.log('WDA session ready.');
  fs.writeFileSync(path.join(dir,'initial.xml'),(await driver.snapshot()).xml);
  engine.start(rows,{scope:'fixture-only'});
  timer=setTimeout(()=>engine.stop(),180_000);
  const report=setInterval(()=>console.log(JSON.stringify(engine.view())),5000);
  try { await engine.worker; } finally { clearInterval(report); clearTimeout(timer); }
  fs.writeFileSync(path.join(dir,'batch.json'),JSON.stringify(engine.view(),null,2));
  const final=await driver.snapshot();
  fs.writeFileSync(path.join(dir,'final.xml'),final.xml);
  fs.writeFileSync(path.join(dir,'final.png'),Buffer.from(await driver.screenshot(),'base64'));
  assert.equal(engine.state,'COMPLETED',engine.reason);
  assert.deepEqual(rows.map(row=>store.record('fixture-only',row.id)?.status),['SUBMITTED','SUBMITTED','ENDED','ALREADY','SUBMITTED']);
  assert.ok(final.nodes.some(n=>n.labels.some(t=>t.includes('測試送出 3 次'))),'Exactly three submissions across five coupons');
  const ocr=await visionOcr(path.join(ROOT,'.runtime/recognize'))(await driver.screenshot(),{width:final.width,height:final.height});
  assert.ok(ocr.some(n=>n.labels.some(t=>t.includes('查看已領取'))),'Vision can read the terminal button');
  console.log('PASS five coupons: 3 submissions, 1 ended, 1 already received; OCR recognized terminal button.');
  const captcha={...rows[0],url:'https://liff.line.me/fixture/c/captcha'};
  engine.start([captcha],{scope:'fixture-captcha'});await engine.worker;
  assert.equal(engine.state,'PAUSED');assert.match(engine.reason,/驗證|人工/);
  console.log('PASS CAPTCHA pauses without clicking.');engine.stop();
  const slow={...rows[0],url:'https://liff.line.me/fixture/c/slow'};
  engine.start([slow],{scope:'fixture-slow'});await engine.worker;
  assert.equal(engine.state,'COMPLETED');assert.equal(store.record('fixture-slow','coupon:fixture:slow')?.status,'SUBMITTED');
  console.log('PASS delayed page loading submits once.');
  driver.ocr=visionOcr(path.join(ROOT,'.runtime/recognize'));
  const image={...rows[0],url:'https://liff.line.me/fixture/c/image'};
  engine.start([image],{scope:'fixture-ocr'});await engine.worker;
  assert.equal(engine.state,'COMPLETED');assert.equal(store.record('fixture-ocr','coupon:fixture:image')?.status,'SUBMITTED');
  assert.equal(clickSources.at(-1),'ocr','Image-only case must actually use the OCR tap path');
  console.log('PASS image-only inaccessible button: Vision OCR + WDA coordinate tap.');
  fs.writeFileSync(path.join(dir,'result.json'),JSON.stringify({passed:true,cases:8,at:new Date().toISOString(),appium:'3.8.0',xcuitest:'12.13.2',ios:'26.2',realLineTested:false},null,2));
  console.log(`Evidence: ${dir}`);
} catch(error) {
  console.error(error);
  if(driver.sessionId){try{fs.writeFileSync(path.join(dir,'failure.xml'),(await driver.snapshot()).xml);fs.writeFileSync(path.join(dir,'failure.png'),Buffer.from(await driver.screenshot(),'base64'));}catch{}}
  console.error(`Evidence: ${dir}`);process.exitCode=1;
} finally {clearTimeout(timer);engine.stop();await driver.disconnect().catch(()=>{});}
