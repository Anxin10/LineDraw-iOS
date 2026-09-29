import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash, randomBytes} from 'node:crypto';
import {AppiumDriver} from './appium.mjs';
import {Engine} from './engine.mjs';
import {Store} from './store.mjs';
import {FIVE_LINKS, validateCatalog, eligibility} from './catalog.mjs';
import {classify} from './screen.mjs';
import {visionOcr} from './ocr.mjs';
import {MobileController} from './mobile-controller.mjs';
import {MobileServer} from './mobile-server.mjs';
const exec = promisify(execFile);
export const ROOT = fileURLToPath(new URL('..', import.meta.url));

export function makeServer({directory = path.join(ROOT, '.data'), driverFactory = options => new AppiumDriver(options)} = {}) {
  const store = new Store(directory);
  let catalog = validateCatalog(store.data.catalog || FIVE_LINKS);
  let driver = null; let engine = null; let connecting = false; let commandBusy = false; let scope = '';
  const token = randomBytes(24).toString('hex');
  const mobile = new MobileController({store,getDriver:()=>driver,isLegacyBusy:()=>!!engine?.worker||engine?.state==='PAUSED'||connecting||commandBusy});
  const mobileServer = new MobileServer({store,controller:mobile,getDriver:()=>driver,directory:path.join(directory,'mobile-tls')});
  const json = (res, status, value) => { res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8'}); res.end(JSON.stringify(value)); };
  function editable() { if (connecting || commandBusy || engine?.worker || engine?.state === 'PAUSED' || mobile.locked) throw new Error('請先停止批次，並等待目前指令結束。'); }
  const status = () => ({connected: !!driver?.sessionId, connecting, commandBusy,
    engine: mobile.locked ? {...mobile.engine.view(), busy: !!mobile.worker || !!mobile.engine.worker} : engine?.view() || {state: 'IDLE', reason: '尚未連線 iPhone。', index: 0, total: 0, busy: false},
    catalog: catalog.map(item => ({...item, eligibility: eligibility(item), record: scope ? store.record(scope, item.id) || null : null})),
    events: store.data.events.slice(-40), version: '1.0.0-alpha', personalPrototype: true});
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'");
    const address = server.address();
    const origin = `http://127.0.0.1:${address.port}`;
    if (req.headers.host !== `127.0.0.1:${address.port}`) return json(res, 403, {error: '只接受本機控制面板。'});
    if (req.headers.origin && req.headers.origin !== origin) return json(res, 403, {error: '拒絕外部網站請求。'});
    const route = new URL(req.url, origin).pathname;
    try {
      if (req.method === 'GET' && route === '/api/status') return json(res, 200, status());
      if (req.method === 'GET' && route === '/api/bootstrap') return json(res, 200, {token});
      if (req.method === 'GET' && ['/','/app.js','/style.css'].includes(route)) {
        const name = route === '/' ? 'index.html' : route.slice(1);
        const type = route === '/' ? 'text/html' : route.endsWith('.js') ? 'text/javascript' : 'text/css';
        res.writeHead(200, {'Content-Type': `${type}; charset=utf-8`});
        return res.end(await fs.readFile(path.join(ROOT, 'public', name)));
      }
      if (req.method !== 'POST' || !route.startsWith('/api/')) return json(res, 404, {error: '找不到此功能。'});
      if (req.headers['x-linedraw-token'] !== token || !req.headers['content-type']?.startsWith('application/json')) {
        return json(res, 403, {error: '請從本機控制面板操作。'});
      }
      const chunks = []; let bytes = 0;
      for await (const chunk of req) { bytes += chunk.length; if (bytes > 500_000) throw new Error('請求內容過大。'); chunks.push(chunk); }
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
      if (route === '/api/pause') { if(mobile.locked) mobile.pause(); else engine?.pause(); return json(res, 200, status()); }
      if (route === '/api/stop') { mobile.stop(); engine?.stop(); return json(res, 200, status()); }
      if (connecting || commandBusy) throw new Error('目前指令執行中，請稍候。');
      if (route === '/api/mobile-pair') {
        editable(); commandBusy = true;
        try { const invitation = await mobileServer.invite();
          const {stdout} = await exec('xcrun',['swift',path.join(ROOT,'native','PairingQR.swift'),invitation.uri],{timeout:30000,maxBuffer:1000000});
          return json(res,200,{...invitation,qr:stdout.trim()});
        } finally { commandBusy=false; }
      }
      if (route === '/api/mobile-revoke') { await mobileServer.disable(); return json(res,200,{ok:true}); }
      if (route === '/api/connect') {
        editable(); if (driver?.sessionId) throw new Error('請先中斷既有連線。');
        connecting = true;
        const candidate = driverFactory({baseUrl: 'http://127.0.0.1:4725',
          ocr: body.ocr ? visionOcr(path.join(ROOT, '.runtime', 'recognize')) : null});
        try {
          if (body.ocr) await fs.access(path.join(ROOT, '.runtime', 'recognize'));
          await candidate.connect(body);
          if (!await candidate.installed()) throw new Error('此 iPhone 尚未安裝 LINE。');
          driver = candidate;
          const profile = String(body.profile || 'default').trim();
          scope = createHash('sha256').update(`${body.udid}\n${profile}\nline`).digest('hex');
          engine = new Engine({driver, store});
          store.event('CONNECTED');
        } catch (error) { await candidate.disconnect().catch(() => {}); throw error; }
        finally { connecting = false; }
        return json(res, 200, status());
      }
      if (route === '/api/disconnect') {
        editable(); commandBusy = true;
        try { await driver?.disconnect(); driver = null; engine = null; scope = ''; }
        finally { commandBusy = false; }
        return json(res, 200, status());
      }
      if (route === '/api/start') {
        if (mobile.locked) throw new Error('手機 App 的批次正在執行，請先停止。');
        if (!engine || !driver?.sessionId) throw new Error('請先連線 iPhone。');
        if (body.accepted !== true) throw new Error('開始前請確認這是你要操作的 LINE 帳號，並同意自動加入好友與抽選。');
        if (!Array.isArray(body.ids) || !body.ids.length || body.ids.some(id => !catalog.some(item => item.id === id))) throw new Error('請選擇有效的抽選項目。');
        // Always preserve catalog ordering, regardless of selection order.
        engine.start(catalog.filter(item => body.ids.includes(item.id)), {scope, autoFriend: body.autoFriend !== false});
        return json(res, 200, status());
      }
      if (route === '/api/resume') {
        if(mobile.locked){if(mobile.worker) throw new Error('請等待目前指令結束。');mobile.engine.resume();mobile.watch();return json(res,200,status());}
        if (!engine) throw new Error('尚無可恢復批次。');
        engine.resume(); return json(res, 200, status());
      }
      if (route === '/api/catalog') {
        editable(); const next = validateCatalog(body.rows);
        store.data.catalog = next; store.save(); catalog = next;
        return json(res, 200, status());
      }
      if (route === '/api/five-links') {
        editable(); store.data.catalog = FIVE_LINKS; store.save(); catalog = validateCatalog(FIVE_LINKS);
        return json(res, 200, status());
      }
      if (route === '/api/record') {
        editable(); if (!scope || !catalog.some(item => item.id === body.id)) throw new Error('請先連線並選擇活動。');
        if (body.action === 'manual') store.setRecord(scope, body.id, 'MANUAL', '使用者手動標記完成。');
        else if (body.action === 'clear') store.clearRecord(scope, body.id);
        else throw new Error('不支援的紀錄操作。');
        return json(res, 200, status());
      }
      if (route === '/api/inspect') {
        if (engine?.worker || mobile.worker) throw new Error('請暫停並等待目前指令結束。');
        if (!driver?.sessionId) throw new Error('請先連線 iPhone。');
        commandBusy = true;
        try {
          const screen = await driver.snapshot();
          const decision = classify(screen);
          return json(res, 200, {bundleId: screen.bundleId, width: screen.width, height: screen.height,
            nodes: screen.nodes.length, decision: {kind: decision.kind, action: decision.action, label: decision.label, reason: decision.reason}});
        } finally { commandBusy = false; }
      }
      if (route === '/api/capture') {
        if (engine?.worker || mobile.worker) throw new Error('請暫停並等待目前指令結束。');
        if (!driver?.sessionId) throw new Error('請先連線 iPhone。');
        commandBusy = true;
        try {
          const dir = path.join(directory, 'diagnostics', new Date().toISOString().replace(/[:.]/g, '-'));
          await fs.mkdir(dir, {recursive: true, mode: 0o700});
          const screen = await driver.snapshot();
          await fs.writeFile(path.join(dir, 'source.xml'), screen.xml, {mode: 0o600});
          await fs.writeFile(path.join(dir, 'screen.png'), Buffer.from(await driver.screenshot(), 'base64'), {mode: 0o600});
          await fs.writeFile(path.join(dir, 'decision.json'), JSON.stringify({decision: classify(screen), width: screen.width, height: screen.height}, null, 2), {mode: 0o600});
          return json(res, 200, {directory: dir});
        } finally { commandBusy = false; }
      }
      if (route === '/api/devices') {
        commandBusy = true;
        try {
          const {stdout} = await exec('xcrun', ['xctrace', 'list', 'devices'], {timeout: 30_000, maxBuffer: 1_000_000});
          const devices = []; let section = '';
          for (const line of stdout.split('\n')) {
            if (line.startsWith('==')) { section = line; continue; }
            if (!section.includes('Devices') || section.includes('Offline')) continue;
            const m = line.match(/^(.*?) \(([\d.]+)\) \(([A-Fa-f\d-]+)\)$/);
            if (m && !/Watch|Mac/i.test(m[1])) devices.push({name: m[1], version: m[2], udid: m[3]});
          }
          return json(res, 200, {devices});
        } finally { commandBusy = false; }
      }
      return json(res, 404, {error: '找不到此功能。'});
    } catch (error) { json(res, 400, {error: error.message}); }
  });
  server.requestTimeout = 300_000;
  return {server, status, stop: async () => { engine?.stop(); mobile.stop(); if (engine?.worker) await engine.worker; if(mobile.worker) await mobile.worker; await mobileServer.close(); await driver?.disconnect(); }};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const {server, stop} = makeServer({directory:process.env.LINEDRAW_DATA_DIR || path.join(ROOT,'.data')});
  const port = Number(process.env.LINEDRAW_PORT || 4780);
  server.listen(port, '127.0.0.1', () => console.log(`LineDraw iOS 原型：http://127.0.0.1:${port}`));
  let stopping = false;
  const shutdown = async () => {
    if (stopping) return; stopping = true;
    server.close(); await stop().catch(() => {}); process.exit(0);
  };
  process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);
}
