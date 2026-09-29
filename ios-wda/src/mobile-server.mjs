import https from 'node:https';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {X509Certificate} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {PairingGate} from './pairing.mjs';
const exec=promisify(execFile);
export class MobileServer{
 constructor({store,controller,getDriver,directory,port=4781,host='0.0.0.0'}){Object.assign(this,{store,controller,getDriver,directory,port,host});this.gate=new PairingGate({store});this.server=null;this.fingerprint=null;}
 async enable(){if(this.server)return;
  await fs.mkdir(this.directory,{recursive:true,mode:0o700});const keyFile=path.join(this.directory,'key.pem'),certFile=path.join(this.directory,'certificate.pem');
  try{await fs.access(keyFile);await fs.access(certFile);}catch{await exec('/usr/bin/openssl',['req','-x509','-newkey','rsa:2048','-nodes','-sha256','-days','365','-subj','/CN=LineDraw Local Companion','-keyout',keyFile,'-out',certFile],{timeout:20000});await fs.chmod(keyFile,0o600);}
  const [key,cert]=await Promise.all([fs.readFile(keyFile),fs.readFile(certFile)]);this.fingerprint=new X509Certificate(cert).fingerprint256.replaceAll(':','').toLowerCase();
  const server=https.createServer({key,cert,minVersion:'TLSv1.2'},(req,res)=>this.handle(req,res));server.requestTimeout=30000;server.headersTimeout=10000;
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(this.port,this.host,resolve);});this.server=server;
 }
 async invite(){if(this.controller.locked)throw new Error('請先停止目前批次。');const driver=this.getDriver();if(!driver?.sessionId)throw new Error('請先在 Mac 連線要操作的 iPhone。');await this.enable();
  const invitation=this.gate.invite(driver.udid);
  const addresses=Object.entries(os.networkInterfaces()).flatMap(([name,items])=>(items||[]).filter(x=>x.family==='IPv4'&&!x.internal&&/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(x.address)).map(x=>({name,address:x.address}))).sort((a,b)=>(a.name==='en0'?-1:0)-(b.name==='en0'?-1:0));
  if(!addresses.length)throw new Error('Mac 尚未連接區域網路，請先連接與 iPhone 相同的 Wi-Fi。');
  const endpoint=`https://${addresses[0].address}:${this.server.address().port}`;
  const params=new URLSearchParams({endpoint,fingerprint:this.fingerprint,code:invitation.code});
  return{uri:'linedraw://pair?'+params.toString(),expiresAt:invitation.expiresAt,endpoint};
 }
 async body(req){let bytes=0;const parts=[];for await(const chunk of req){bytes+=chunk.length;if(bytes>8_000_000)throw new Error('請求過大。');parts.push(chunk);}return JSON.parse(Buffer.concat(parts).toString('utf8')||'{}');}
 async handle(req,res){
  const send=(status,value)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(value));};
  // Native clients only: do not grant browser origins CORS access to a paired control endpoint.
  if(req.headers.origin||req.headers['sec-fetch-site'])return send(403,{error:'只接受已配對 App 的請求。'});
  try{
   const url=new URL(req.url,'https://local.invalid');if(url.pathname==='/v1/pair'&&req.method==='POST'){
    if(!req.headers['content-type']?.startsWith('application/json'))throw new Error('需要 JSON 格式。');const b=await this.body(req);return send(200,{token:this.gate.pair(b.code),name:os.hostname()});
   }
   let pair;try{pair=this.gate.authorize(req.headers.authorization);}catch{return send(401,{error:'尚未配對或配對已失效，請重新配對。'});}
   if(req.method==='GET'&&url.pathname==='/v1/status')return send(200,this.controller.view(pair,Object.fromEntries(url.searchParams)));
   if(req.method!=='POST'||!req.headers['content-type']?.startsWith('application/json'))return send(404,{error:'找不到此功能。'});
   const b=await this.body(req);
   if(url.pathname==='/v1/start')return send(200,this.controller.start(pair,b));
   if(['/v1/pause','/v1/resume','/v1/stop','/v1/skip'].includes(url.pathname))return send(200,this.controller.control(pair,b,url.pathname.slice(4)));
   if(url.pathname==='/v1/records')return send(200,this.controller.mutate(pair,b));
   if(url.pathname==='/v1/unpair'){this.controller.editable();this.gate.revoke(pair.identity);return send(200,{ok:true});}
   return send(404,{error:'找不到此功能。'});
  }catch(error){return send(400,{error:error instanceof SyntaxError?'JSON 格式不正確。':error.message});}
 }
 async disable(){this.controller.stop();this.gate.revokeAll();await this.close();}
 async close(){if(this.server){const server=this.server;this.server=null;server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}}
}
