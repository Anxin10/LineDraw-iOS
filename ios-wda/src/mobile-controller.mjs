import {createHash} from 'node:crypto';
import {Engine} from './engine.mjs';
import {couponUrl} from './catalog.mjs';
import {ready,continuationRows,fetchWebsite,WEBSITE} from './mobile-catalog.mjs';
const recordKey=id=>typeof id==='string'&&/^(coupon:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+|url:[a-f0-9]{64})$/.test(id);
const digest=s=>createHash('sha256').update(s).digest('hex');
const blocked=status=>['SUBMITTED','COMPLETE','ALREADY','MANUAL','REVIEW','ENDED'].includes(status)||status?.endsWith('_INTENT');
const idle=()=>({state:'IDLE',reason:'尚未開始批次。',index:0,total:0,busy:false,current:null,queue:[]});
export class MobileController{
 constructor({store,getDriver,isLegacyBusy=()=>false,fetchCatalog=signal=>fetchWebsite(fetch,{signal}),online,engineOptions={}}){
  Object.assign(this,{store,getDriver,isLegacyBusy,fetchCatalog,engineOptions});this.engine=null;this.worker=null;this.run=null;this.busyMutation=false;
  this.store.data.mobileCatalog ||= {};this.store.data.mobileUndo ||= {};this.store.data.mobileMutations ||= {};this.store.data.mobileRequests ||= {};
  this.online=online||this.probe.bind(this);this.networkAt=0;this.networkOK=true;
  // A restarted companion does not resume control, and uncertain intent records were recovered by Store.
  if(this.store.data.mobileRun){this.store.event('MOBILE_RECOVERED',null,'上次批次中斷；需由使用者重新選取尚未處理項目。');this.store.data.mobileRun=null;this.store.save();}
 }
 context(pair,body){const profile=String(body.profile||'預設');const area=body.area;
  if(!profile.trim()||profile.length>80||profile.startsWith('__')||/[\r\n\u0000]/u.test(profile)||!['website','test'].includes(area))throw new Error('設定檔或清單類型不正確。');
  return {profile,area,scope:digest(`mobile\n${pair.udid}\n${profile}\n${area}`)};
 }
 get locked(){return !!this.worker||this.engine?.state==='PAUSED';}
 view(pair,body){const context=this.context(pair,body);const same=this.run?.scope===context.scope&&this.run?.owner===pair.identity;
  const engine=same&&this.engine?{...this.engine.view(),busy:!!this.worker||!!this.engine.worker}:idle();
  if(this.locked&&!same){engine.state='PAUSED';engine.reason='另一份設定檔正在執行，請先在 Mac 停止。';engine.busy=true;}
  const catalog=this.store.data.mobileCatalog[context.scope]||{};
  const prefix=context.scope+'\n';
  const records=Object.entries(this.store.data.records).filter(([key])=>key.startsWith(prefix)).map(([key,r])=>({id:key.slice(prefix.length),product:catalog[key.slice(prefix.length)]?.product||'活動',store:catalog[key.slice(prefix.length)]?.store||'',...r}));
  return{connected:!!this.getDriver()?.sessionId&&this.getDriver()?.udid===pair.udid,engine,records,profile:context.profile,area:context.area,round:same?this.run.round:0,diagnostics:same?this.store.data.events.filter(e=>e.at>=this.run.startedAt).slice(-100):[]};
 }
 editable(){if(this.locked||this.isLegacyBusy()||this.busyMutation)throw new Error('請先停止目前批次，再變更清單或紀錄。');}
 driver(pair){const driver=this.getDriver();if(!driver?.sessionId||driver.udid!==pair.udid)throw new Error('請在 Mac 連線到配對時的 iPhone。');return driver;}
 validateRows(rows,area){if(!Array.isArray(rows)||!rows.length||rows.length>5000)throw new Error('清單筆數不正確。');const seen=new Set();
  return rows.map((r,index)=>{if(typeof r.id!=='string'||!r.id||r.id.length>300||seen.has(r.id)||r.area!==area||typeof r.product!=='string'||r.product.length>500||typeof r.store!=='string'||r.store.length>200)throw new Error('清單資料不正確。');seen.add(r.id);
   const canonicalURL=r.canonicalURL?couponUrl(r.canonicalURL):null;const parts=canonicalURL?new URL(canonicalURL).pathname.split('/'):null;
   if(parts&&r.activityKey!==`coupon:${parts[1]}:${parts[3]}`)throw new Error('活動識別與連結不符。');
   for(const field of ['startsAt','endsAt'])if(r[field]!=null&&(typeof r[field]!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(r[field])||!Number.isFinite(Date.parse(r[field]))))throw new Error('時間缺少時區或格式不正確。');
   if(r.startsAt&&r.endsAt&&Date.parse(r.endsAt)<=Date.parse(r.startsAt))throw new Error('活動起訖時間不正確。');
   return{...r,canonicalURL,ordinal:index};});
 }
 engineRows(rows){return rows.map(row=>({title:row.product,url:row.canonicalURL,startsAt:row.startsAt,endsAt:row.endsAt}));}
 start(pair,body){
  const context=this.context(pair,body);if(body.accepted!==true)throw new Error('請先同意本次抽選操作。');
  if(typeof body.requestID!=='string'||!/^[a-f\d-]{36}$/i.test(body.requestID))throw new Error('缺少批次請求識別。');
  const requestKey=pair.identity+':'+body.requestID;
  if(this.store.data.mobileRequests[requestKey])return this.view(pair,body); // response-loss retry must never run twice
  this.editable();const driver=this.driver(pair);const rows=this.validateRows(body.rows,context.area);
  if(!Array.isArray(body.selectedIDs)||!body.selectedIDs.length||body.selectedIDs.some(id=>!rows.some(r=>r.id===id)))throw new Error('請選擇有效活動。');
  const filter=body.filter||{};if(!Array.isArray(filter.cities)||!Array.isArray(filter.statuses)||typeof filter.query!=='string'||filter.query.length>500||filter.cities.some(c=>typeof c!=='string'||c.length>200)||filter.statuses.some(s=>!['ready','notStarted','unknown','recorded','expired','archived'].includes(s)))throw new Error('篩選格式不正確。');
  const selected=rows.filter(r=>body.selectedIDs.includes(r.id));if(selected.some(r=>!ready(r)))throw new Error('部分活動尚未開始、已截止或連結未解析。');
  // Incoming records can only add a terminal history; they never overwrite or erase Mac evidence.
  if(!Array.isArray(body.records)||body.records.length>20000)throw new Error('紀錄格式不正確。');
  const seeds=[];for(const r of body.records){if(!recordKey(r.id)||!blocked(r.status))continue;seeds.push(r);}
  for(const r of seeds)if(!this.store.record(context.scope,r.id))this.store.data.records[this.store.key(context.scope,r.id)]={status:r.status.endsWith('_INTENT')?'REVIEW':r.status,reason:'由配對手機匯入既有完成紀錄。',at:new Date().toISOString()};
  const unique=new Set();const runRows=selected.filter(r=>{if(unique.has(r.activityKey)||blocked(this.store.record(context.scope,r.activityKey)?.status))return false;unique.add(r.activityKey);return true;});
  if(!runRows.length){this.store.save();throw new Error('所選活動已有紀錄，沒有可執行項目。');}
  this.store.data.mobileCatalog[context.scope]={...(this.store.data.mobileCatalog[context.scope]||{}),...Object.fromEntries(rows.map(r=>[r.activityKey,r]))};
  this.run={...context,owner:pair.identity,requestID:body.requestID,round:0,startedAt:new Date().toISOString(),seen:new Set(rows.map(r=>r.activityKey)),filter,autoContinue:context.area==='website'&&body.autoContinue===true,autoFriend:body.autoFriend!==false};
  this.store.data.mobileRequests[requestKey]=new Date().toISOString();const keys=Object.keys(this.store.data.mobileRequests);for(const key of keys.slice(0,Math.max(0,keys.length-1000)))delete this.store.data.mobileRequests[key];
  this.store.data.mobileRun={...this.run,seen:[...this.run.seen]};this.store.save();
  this.engine=new Engine({driver,store:this.store,online:this.online,...this.engineOptions});
  this.engine.start(this.engineRows(runRows),{scope:context.scope,autoFriend:this.run.autoFriend});this.watch();return this.view(pair,body);
 }
 watch(){if(this.worker)return;this.worker=this.follow().catch(()=>{this.engine?.pause('網站接續失敗，請檢查網路後繼續。');this.store.event('CONTINUATION_FAILED');}).finally(()=>{this.worker=null;this.store.data.mobileRun=this.engine?.state==='PAUSED'?{...this.run,seen:[...this.run.seen]}:null;this.store.save();});}
 async follow(){
  await this.engine.worker;
  while(this.engine.state==='COMPLETED'&&this.run.autoContinue&&this.run.round<3){
   this.engine.state='RUNNING';this.engine.reason='本輪完成，正在同步網站新增活動。';this.store.event('CONTINUATION_SYNC');
   this.catalogAbort=new AbortController();let rows;try{rows=await this.fetchCatalog(this.catalogAbort.signal);}catch{if(this.engine.state==='RUNNING'){this.engine.state='PAUSED';this.engine.reason='網站同步失敗，紀錄保留；可停止或稍後繼續。';}return;}
   if(this.engine.state!=='RUNNING')return;
   const next=continuationRows(rows,{seen:this.run.seen,filter:this.run.filter,record:id=>this.store.record(this.run.scope,id)});
   for(const r of rows)this.run.seen.add(r.activityKey);this.run.round++;
   this.store.data.mobileCatalog[this.run.scope]={...this.store.data.mobileCatalog[this.run.scope],...Object.fromEntries(rows.map(r=>[r.activityKey,r]))};
   if(!next.length){this.engine.state='COMPLETED';this.engine.reason='本輪完成，沒有符合原篩選的新活動。';return;}
   const previous=this.engine.queue;this.engine.queue=[...previous,...this.engineRows(next).map(r=>{const p=new URL(r.url).pathname.split('/');return{...r,id:`coupon:${p[1]}:${p[3]}`};})];
   this.store.event('CONTINUATION_ADDED',null,`新增 ${next.length} 筆，第 ${this.run.round} 輪。`);this.store.save();this.engine.launch();await this.engine.worker;
  }
 }
 control(pair,body,action){const context=this.context(pair,body);if(!this.run||this.run.owner!==pair.identity||this.run.scope!==context.scope)throw new Error('這份設定檔沒有可控制的批次。');
  if(action==='pause')this.pause();else if(action==='stop')this.stop();else if(action==='resume'){this.driver(pair);if(this.worker)throw new Error('請等待目前操作結束。');this.engine.resume();this.watch();}else if(action==='skip'){this.driver(pair);if(this.worker)throw new Error('請等待目前操作結束。');this.engine.skip();this.watch();}else throw new Error('不支援的控制指令。');return this.view(pair,body);
 }
 mutate(pair,mutations){this.editable();if(!Array.isArray(mutations)||mutations.length>1000)throw new Error('紀錄操作格式不正確。');
  // Validate and apply to a copy so a rejected mutation cannot partially commit the batch.
  const next=structuredClone(this.store.data);
  for(const m of mutations){const context=this.context(pair,m);if(!/^[a-f\d-]{36}$/i.test(m.id||'')||!recordKey(m.activityKey)||!['manual','undo'].includes(m.action))throw new Error('紀錄操作格式不正確。');
   const receipt=pair.identity+':'+m.id;if(next.mobileMutations[receipt])continue;const key=this.store.key(context.scope,m.activityKey);const old=next.records[key];
   if(m.action==='manual'){
    if(old?.status!=='MANUAL'&&old&& !['SUBMITTED','REVIEW','LOAD_TIMEOUT','ENDED','SKIPPED'].includes(old.status))throw new Error('這筆已有完成紀錄。');
    if(old?.status!=='MANUAL'){next.mobileUndo[key]={previous:old||null};next.records[key]={status:'MANUAL',reason:'使用者手動標記；不代表中獎。',at:new Date().toISOString()};}
   }else if(old?.status==='MANUAL'){
    if(!Object.hasOwn(next.mobileUndo,key))throw new Error('缺少原始紀錄，保留手動完成狀態。');const previous=next.mobileUndo[key].previous;if(previous)next.records[key]=previous;else delete next.records[key];delete next.mobileUndo[key];
   }
   next.mobileCatalog[context.scope] ||= {};next.mobileCatalog[context.scope][m.activityKey] ||= {product:String(m.product||'活動').slice(0,500),store:String(m.store||'').slice(0,200)};
   next.mobileMutations[receipt]=true;
  }
  this.store.data=next;this.store.save();return {ok:true};
 }
 async probe(){if(Date.now()-this.networkAt<5000)return this.networkOK;try{const r=await fetch(WEBSITE,{method:'HEAD',redirect:'error',signal:AbortSignal.timeout(4000)});this.networkOK=r.ok;await r.body?.cancel();}catch{this.networkOK=false;}this.networkAt=Date.now();return this.networkOK;}
 pause(){this.engine?.pause();this.catalogAbort?.abort();}
 stop(){this.engine?.stop();this.catalogAbort?.abort();}
}
