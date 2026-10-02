import {load} from 'cheerio';
import {createHash} from 'node:crypto';
import {couponUrl} from './catalog.mjs';
export const WEBSITE='https://uxux11.github.io/funbox-line/';
export const CATALOG_SOURCES=Object.freeze({funbox:WEBSITE,beybladehunter:'https://beybladehunter.com/api/funbox/data'});
const hash=s=>createHash('sha256').update(s).digest('hex');
export function allowed(raw){try{const u=new URL(raw);return u.protocol==='https:'&&['lin.ee','liff.line.me','line.me'].includes(u.hostname)&&!u.username&&!u.password&&!u.port&&u.pathname!=='/';}catch{return false;}}
export function canonical(raw){try{return couponUrl(raw);}catch{return null;}}
export function schedule(label){
 const cleaned=label.replaceAll('：',':').replaceAll('／','/').replace(/[（(](?:星期|週|周)?[一二三四五六日天][）)]/gu,' ');
 const clause=cleaned.split(/[｜|；;\n]/u).find(x=>/抽[選籤]/u.test(x));if(!clause)return [null,null];
 const tail=clause.slice(clause.search(/抽[選籤]/u));const date='(\\d{4})/(\\d{1,2})/(\\d{1,2})\\s+(\\d{1,2}):(\\d{2})';
 const first=new RegExp(date,'u').exec(tail);if(!first)return[null,null];
 const parse=m=>{if(!m)return null;const p=m.slice(1,6).map(Number);const utc=Date.UTC(p[0],p[1]-1,p[2],p[3]-8,p[4]);const taipei=new Date(utc+8*3600000);return [taipei.getUTCFullYear(),taipei.getUTCMonth()+1,taipei.getUTCDate(),taipei.getUTCHours(),taipei.getUTCMinutes()].every((n,i)=>n===p[i])?new Date(utc).toISOString():null;};
 const remaining=tail.slice(first.index+first[0].length);const end=new RegExp('^\\s*[~～至到－—–-]\\s*'+date,'u').exec(remaining);
 const startAt=parse(first),endAt=parse(end);if(startAt&&endAt&&Date.parse(endAt)<=Date.parse(startAt))throw new Error('抽選起訖時間衝突。');return[startAt,endAt];
}
export function parseWebsite(html){
 if(Buffer.byteLength(html)>2_000_000)throw new Error('來源頁面過大。');
 const $=load(html);const stores=$('#page-draws .draw-store');if(!stores.length)throw new Error('找不到抽選區，保留前次清單。');
 const rows=[],seen=new Set();
 for(const store of stores.toArray()){
  const node=$(store),name=node.find('.draw-store-name').first().text().trim(),city=node.attr('data-draw-city')||'未分類',timeLabel=node.find('.draw-start').first().text();
  const items=node.find('.draw-item'),[startsAt,endsAt]=schedule(timeLabel);
  if(!name||name.length>=200||!items.length)throw new Error('店家抽選資料不完整。');
  for(const item of items.toArray()){
   const n=$(item);
   // 純販售說明沒有操作標記；殘缺的抽選列不能當成說明略過。
   const actionable=['data-draw-id','data-draw-href','onclick','onkeydown'].some(key=>n.attr(key)!==undefined)||n.hasClass('draw-item-clickable')||n.attr('role')==='link'||n.find('a[href], button').length>0;
   const display=n.find('.draw-product').first().text().trim();
   if(!actionable&&display&&display.length<500)continue;
   const sourceID=(n.attr('data-draw-id')||'').trim(),url=(n.attr('data-draw-href')||'').trim(),product=n.find('.draw-product').first().text().trim();
   if(!sourceID||seen.has(sourceID)||!product||product.length>=500||!allowed(url))throw new Error('抽選列缺漏、重複或網址異常。');seen.add(sourceID);
   const canonicalURL=canonical(url),parts=canonicalURL?new URL(canonicalURL).pathname.split('/'):null;
   rows.push({id:sourceID+':'+hash(url).slice(0,16),activityKey:parts?`coupon:${parts[1]}:${parts[3]}`:'url:'+hash(name+'\n'+url+'\n'+timeLabel),store:name,city,product,url,canonicalURL,timeLabel,startsAt,endsAt,ordinal:rows.length,archived:false,area:'website'});
  }
 }
 if(!rows.length||rows.length>5000)throw new Error('抽選筆數異常。');return rows;
}
export function parseHunter(payload){
 if(Buffer.byteLength(payload)>2_000_000)throw new Error('來源資料過大。');
 const input=JSON.parse(payload);if(!Array.isArray(input.draws)||input.draws.length>5000)throw new Error('抽選資料格式異常。');
 const ids=new Set();
 return input.draws.map((r,index)=>{
  const id=String(r.id);if(!/^[1-9][0-9]{0,18}$/.test(id)||BigInt(id)>9223372036854775807n||(typeof r.id==='number'&&!Number.isSafeInteger(r.id))||ids.has(id))throw new Error('來源 ID 無效或重複。');ids.add(id);
  const text=(key,limit)=>{if(typeof r[key]!=='string'||!r[key].trim()||r[key].length>limit)throw new Error('活動資料不完整。');return r[key].trim();};
  const date=key=>{const raw=r[key];if(raw==null||typeof raw==='string'&&!raw.trim())return null;if(typeof raw!=='string'||!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(raw))throw new Error('活動時間格式異常。');const d=new Date(raw.replace(' ','T')+'+08:00');if(!Number.isFinite(d.getTime())||new Date(d.getTime()+8*3600000).toISOString().slice(0,19)!==raw.replace(' ','T'))throw new Error('活動時間格式異常。');return d.toISOString();};
  const store=text('store_name',255),city=text('city',50),product=text('product_name',500),url=text('line_url',2000),startsAt=date('start_time'),endsAt=date('end_time');
  if(!allowed(url)||startsAt&&endsAt&&Date.parse(endsAt)<Date.parse(startsAt))throw new Error('抽選連結或時間異常。');
  const format=raw=>raw?.trim()?raw.slice(0,16).replaceAll('-','/'):null;
  const timeLabel=`抽選時間：${format(r.start_time)||'開始時間未提供'}~${format(r.end_time)||'結束時間未提供'}`;
  const canonicalURL=canonical(url),parts=canonicalURL?new URL(canonicalURL).pathname.split('/'):null;
  return{id:'catalog:beybladehunter:'+id+':'+hash(url).slice(0,16),activityKey:parts?`coupon:${parts[1]}:${parts[3]}`:'url:'+hash(store+'\n'+url+'\n'+timeLabel),store,city,product,url,canonicalURL,timeLabel,startsAt,endsAt,ordinal:index,archived:false,area:'website'};
 });
}
async function limited(response,limit){let size=0;const chunks=[];for await(const chunk of response.body){size+=chunk.length;if(size>limit){await response.body.cancel().catch(()=>{});throw new Error('來源回應過大。');}chunks.push(chunk);}return Buffer.concat(chunks).toString('utf8');}
export async function resolveLink(raw,fetchImpl=fetch,signal){
 let url=raw;const seen=new Set();for(let i=0;i<5;i++){
  if(canonical(url))return canonical(url);if(!allowed(url)||seen.has(url))throw new Error('抽選連結導向異常。');seen.add(url);
  const response=await fetchImpl(url,{redirect:'manual',signal:signal?AbortSignal.any([signal,AbortSignal.timeout(15000)]):AbortSignal.timeout(15000)});await response.body?.cancel();
  const location=response.headers.get('location');if(response.status<300||response.status>=400||!location)throw new Error('連結尚無法解析。');url=new URL(location,url).href;
 }throw new Error('抽選連結重新導向過多。');
}
export async function fetchWebsite(fetchImpl=fetch,{signal,source="funbox"}={}){
 if(!Object.hasOwn(CATALOG_SOURCES,source))throw new Error('不支援的清單來源。');
 const response=await fetchImpl(CATALOG_SOURCES[source],{redirect:'error',signal:signal?AbortSignal.any([signal,AbortSignal.timeout(20000)]):AbortSignal.timeout(20000)});if(!response.ok)throw new Error('網站同步失敗。');
 const payload=await limited(response,2_000_000);const rows=source==='funbox'?parseWebsite(payload):parseHunter(payload);const unique=[...new Set(rows.map(x=>x.url))],resolved=new Map();
 for(let i=0;i<unique.length;i+=4){signal?.throwIfAborted();const results=await Promise.allSettled(unique.slice(i,i+4).map(async u=>[u,await resolveLink(u,fetchImpl,signal)]));for(const result of results)if(result.status==='fulfilled')resolved.set(...result.value);}
 signal?.throwIfAborted();
 for(const row of rows){const url=resolved.get(row.url);if(url){row.canonicalURL=url;const p=new URL(url).pathname.split('/');row.activityKey=`coupon:${p[1]}:${p[3]}`;}}
 const owners=new Map();for(const row of rows){if(owners.has(row.activityKey)&&owners.get(row.activityKey)!==row.store)throw new Error('同一活動的店家資料衝突。');owners.set(row.activityKey,row.store);}return rows;
}
export function ready(row,now=Date.now()){return !row.archived&&canonical(row.canonicalURL)&&Number.isFinite(Date.parse(row.startsAt))&&Number.isFinite(Date.parse(row.endsAt))&&Date.parse(row.startsAt)<=now&&now<Date.parse(row.endsAt);}
export function matches(row,filter,now=Date.now()){
 if(filter.cities?.length&&!filter.cities.includes(row.city))return false;
 if(filter.query&&!`${row.store} ${row.product} ${row.city}`.toLowerCase().includes(filter.query.toLowerCase()))return false;
 return !filter.statuses?.length||filter.statuses.some(s=>s==='ready'&&ready(row,now)||s==='notStarted'&&Date.parse(row.startsAt)>now||s==='unknown'&&(!row.startsAt||!row.endsAt)||s==='expired'&&Date.parse(row.endsAt)<=now||s==='archived'&&row.archived);
}
export function continuationRows(rows,{seen,filter,record,now=Date.now()}){return rows.filter(row=>ready(row,now)&&!seen.has(row.activityKey)&&matches(row,filter,now)&&!record(row.activityKey));}
