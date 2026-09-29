import {randomBytes,randomInt,createHash,timingSafeEqual} from 'node:crypto';
const hash=s=>createHash('sha256').update(s).digest('hex');
export class PairingGate{
 constructor({store,now=Date.now}={}){this.store=store;this.now=now;this.pending=null;this.store.data.mobilePairs ||= {};}
 invite(udid){if(!udid)throw new Error('請先在 Mac 連線要操作的 iPhone。');const code=String(randomInt(1000000)).padStart(6,'0');this.pending={hash:hash(code),udid,until:this.now()+300000,failures:0};return {code,expiresAt:new Date(this.pending.until).toISOString()};}
 pair(code){const p=this.pending;if(!p||p.until<=this.now()||p.failures>=5)throw new Error('配對碼已失效，請在 Mac 重新產生。');
 const candidate=hash(String(code));if(!timingSafeEqual(Buffer.from(candidate),Buffer.from(p.hash))){p.failures++;throw new Error('配對碼錯誤。');}
 const token=randomBytes(32).toString('base64url');const identity=hash(token);this.store.data.mobilePairs[identity]={udid:p.udid,createdAt:this.now(),expiresAt:this.now()+30*86400000};this.pending=null;this.store.save();return token;}
 authorize(header){const token=typeof header==='string'&&/^Bearer [A-Za-z0-9_-]{43}$/.test(header)?header.slice(7):'';const identity=hash(token),pair=this.store.data.mobilePairs[identity];if(!token||!pair||pair.expiresAt<=this.now())throw new Error('尚未配對或配對已失效，請重新配對。');return{identity,...pair};}
 revoke(identity){delete this.store.data.mobilePairs[identity];this.store.save();}
 revokeAll(){this.pending=null;this.store.data.mobilePairs={};this.store.save();}
}
