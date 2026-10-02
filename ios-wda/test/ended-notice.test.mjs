import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {classify,ENDED_NOTICES} from '../src/screen.mjs';
import {Engine} from '../src/engine.mjs';
import {Store} from '../src/store.mjs';
import {FIVE_LINKS} from '../src/catalog.mjs';
import {node,page} from './helpers.mjs';
const notice=(label='抽獎期間已結束',alert=false)=>page([],{nodes:[
 node(label,{type:'XCUIElementTypeStaticText',enabled:false,rect:{x:40,y:320,width:300,height:40}}),
 ...(alert?[node('提醒',{type:'XCUIElementTypeAlert',rect:{x:20,y:260,width:350,height:220}})]:[])
]});
test('完整結束提示在內文、停用按鈕及已知提示框皆直接結束',()=>{
 for(const label of [...ENDED_NOTICES,' 抽獎期間\n已結束！']){
  assert.equal(classify(notice(label)).kind,'ended');assert.equal(classify(notice(label,true)).kind,'ended');assert.equal(classify(page([node(label,{enabled:false})])).kind,'ended');
 }
});
test('條件句、無關提示框、登入驗證及其他 App 不會被結束提示覆蓋',()=>{
 assert.equal(classify(notice('如果抽獎期間已結束，請下次再來')).kind,'wait');
 assert.equal(classify({...notice(),bundleId:'com.apple.springboard'}).kind,'pause');
 const blocked=notice('抽獎期間已結束',true);blocked.nodes.push(node('請輸入驗證碼'));assert.equal(classify(blocked).kind,'pause');
 const unrelated=notice('抽獎期間已結束',true);unrelated.nodes[0].rect.y=700;assert.equal(classify(unrelated).kind,'pause');
});
test('優惠券的一般登入付款說明不會擋住結束通知',()=>{
 const s=notice();s.nodes.push(node('使用優惠券時可能付款，本活動不需登入',{type:'XCUIElementTypeStaticText',rect:{x:20,y:100,width:350,height:80}}));
 assert.equal(classify(s).kind,'ended');s.nodes.push(node('',{type:'XCUIElementTypeSecureTextField'}));assert.notEqual(classify(s).kind,'ended');
});
test('結束提示 OCR 仍需底部與足夠信心',()=>{
 assert.equal(classify(page([node('抽獎期間已結束',{source:'ocr',confidence:.95})])).kind,'ended');
 assert.equal(classify(page([node('抽獎期間已結束',{source:'ocr',confidence:.5})])).kind,'wait');
});
test('結束內文與提示框後仍執行下一筆，只點擊一次抽選',async t=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'linedraw-ended-'));t.after(()=>fs.rmSync(directory,{recursive:true,force:true}));
 const store=new Store(directory),screens=[notice(),notice('抽獎期間已結束',true),page(['抽選'])],opens=[],taps=[];let clock=0;
 const driver={open:async url=>{opens.push(url);return 'previous-page';},snapshot:async()=>screens[opens.length-1],tap:async target=>{taps.push(target);}};
 const engine=new Engine({driver,store,online:async()=>true,clock:()=>clock,wallClock:()=>Date.parse('2026-09-26T12:00:00+08:00'),delay:async ms=>{clock+=ms;},pollMs:10,settleMs:0,loadMs:100});
 const rows=FIVE_LINKS.slice(0,3);engine.start(rows,{scope:'ended-notice'});await engine.worker;
 assert.equal(engine.state,'COMPLETED');assert.deepEqual(opens,rows.map(r=>r.url));assert.equal(taps.length,1);assert(taps[0].labels.includes('抽選'));
 assert.deepEqual(rows.map(r=>store.record('ended-notice',r.id)?.status),['ENDED','ENDED','SUBMITTED']);
});
