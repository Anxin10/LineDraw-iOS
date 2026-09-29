const $ = id => document.getElementById(id);
let token = '', status, selection = new Set(), initialized = false, toastTimer;
const labels = {READY:'可測試',NOT_STARTED:'尚未開始',EXPIRED:'已截止',SUBMITTED:'已送出',ALREADY:'已抽過／已領取',COMPLETE:'已完成',MANUAL:'手動完成',REVIEW:'待確認',ENDED:'活動已結束',LOAD_TIMEOUT:'載入逾時',FRIEND_ADDED:'已加入好友',SUBMIT_INTENT:'送出中',ADD_FRIEND_AND_SUBMIT_INTENT:'加入好友並送出中',ADD_FRIEND_INTENT:'加入好友中'};
const states = {IDLE:'待開始',RUNNING:'執行中',PAUSED:'已暫停',STOPPED:'已停止',COMPLETED:'本輪完成'};
const terminal = ['SUBMITTED','ALREADY','COMPLETE','MANUAL','REVIEW','ENDED','SUBMIT_INTENT','ADD_FRIEND_INTENT','ADD_FRIEND_AND_SUBMIT_INTENT'];
function toast(text) { $('toast').textContent = text; $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 8000); }
async function api(route, body = {}) {
  const response = await fetch(`/api/${route}`, {method:'POST',headers:{'Content-Type':'application/json','X-LineDraw-Token':token},body:JSON.stringify(body)});
  const value = await response.json(); if (!response.ok) throw new Error(value.error || '連線失敗'); return value;
}
function canRun(item) { return item.eligibility === 'READY' && !terminal.includes(item.record?.status); }
function el(tag, cls, text) { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; }
function render(value) {
  status = value; const e = value.engine;
  const busy = e.busy || value.connecting || value.commandBusy;
  const locked = busy || e.state === 'PAUSED';
  if (!initialized) { value.catalog.filter(canRun).forEach(row => selection.add(row.id)); initialized = true; }
  $('connection').textContent = value.connecting ? '正在啟動 WDA…' : value.connected ? 'iPhone 已連線' : '尚未連線';
  $('connection').classList.toggle('on', value.connected);
  $('state').textContent = states[e.state] || e.state;
  $('progress').textContent = e.current && e.state !== 'COMPLETED' ? e.current : e.total ? `${Math.min(e.index,e.total)} / ${e.total} 筆已處理` : '準備好，再開始。';
  $('reason').textContent = e.reason; $('bar').max = e.total || 5; $('bar').value = e.index;
  $('connect').disabled = busy || value.connected; $('disconnect').disabled = !value.connected || locked;
  $('mobile-pair').disabled=locked || !value.connected;
  $('devices').disabled = locked; $('start').disabled = !value.connected || locked || !$('accepted').checked || !value.catalog.some(row => selection.has(row.id) && canRun(row));
  $('pause').disabled = e.state !== 'RUNNING'; $('resume').disabled = e.state !== 'PAUSED' || busy;
  $('stop').disabled = !['RUNNING','PAUSED'].includes(e.state);
  ['inspect','capture'].forEach(id => $(id).disabled = !value.connected || busy);
  ['restore','import','select-all'].forEach(id => $(id).disabled = locked);
  $('count').textContent = value.catalog.length;
  const signature = JSON.stringify([value.catalog, [...selection], locked, value.connected]);
  if ($('catalog').dataset.signature !== signature) {
    $('catalog').dataset.signature = signature;
    $('catalog').replaceChildren(...value.catalog.map(row => {
      const card = el('div','item'), label = el('label'), checkbox = el('input'); checkbox.type='checkbox';
      checkbox.setAttribute('aria-label', `選擇 ${row.title}`); checkbox.checked = selection.has(row.id) && canRun(row); checkbox.disabled = locked || !canRun(row);
      checkbox.addEventListener('change', () => { checkbox.checked ? selection.add(row.id) : selection.delete(row.id); render(status); });
      label.append(checkbox); const body = el('div','item-body'); body.append(el('div','item-title',row.title),el('div','item-url',row.shortUrl || row.url));
      const meta = el('div','item-meta'); const state = row.record?.status || row.eligibility;
      meta.append(el('span',`tag ${state === 'REVIEW' ? 'review' : terminal.includes(state) ? 'done' : ''}`,labels[state] || state));
      for (const [action,text] of [['manual','標記已完成'],...(row.record ? [['clear','清除本筆紀錄']] : [])]) {
        const button = el('button','text-button record-button',text); button.disabled = locked || !value.connected;
        button.onclick = async () => { if (action === 'clear' && !confirm('清除後可重新選取，可能重複抽選。確認已人工核對此活動？')) return;
          try { render(await api('record',{id:row.id,action})); } catch(error) { toast(error.message); } };
        meta.append(button);
      }
      body.append(meta); if (row.record?.reason) body.append(el('div','item-reason',row.record.reason)); card.append(label,body); return card;
    }));
  }
  $('events').textContent = value.events.map(event => `${event.at}  ${event.index === null ? '' : `第 ${event.index+1} 筆`}  ${event.code} ${event.detail}`).reverse().join('\n') || '尚無執行紀錄。';
}
function on(id, action) { $(id).onclick = async () => { try { await action(); } catch(error) { toast(error.message); } }; }
on('devices', async () => {
  $('setup-message').textContent = '正在讀取 USB 裝置…'; const {devices} = await api('devices');
  $('device-list').replaceChildren(...devices.map(device => { const b=el('button','secondary',`${device.name} · iOS ${device.version}`); b.onclick=()=>{$('udid').value=device.udid;$('version').value=device.version;};return b;}));
  $('setup-message').textContent = devices.length ? '點選裝置以填入 UDID。' : '未找到可連線 iPhone。請接上 USB、解鎖並信任這部 Mac。';
});
on('connect', async () => {
  $('connect').disabled = true; $('setup-message').textContent = '首次建置 WDA 可能需要數分鐘，請保持 iPhone 解鎖。';
  try { render(await api('connect',{udid:$('udid').value.trim(),profile:$('profile').value.trim(),mode:$('mode').value,
    teamId:$('team').value.trim(),wdaBundleId:$('bundle').value.trim(),platformVersion:$('version').value.trim(),wdaUrl:$('wda-url').value.trim(),ocr:$('ocr').checked}));
    $('setup-message').textContent='已連線。開始前請在手機確認 LINE 帳號。';
  } catch(error) { $('setup-message').textContent=error.message; throw error; }
});
for(const route of ['disconnect','pause','resume','stop']) on(route,async()=>render(await api(route)));
on('start',async()=>render(await api('start',{ids:[...selection],accepted:$('accepted').checked,autoFriend:$('auto-friend').checked})));
on('select-all',async()=>{selection=new Set(status.catalog.filter(canRun).map(row=>row.id));render(status);});
$('accepted').addEventListener('change',()=>render(status));
on('inspect',async()=>{const result=await api('inspect');$('inspection').textContent=JSON.stringify(result,null,2);});
on('capture',async()=>{
  if(!confirm('將目前 LINE 截圖與完整畫面元素存到本機，可能含帳號或聊天資訊。請先停留在測試優惠券頁；分享檔案前自行檢查。')) return;
  const result=await api('capture');$('inspection').textContent=`已儲存至：\n${result.directory}`;
});
on('restore',async()=>{selection=new Set();initialized=false;render(await api('five-links'));});
$('import').addEventListener('change',async event=>{try{const file=event.target.files[0];if(!file)return;const rows=JSON.parse(await file.text());const result=await api('catalog',{rows});initialized=false;selection=new Set();render(result);toast('已載入清單；既有紀錄保留。');}catch(error){toast(error.message);}finally{event.target.value='';}});
try { ({token}=await (await fetch('/api/bootstrap')).json()); render(await (await fetch('/api/status')).json()); }
catch { toast('無法連上本機服務，請重新執行啟動檔。'); }
async function poll(){try{render(await (await fetch('/api/status')).json());}catch{$('connection').textContent='本機服務已中斷';$('start').disabled=true;}finally{setTimeout(poll,1000);}}setTimeout(poll,1000);

on('mobile-pair',async()=>{const r=await api('mobile-pair');$('mobile-qr').src='data:image/png;base64,'+r.qr;$('mobile-uri').value=r.uri;$('mobile-expiry').textContent='有效至 '+new Date(r.expiresAt).toLocaleTimeString();$('mobile-invitation').hidden=false;});
on('mobile-revoke',async()=>{if(!confirm('停止手機 App 批次並撤銷所有手機配對？'))return;await api('mobile-revoke');$('mobile-invitation').hidden=true;toast('手機配對已撤銷，HTTPS 控制端點已關閉。');});
