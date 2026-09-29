import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import https from 'node:https';import {X509Certificate,createHash} from 'node:crypto';
import {Store} from '../src/store.mjs';import {MobileController} from '../src/mobile-controller.mjs';import {MobileServer} from '../src/mobile-server.mjs';import {Engine} from '../src/engine.mjs';import {page} from './helpers.mjs';
function request(port,pathname,{token,body,origin}={}){return new Promise((resolve,reject)=>{const req=https.request({hostname:'127.0.0.1',port,path:pathname,method:body?'POST':'GET',rejectUnauthorized:false,headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{}),...(origin?{Origin:origin}:{})}},res=>{let raw='';res.on('data',c=>raw+=c);res.on('end',()=>resolve({status:res.statusCode,body:JSON.parse(raw)}));});req.on('error',reject);req.end(body?JSON.stringify(body):undefined);});}
function store(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'linedraw-transport-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));return new Store(dir);}
test('real TLS endpoint authenticates, rejects browser origins and never runs on pairing',async t=>{
 const s=store(t);let taps=0;const driver={udid:'fixture-device',sessionId:'fake',open:async()=> 'old',snapshot:async()=>page(['抽選']),tap:async()=>{taps++;}};let clock=0;
 const controller=new MobileController({store:s,getDriver:()=>driver,online:async()=>true,engineOptions:{clock:()=>clock,delay:async ms=>{clock+=ms;},settleMs:0,pollMs:1}});
 const server=new MobileServer({store:s,controller,getDriver:()=>driver,directory:path.join(s.directory,'tls'),host:'127.0.0.1',port:0});await server.enable();t.after(()=>server.close());const port=server.server.address().port;
 const certificate=new X509Certificate(fs.readFileSync(path.join(s.directory,'tls/certificate.pem')));assert.equal(server.fingerprint,createHash('sha256').update(certificate.raw).digest('hex'));
 assert.equal((await request(port,'/v1/status?profile=x&area=test')).status,401);
 const code=server.gate.invite(driver.udid).code;
 assert.equal((await request(port,'/v1/pair',{body:{code},origin:'https://example.com'})).status,403);
 const paired=await request(port,'/v1/pair',{body:{code}});assert.equal(paired.status,200);const token=paired.body.token;assert.equal(taps,0);
 assert.equal((await request(port,'/v1/pair',{body:{code}})).status,400);
 const status=await request(port,'/v1/status?profile=x&area=test',{token});assert.equal(status.body.connected,true);assert.equal(status.body.engine.state,'IDLE');
 const mutation={id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',profile:'x',area:'test',activityKey:'url:'+'a'.repeat(64),action:'manual'};
 assert.equal((await request(port,'/v1/records',{token,body:[mutation]})).status,200);
 const recorded=await request(port,'/v1/status?profile=x&area=test',{token});assert.equal(recorded.body.records[0].status,'MANUAL');
 assert.equal((await request(port,'/v1/unpair',{token,body:{}})).status,200);assert.equal((await request(port,'/v1/status?profile=x&area=test',{token})).status,401);
 assert.equal(taps,0);
});
test('offline wait is bounded and no link is opened before network returns',async t=>{
 const s=store(t);let clock=0,opens=0;const engine=new Engine({store:s,driver:{open:async()=>{opens++;}},clock:()=>clock,delay:async ms=>{clock+=ms},online:async()=>false,offlineMs:10,pollMs:2});
 engine.start([{title:'fixture',url:'https://liff.line.me/app/c/id',startsAt:'2020-01-01T00:00:00Z',endsAt:'2099-01-01T00:00:00Z'}],{scope:'test'});await engine.worker;assert.equal(engine.state,'PAUSED');assert.equal(opens,0);assert.equal(Object.keys(s.data.records).length,0);
});
test('skip preserves uncertain evidence and moves to next item',async t=>{
 const s=store(t);let clock=0,taps=0;const engine=new Engine({store:s,driver:{open:async()=> 'old',snapshot:async()=>page(['抽選']),tap:async()=>{taps++;}},clock:()=>clock,delay:async ms=>{clock+=ms},pollMs:1,settleMs:0});
 engine.scope='test';engine.queue=[{id:'coupon:app:one',title:'one',url:'https://liff.line.me/app/c/one'},{id:'coupon:app:two',title:'two',url:'https://liff.line.me/app/c/two',startsAt:'2020-01-01T00:00:00Z',endsAt:'2099-01-01T00:00:00Z'}];engine.state='PAUSED';s.setRecord('test','coupon:app:one','REVIEW','uncertain');engine.skip();await engine.worker;assert.equal(s.record('test','coupon:app:one').status,'REVIEW');assert.equal(taps,1);assert.equal(engine.state,'COMPLETED');
});
