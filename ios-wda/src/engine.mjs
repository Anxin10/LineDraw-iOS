import {classify, targetKey} from './screen.mjs';
import {eligibility, validateCatalog} from './catalog.mjs';

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const TERMINAL = new Set(['SUBMITTED', 'ALREADY', 'COMPLETE', 'MANUAL', 'REVIEW', 'ENDED', 'ADD_FRIEND_INTENT', 'SUBMIT_INTENT', 'ADD_FRIEND_AND_SUBMIT_INTENT']);

export class Engine {
  constructor({driver, store, clock = () => performance.now(), wallClock = Date.now, delay = sleep,
    pollMs = 650, loadMs = 30_000, settleMs = 1_000, navigationGraceMs = 5_000, online = async () => true, offlineMs = 60_000} = {}) {
    Object.assign(this, {driver, store, clock, wallClock, delay, pollMs, loadMs, settleMs, navigationGraceMs, online, offlineMs});
    this.state = 'IDLE'; this.reason = '請先連線 iPhone，再選擇測試項目。'; this.queue = [];
    this.index = 0; this.worker = null; this.scope = ''; this.autoFriend = true;
  }
  active() { return this.state === 'RUNNING'; }
  view() { return {state: this.state, reason: this.reason, index: this.index, total: this.queue.length, busy: !!this.worker,
    current: this.queue[this.index]?.title || null, queue: this.queue.map(row => ({...row, record: this.store.record(this.scope, row.id) || null}))}; }
  start(rows, {scope, autoFriend = true} = {}) {
    if (this.worker || this.state === 'PAUSED') throw new Error('請先停止目前批次。');
    if (!scope) throw new Error('缺少裝置紀錄範圍。');
    this.queue = validateCatalog(rows);
    if (this.queue.every(item => TERMINAL.has(this.store.record(scope, item.id)?.status) || eligibility(item, this.wallClock()) !== 'READY')) {
      throw new Error('所選項目已有紀錄、尚未開始或已截止，沒有可執行項目。');
    }
    this.scope = scope; this.autoFriend = autoFriend; this.index = 0;
    this.launch();
  }
  launch() {
    this.state = 'RUNNING'; this.reason = '開始依序處理。';
    this.worker = this.loop().catch(error => {
      this.state = 'PAUSED'; this.reason = error.message;
      try { this.store.event('PAUSED_ERROR', this.index, error.message); } catch { /* Keep the UI stopped even if storage failed. */ }
    }).finally(() => { this.worker = null; });
  }
  pause(reason = '使用者暫停；目前已派送的操作可能仍會完成。') { if (this.active()) { this.state = 'PAUSED'; this.reason = reason; } }
  resume() {
    if (this.state !== 'PAUSED' || this.worker) throw new Error('請等目前指令結束後再恢復。');
    this.launch();
  }
  stop() { this.state = 'STOPPED'; this.reason = '已停止；保留紀錄，不再派送下一個操作。'; }
  skip() {
    if (this.state !== 'PAUSED' || this.worker) throw new Error('請先暫停並等待目前指令結束。');
    const item = this.queue[this.index];
    if (item && !this.store.record(this.scope, item.id)) this.store.setRecord(this.scope, item.id, 'SKIPPED', '使用者略過本筆，未標記已抽選。');
    this.store.event('SKIPPED', this.index); this.index++; this.launch();
  }
  async awaitOnline() {
    const began = this.clock();
    while (this.active() && !await this.online()) {
      this.reason = '網路中斷，等待恢復（最多 60 秒）。';
      if (this.clock() - began >= this.offlineMs) { this.pause('網路尚未恢復，請確認連線後繼續。'); this.store.event('OFFLINE_PAUSE', this.index); return false; }
      await this.delay(Math.min(1000, this.pollMs));
    }
    return this.active();
  }
  async loop() {
    for (; this.index < this.queue.length && this.active(); this.index++) {
      const item = this.queue[this.index];
      if (TERMINAL.has(this.store.record(this.scope, item.id)?.status)) continue;
      if (eligibility(item, this.wallClock()) !== 'READY') {
        this.store.event('OUTSIDE_TIME', this.index); continue;
      }
      const done = await this.process(item);
      if (!done) return;
    }
    if (this.active()) { this.state = 'COMPLETED'; this.reason = '本輪已處理完畢；已送出不代表中獎或伺服器確認參加。'; }
  }
  async process(item) {
    let friendAttempted = this.store.record(this.scope, item.id)?.status === 'FRIEND_ADDED';
    let retargets = 0;
    for (let attempt = 0; attempt < 2 && this.active(); attempt++) {
      this.reason = attempt ? '載入逾時，重新開啟一次。' : '正在開啟抽選頁面。';
      this.store.event('OPEN', this.index, attempt ? 'RETRY' : 'FIRST');
      if (!await this.awaitOnline()) return false;
      let baseline;
      try { baseline = await this.driver.open(item.url, () => this.active()); }
      catch (error) { if (error.notDispatched && !this.active()) return false; throw error; }
      if (!this.active()) return false;
      let start = this.clock(); let navigated = false; let lastKey = ''; let stable = 0;
      while (this.active() && this.clock() - start < this.loadMs) {
        const checkingNetworkAt = this.clock();
        if (!await this.awaitOnline()) return false;
        start += this.clock() - checkingNetworkAt;
        const screen = await this.driver.snapshot();
        if (!this.active()) return false;
        // Universal Link animation briefly reports SpringBoard on real iOS.
        // Wait only during the opening window; never click or count it as navigation.
        if (screen.bundleId === 'com.apple.springboard' && this.clock() - start < Math.min(this.navigationGraceMs, this.loadMs)) {
          stable = 0; lastKey = ''; this.reason = '等待 iOS 完成切換至 LINE。';
          await this.delay(this.pollMs); continue;
        }
        if (screen.bundleId === screen.expectedBundle && screen.fingerprint !== baseline) navigated = true;
        const decision = classify(screen, {autoFriend: this.autoFriend, friendAttempted});
        if (decision.kind === 'pause') { this.pause(decision.reason); this.store.event('MANUAL_PAUSE', this.index); return false; }
        // A deep-link response alone does not prove the old coupon disappeared.
        if (!navigated || this.clock() - start < this.settleMs) {
          this.reason = '等待新頁載入，避免點到上一筆。'; await this.delay(this.pollMs); continue;
        }
        const key = targetKey(decision);
        stable = lastKey === key ? stable + 1 : 1; lastKey = key;
        if (stable < 2 || decision.kind === 'wait') { this.reason = '等待可辨識的抽選按鈕。'; await this.delay(this.pollMs); continue; }
        if (['already', 'complete', 'ended'].includes(decision.kind)) {
          this.store.setRecord(this.scope, item.id, decision.kind === 'ended' ? 'ENDED' : decision.kind.toUpperCase(), '已辨識終止畫面，接續下一筆。');
          this.store.event(decision.kind.toUpperCase(), this.index); return true;
        }
        if (decision.kind === 'reopen') break;
        if (decision.kind === 'click') {
          if (eligibility(item, this.wallClock()) !== 'READY') { this.store.event('EXPIRED_BEFORE_CLICK', this.index); return true; }
          this.reason = decision.action === 'ADD_FRIEND' ? '正在加入好友。' : '正在送出抽選。';
          const previous = this.store.record(this.scope, item.id);
          this.store.setRecord(this.scope, item.id, `${decision.action}_INTENT`, '操作意圖已保存。');
          try { await this.driver.tap(decision.target, () => this.active()); }
          catch (error) {
            if (error.notDispatched) {
              if (previous) this.store.setRecord(this.scope, item.id, previous.status, previous.reason);
              else this.store.clearRecord(this.scope, item.id);
              // A rebuilt WebView may lose its element between source and lookup.
              // Retry only known pre-dispatch failures, with fresh stable snapshots.
              if (error.retryable && this.active() && retargets < 2 && this.clock() - start < this.loadMs) {
                retargets++; stable = 0; lastKey = '';
                this.reason = '按鈕更新中，重新定位後再操作。';
                this.store.event('RETARGET', this.index);
                await this.delay(this.pollMs);
                continue;
              }
            } else {
              this.store.setRecord(this.scope, item.id, 'REVIEW', '點擊回應中斷，可能已送出；需人工確認，不自動重試。');
            }
            if (this.active()) this.pause(error.message);
            return false;
          }
          if (decision.action === 'ADD_FRIEND') {
            friendAttempted = true;
            this.store.setRecord(this.scope, item.id, 'FRIEND_ADDED', '已送出加入好友操作，回到原活動繼續。');
            // Reopen the same coupon without repeatedly adding the account.
            break;
          }
          this.store.setRecord(this.scope, item.id, 'SUBMITTED', '點擊指令已回應；不等待中獎結果，直接接續。');
          this.store.event('SUBMITTED', this.index); return true;
        }
      }
    }
    if (!this.active()) return false;
    this.store.setRecord(this.scope, item.id, 'LOAD_TIMEOUT', '兩次載入仍無法辨識新頁或按鈕；本輪略過，可手動重試。');
    this.store.event('LOAD_TIMEOUT', this.index); return true;
  }
}
