import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {FIVE_LINKS, validateCatalog, eligibility, couponUrl} from '../src/catalog.mjs';
import {classify, parseSource, closeTarget} from '../src/screen.mjs';
import {Store} from '../src/store.mjs';
import {Engine} from '../src/engine.mjs';
import {NotDispatched} from '../src/appium.mjs';
import {node, page} from './helpers.mjs';
const now = Date.parse('2026-09-26T12:00:00+08:00');

test('five-link order and identities preserve the owner-provided pilot catalog',()=>{
  // Historical pilot values, independent of the Android checkout and runtime catalog.
  const expected=[
    ['https://lin.ee/WGMIH4U','01M34QPHTDYX6TQ5F0M5TKP5J7'],
    ['https://lin.ee/niRxKxI','01M34QQ7QZNTMR8M7ADSWXY7AW'],
    ['https://lin.ee/Q8gr93W','01M34QQXZ27VBQPSY134CD6FG4'],
    ['https://lin.ee/x2IpNpc','01M34QRHHTGYP0NZ594RCR9Z6T'],
    ['https://lin.ee/TCxN08P','01M34QS2Y5Z75XA9E8ED6SWBD4'],
  ];
  assert.deepEqual(FIVE_LINKS.map(row=>[row.shortUrl,new URL(row.url).pathname.split('/').at(-1)]),expected);
  assert.deepEqual(FIVE_LINKS.map(row=>row.id),expected.map(([,coupon])=>`coupon:1654883387-DxN9w07M:${coupon}`));
  assert.equal(validateCatalog(FIVE_LINKS).length,5);
});
test('Taipei opening and exclusive closing boundary are independent of Mac timezone',()=>{
  const row=FIVE_LINKS[0];assert.equal(eligibility(row,Date.parse('2026-09-21T15:59:59Z')),'NOT_STARTED');
  assert.equal(eligibility(row,Date.parse('2026-09-21T16:00:00Z')),'READY');
  assert.equal(eligibility(row,Date.parse('2026-09-27T16:00:00Z')),'READY');
  assert.equal(eligibility(row,Date.parse('2026-09-29T15:59:59Z')),'READY');
  assert.equal(eligibility(row,Date.parse('2026-09-29T16:00:00Z')),'EXPIRED');
});
test('catalog rejects ambiguous times, duplicate coupons and non-coupon URLs',()=>{
  assert.throws(()=>validateCatalog([FIVE_LINKS[0],FIVE_LINKS[0]]));
  assert.throws(()=>validateCatalog([{...FIVE_LINKS[0],startsAt:'2026-09-22 00:00:00'}]));
  for(const url of ['http://liff.line.me/a/c/b','https://liff.line.me.evil.test/a/c/b','https://user@liff.line.me/a/c/b','https://liff.line.me/a/c/b?x=1','https://liff.line.me/a/c/b#x','https://lin.ee/WGMIH4U','file:///a'])assert.throws(()=>couponUrl(url));
});
for(const [label,kind,action] of [['抽選','click','SUBMIT'],['加入好友並參加抽獎','click','ADD_FRIEND_AND_SUBMIT'],['加入好友','click','ADD_FRIEND'],['查看已領取的優惠券','already'],['已結束','ended'],['恭喜中獎','complete']]){
  test(`recognizes ${label}`,()=>{const d=classify(page([label]));assert.equal(d.kind,kind);if(action)assert.equal(d.action,action);});
}
test('disabled ended button still skips, disabled draw cannot submit',()=>{
  assert.equal(classify(page([node('已結束',{enabled:false})])).kind,'ended');
  assert.equal(classify(page([node('抽選',{enabled:false})])).kind,'wait');
});
test('does not tap body copy or redeem/view-my-coupons',()=>{
  for(const label of ['抽選說明','查看我的優惠券','立即使用','兌換','使用優惠券'])assert.notEqual(classify(page([label])).kind,'click');
  assert.equal(classify(page([node('抽選',{rect:{x:0,y:100,width:100,height:20}})])).kind,'wait');
});
test('reopened won coupon skips its bottom redemption button without redeeming',()=>{
  assert.equal(classify(page(['使用優惠券'])).kind,'already');
  assert.equal(classify(page([node('使用優惠券',{rect:{x:0,y:100,width:100,height:20}})])).kind,'wait');
  assert.notEqual(classify(page([],{nodes:[node('使用優惠券')]})).kind,'already');
});
test('reopened losing coupon skips disabled result, ignoring other coupon recommendations',()=>{
  const screen=page([node('已領取',{type:'XCUIElementTypeSwitch',enabled:false}),node('可惜...沒有抽中！',{enabled:false})]);
  assert.equal(classify(screen).kind,'complete');
  assert.equal(classify(page([node('可惜…沒有抽中！',{enabled:false})])).kind,'complete');
  assert.equal(classify(page([node('可惜...沒有抽中！',{enabled:false,rect:{x:0,y:100,width:100,height:20}})])).kind,'wait');
});
test('nested button/static label is one target; two separate buttons pause',()=>{
  assert.equal(classify(page([node('抽選'),node('抽選',{type:'XCUIElementTypeStaticText',rect:{x:50,y:735,width:100,height:22}})])).kind,'click');
  assert.equal(classify(page([node('抽選'),node('立即抽獎',{rect:{x:0,y:790,width:390,height:50}})])).kind,'pause');
});
test('foreign app, system alerts and login/captcha pause',()=>{
  assert.equal(classify(page(['抽選'],{bundleId:'com.apple.springboard'})).kind,'pause');
  for(const label of ['請輸入驗證碼','登入','CAPTCHA'])assert.equal(classify(page([label,'抽選'])).kind,'pause');
  assert.equal(classify(page([node('確認',{type:'XCUIElementTypeAlert'}),'抽選'])).kind,'pause');
});
test('friend consent and exact whitespace-normalized labels',()=>{
  assert.equal(classify(page(['加入好友並參加抽獎']),{autoFriend:false}).kind,'pause');
  assert.equal(classify(page([' 加入好友\n並參加抽獎 '])).action,'ADD_FRIEND_AND_SUBMIT');
});
test('OCR requires high-confidence known bottom text',()=>{
  assert.equal(classify(page([node('抽選',{source:'ocr',confidence:.95})])).kind,'click');
  assert.equal(classify(page([node('抽選',{source:'ocr',confidence:.7})])).kind,'wait');
  assert.equal(classify(page([node('抽選',{source:'ocr',confidence:.99,rect:{x:0,y:300,width:100,height:50}})])).kind,'wait');
});
test('XML reads escaped labels and excludes hidden subtrees, rejects malformed/entity sources',()=>{
  const xml='<AppiumAUT><XCUIElementTypeApplication><XCUIElementTypeButton label="加入好友&amp;測試" enabled="true" visible="true" x="0" y="700" width="390" height="50"/><XCUIElementTypeOther visible="false"><XCUIElementTypeButton label="抽選" visible="true"/></XCUIElementTypeOther></XCUIElementTypeApplication></AppiumAUT>';
  const nodes=parseSource(xml);assert.ok(nodes.some(n=>n.labels.includes('加入好友&測試')));assert.ok(!nodes.some(n=>n.labels.includes('抽選')));
  assert.throws(()=>parseSource('<broken'));assert.throws(()=>parseSource('<!DOCTYPE x><x/>'));
});
test('only recognized coupon top native close button is used',()=>{
  const target=node('關閉',{rect:{x:330,y:35,width:40,height:40}});assert.ok(closeTarget(page([target])));
  assert.equal(closeTarget(page([target],{nodes:[target]})),null);
});
test('real LINE WebView wrapper does not hide visible coupon action or close control',()=>{
  const xml=fs.readFileSync(new URL('./fixtures/line-ios27-coupon.xml',import.meta.url),'utf8');
  const screen=page([],{height:956,width:440,nodes:parseSource(xml)});
  assert.equal(classify(screen).action,'SUBMIT');
  assert.equal(classify(screen).target.rect.y,866);
  assert.equal(closeTarget(screen).labels[0],'關閉');
  for(const changed of [
    xml.replace('<XCUIElementTypeWindow visible="true"','<XCUIElementTypeWindow visible="false"'),
    xml.replace('<XCUIElementTypeWebView visible="true"','<XCUIElementTypeWebView visible="false"'),
    xml.replace('<XCUIElementTypeOther visible="false" accessible="false"','<XCUIElementTypeOther label="hidden panel" visible="false" accessible="false"'),
    xml.replace('enabled="true" visible="true" accessible="true" x="0" y="866"','enabled="true" visible="false" accessible="true" x="0" y="866"'),
  ]) assert.notEqual(classify({...screen,nodes:parseSource(changed)}).kind,'click');
});
test('status-bar clock changes are excluded from navigation evidence',()=>{
  const source=clock=>`<AppiumAUT><XCUIElementTypeApplication><XCUIElementTypeStatusBar visible="true"><XCUIElementTypeStaticText label="${clock}" visible="true"/></XCUIElementTypeStatusBar><XCUIElementTypeButton label="抽選" visible="true" x="0" y="720" width="390" height="60"/></XCUIElementTypeApplication></AppiumAUT>`;
  assert.deepEqual(parseSource(source('10:00')),parseSource(source('10:01')));
});

function fixture(t, {pages = [page(['抽選'])], tapError, openBaseline='previous-page', mutateTap, wallClock=()=>now}={}) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'linedraw-test-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const store=new Store(dir);let time=0;const calls={open:[],tap:[]};let snapshotIndex=0;
  const driver={async open(url,canAct){if(!canAct())throw new NotDispatched('stopped');calls.open.push(url);return openBaseline;},
    async snapshot(){return pages[Math.min(snapshotIndex++,pages.length-1)];},
    async tap(target,canAct){if(mutateTap)await mutateTap();if(!canAct())throw new NotDispatched('stopped');calls.tap.push(target);if(tapError)throw tapError;}};
  const engine=new Engine({driver,store,clock:()=>time,wallClock,delay:async ms=>{time+=ms;},pollMs:10,settleMs:0,loadMs:100});
  return {engine,store,calls,dir};
}
test('submission advances all five immediately without waiting for result',async t=>{
  const f=fixture(t);f.engine.start(FIVE_LINKS,{scope:'phoneA'});await f.engine.worker;
  assert.equal(f.engine.state,'COMPLETED');assert.equal(f.calls.tap.length,5);assert.deepEqual(f.calls.open,FIVE_LINKS.map(i=>i.url));
  assert.ok(FIVE_LINKS.every(i=>f.store.record('phoneA',i.id).status==='SUBMITTED'));
});
test('already/ended advance queue without clicking',async t=>{
  const f=fixture(t,{pages:[page(['查看已領取的優惠券']),page(['查看已領取的優惠券']),page([node('已結束',{enabled:false})]),page([node('已結束',{enabled:false})])]});
  f.engine.start(FIVE_LINKS.slice(0,2),{scope:'a'});await f.engine.worker;assert.equal(f.calls.tap.length,0);assert.equal(f.store.record('a',FIVE_LINKS[1].id).status,'ENDED');
});
test('standalone add friend reopens coupon and submits once',async t=>{
  const f=fixture(t,{pages:[page(['加入好友']),page(['加入好友']),page(['抽選']),page(['抽選'])]});
  f.engine.start([FIVE_LINKS[0]],{scope:'a'});await f.engine.worker;assert.equal(f.calls.open.length,2);assert.equal(f.calls.tap.length,2);assert.equal(f.store.record('a',FIVE_LINKS[0].id).status,'SUBMITTED');
});
test('stale identical previous page is never clicked; reopen once then skip',async t=>{
  const p=page(['抽選']);const f=fixture(t,{pages:[p],openBaseline:p.fingerprint});
  f.engine.start([FIVE_LINKS[0]],{scope:'a'});await f.engine.worker;assert.equal(f.calls.tap.length,0);assert.equal(f.calls.open.length,2);assert.equal(f.store.record('a',FIVE_LINKS[0].id).status,'LOAD_TIMEOUT');
});
test('brief SpringBoard transition waits for LINE without counting it as a new coupon',async t=>{
  const spring=page([],{bundleId:'com.apple.springboard'}),coupon=page(['抽選']);
  const f=fixture(t,{pages:[spring,coupon,coupon]});f.engine.navigationGraceMs=20;
  f.engine.start([FIVE_LINKS[0]],{scope:'a'});await f.engine.worker;assert.equal(f.calls.tap.length,1);
  const stale=fixture(t,{pages:[spring,coupon],openBaseline:coupon.fingerprint});stale.engine.navigationGraceMs=20;
  stale.engine.start([FIVE_LINKS[0]],{scope:'a'});await stale.engine.worker;assert.equal(stale.calls.tap.length,0);
});
test('persistent SpringBoard or another foreground app pauses without clicking',async t=>{
  for(const bundleId of ['com.apple.springboard','com.apple.mobilesafari']){
    const f=fixture(t,{pages:[page([],{bundleId})]});f.engine.navigationGraceMs=20;
    f.engine.start([FIVE_LINKS[0]],{scope:'a'});await f.engine.worker;
    assert.equal(f.engine.state,'PAUSED');assert.equal(f.calls.tap.length,0);
  }
});
test('unknown loading page times out without unsafe generic taps',async t=>{
  const f=fixture(t,{pages:[page(['載入中'])]});f.engine.start([FIVE_LINKS[0]],{scope:'a'});await f.engine.worker;assert.equal(f.calls.tap.length,0);assert.equal(f.calls.open.length,2);
});
test('uncertain click response pauses and persists review across restart; never resubmits',async t=>{
  const f=fixture(t,{tapError:new Error('USB disconnected')});f.engine.start(FIVE_LINKS.slice(0,2),{scope:'a'});await f.engine.worker;
  assert.equal(f.engine.state,'PAUSED');assert.equal(f.store.record('a',FIVE_LINKS[0].id).status,'REVIEW');assert.equal(f.calls.tap.length,1);
  const restored=new Store(f.dir);assert.equal(restored.record('a',FIVE_LINKS[0].id).status,'REVIEW');
});
test('transient element lookup failure reacquires without duplicate dispatch',async t=>{
  const f=fixture(t);let preflights=0,dispatched=0;
  f.engine.driver.tap=async()=>{preflights++;if(preflights===1)throw new NotDispatched('element rebuilt',{retryable:true});dispatched++;};
  f.engine.start([FIVE_LINKS[0]],{scope:'a'});await f.engine.worker;
  assert.equal(preflights,2);assert.equal(dispatched,1);assert.equal(f.engine.state,'COMPLETED');
  assert.equal(f.store.record('a',FIVE_LINKS[0].id).status,'SUBMITTED');
  assert.equal(f.store.data.events.filter(e=>e.code==='RETARGET').length,1);
});
test('persistent pre-dispatch ambiguity stops after two reacquisitions',async t=>{
  const f=fixture(t);let preflights=0;
  f.engine.driver.tap=async()=>{preflights++;throw new NotDispatched('ambiguous',{retryable:true});};
  f.engine.start(FIVE_LINKS.slice(0,2),{scope:'a'});await f.engine.worker;
  assert.equal(preflights,3);assert.equal(f.engine.state,'PAUSED');assert.equal(f.calls.open.length,1);
  assert.equal(f.store.record('a',FIVE_LINKS[0].id),undefined);
});
test('crash after intent is retained as review on restart',t=>{
  const f=fixture(t);f.store.setRecord('a',FIVE_LINKS[0].id,'SUBMIT_INTENT');const restored=new Store(f.dir);assert.equal(restored.record('a',FIVE_LINKS[0].id).status,'REVIEW');
});
test('pause while click validation is pending prevents dispatch and removes unexecuted intent',async t=>{
  let engine;const f=fixture(t,{mutateTap:async()=>engine.pause()});engine=f.engine;
  engine.start([FIVE_LINKS[0]],{scope:'a'});await engine.worker;assert.equal(f.calls.tap.length,0);assert.equal(f.store.record('a',FIVE_LINKS[0].id),undefined);
});
test('record identity is isolated by phone/profile; submitted items are not repeated',async t=>{
  const f=fixture(t);f.store.setRecord('a',FIVE_LINKS[0].id,'SUBMITTED');f.engine.start(FIVE_LINKS.slice(0,2),{scope:'a'});await f.engine.worker;assert.equal(f.calls.tap.length,1);
  f.engine.start([FIVE_LINKS[0]],{scope:'b'});await f.engine.worker;assert.equal(f.calls.tap.length,2);
});
test('never starts expired queue or a second simultaneous worker',async t=>{
  const f=fixture(t,{wallClock:()=>Date.parse('2026-09-30T00:00:00Z')});assert.throws(()=>f.engine.start(FIVE_LINKS,{scope:'a'}));
  const g=fixture(t);g.engine.start(FIVE_LINKS,{scope:'a'});assert.throws(()=>g.engine.start(FIVE_LINKS,{scope:'a'}));g.engine.stop();await g.engine.worker;assert.equal(g.calls.tap.length,0);
});
