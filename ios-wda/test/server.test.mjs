import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import {makeServer} from '../src/server.mjs';
import {FIVE_LINKS} from '../src/catalog.mjs';

async function fixture(t) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'linedraw-http-'));
  const {server}=makeServer({directory:dir,driverFactory:()=>({sessionId:null,async connect(){this.sessionId='test';},async installed(){return true;},async disconnect(){this.sessionId=null;}})});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  t.after(async()=>{await new Promise(resolve=>server.close(resolve));fs.rmSync(dir,{recursive:true,force:true});});
  const {token}=await(await fetch(base+'/api/bootstrap')).json();
  return {base,post:(route,body={},extra={})=>fetch(base+'/api/'+route,{method:'POST',headers:{'Content-Type':'application/json','X-LineDraw-Token':token,...extra},body:JSON.stringify(body)})};
}
test('local dashboard serves without connecting or drawing',async t=>{
  const f=await fixture(t);const r=await fetch(f.base);assert.equal(r.status,200);assert.match(await r.text(),/<title>LineDraw · Mac 輔助程式<\/title>/);
  const state=await(await fetch(f.base+'/api/status')).json();assert.equal(state.connected,false);assert.equal(state.catalog.length,5);
});
test('cross-origin, missing token and hostile Host cannot control phone',async t=>{
  const f=await fixture(t);
  assert.equal((await f.post('stop',{}, {'Origin':'https://evil.example'})).status,403);
  assert.equal((await f.post('stop',{}, {'X-LineDraw-Token':''})).status,403);
  const code=await new Promise((resolve,reject)=>http.get(f.base+'/api/bootstrap',{headers:{Host:'evil.example'}},res=>{res.resume();resolve(res.statusCode);}).on('error',reject));
  assert.equal(code,403);
});
test('start requires connection and explicit batch consent',async t=>{
  const f=await fixture(t);assert.equal((await f.post('start',{ids:[FIVE_LINKS[0].id],accepted:true})).status,400);
  assert.equal((await f.post('connect',{udid:'abcdefgh'})).status,200);
  const denied=await f.post('start',{ids:[FIVE_LINKS[0].id]});assert.equal(denied.status,400);assert.match((await denied.json()).error,/確認/);
});
test('invalid catalog import preserves last catalog',async t=>{
  const f=await fixture(t);assert.equal((await f.post('catalog',{rows:[{url:'https://evil.example'}]})).status,400);
  assert.equal((await(await fetch(f.base+'/api/status')).json()).catalog.length,5);
});
test('chunked UTF-8 JSON preserves Chinese activity names',async t=>{
  const f=await fixture(t);const {token}=await(await fetch(f.base+'/api/bootstrap')).json();
  const title='陀螺獵人抽選測試';const body=Buffer.from(JSON.stringify({rows:[{...FIVE_LINKS[0],title}]}));
  const split=body.indexOf(Buffer.from('陀'))+1;
  const value=await new Promise((resolve,reject)=>{
    const req=http.request(f.base+'/api/catalog',{method:'POST',headers:{'Content-Type':'application/json','X-LineDraw-Token':token}},res=>{
      const chunks=[];res.on('data',chunk=>chunks.push(chunk));res.on('end',()=>resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))));
    });req.on('error',reject);req.write(body.subarray(0,split));setTimeout(()=>req.end(body.subarray(split)),10);
  });
  assert.equal(value.catalog[0].title,title);
});
test('manual completion persists and can be cleared only for valid connected rows',async t=>{
  const f=await fixture(t);assert.equal((await f.post('record',{id:FIVE_LINKS[0].id,action:'manual'})).status,400);
  await f.post('connect',{udid:'abcdefgh'});
  let value=await(await f.post('record',{id:FIVE_LINKS[0].id,action:'manual'})).json();assert.equal(value.catalog[0].record.status,'MANUAL');
  value=await(await f.post('record',{id:FIVE_LINKS[0].id,action:'clear'})).json();assert.equal(value.catalog[0].record,null);
});
