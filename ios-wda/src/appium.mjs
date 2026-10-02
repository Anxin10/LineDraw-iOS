import {parseSource, fingerprint, normalize, closeTarget, ACTION_LABELS, classify} from './screen.mjs';
import {LINE_BUNDLE, couponUrl} from './catalog.mjs';

export class NotDispatched extends Error {
  constructor(message, {retryable = false} = {}) { super(message); this.notDispatched = true; this.retryable = retryable; }
}
export function localUrl(value) {
  const u = new URL(value);
  if (u.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(u.hostname) || u.username || u.password || u.search || u.hash) {
    throw new Error('Appium／WDA 僅接受本機 HTTP 位址。');
  }
  return u.href.replace(/\/$/, '');
}
export class AppiumDriver {
  constructor({baseUrl = 'http://127.0.0.1:4725', fetchImpl = fetch, bundleId = LINE_BUNDLE, ocr = null} = {}) {
    this.baseUrl = localUrl(baseUrl); this.fetch = fetchImpl; this.bundleId = bundleId; this.ocr = ocr;
    this.sessionId = null; this.udid = null;
  }
  async request(method, route, body, timeout = 25_000) {
    let response;
    try {
      response = await this.fetch(this.baseUrl + route, {method,
        headers: {'Content-Type': 'application/json'}, ...(body === undefined ? {} : {body: JSON.stringify(body)}),
        signal: AbortSignal.timeout(timeout)});
    } catch { throw new Error('Appium／USB 連線逾時或中斷；若正在點擊，請確認手機狀態。'); }
    const data = await response.json();
    if (!response.ok || data.value?.error) {
      // Do not copy page sources, device identifiers or URLs from driver error messages into normal logs.
      throw new Error(`Appium 指令失敗（${data.value?.error || response.status}）。請查看本機 Appium 日誌。`);
    }
    return data.value;
  }
  async connect(config) {
    if (!/^[A-Za-z0-9-]{8,80}$/.test(config.udid || '')) throw new Error('請輸入或選擇 iPhone 的 UDID。');
    const mode = config.mode || 'xcode';
    if (!['xcode', 'attach', 'preinstalled'].includes(mode)) throw new Error('不支援的 WDA 啟動模式。');
    const caps = {'platformName': 'iOS', 'appium:automationName': 'XCUITest',
      'appium:udid': config.udid, 'appium:bundleId': this.bundleId,
      'appium:noReset': true, 'appium:shouldTerminateApp': false, 'appium:forceAppLaunch': false,
      'appium:autoLaunch': false, 'appium:autoAcceptAlerts': false, 'appium:autoDismissAlerts': false,
      'appium:newCommandTimeout': 3600, 'appium:wdaLocalPort': 8105,
      'appium:wdaLaunchTimeout': 120000, 'appium:waitForIdleTimeout': 1,
      'appium:showXcodeLog': false};
    if (config.platformVersion) {
      if (!/^\d+(\.\d+){0,2}$/.test(config.platformVersion)) throw new Error('iOS 版本格式錯誤。');
      caps['appium:platformVersion'] = config.platformVersion;
    }
    if (config.teamId) {
      if (!/^[A-Z0-9]{10}$/.test(config.teamId)) throw new Error('Apple Team ID 必須是 10 碼英數字。');
      caps['appium:xcodeOrgId'] = config.teamId; caps['appium:xcodeSigningId'] = 'Apple Development';
    }
    if (config.wdaBundleId) {
      if (!/^[A-Za-z][A-Za-z0-9.-]{3,150}$/.test(config.wdaBundleId)) throw new Error('WDA Bundle ID 格式錯誤。');
      caps['appium:updatedWDABundleId'] = config.wdaBundleId;
    }
    if (mode === 'attach') caps['appium:webDriverAgentUrl'] = localUrl(config.wdaUrl || 'http://127.0.0.1:8105');
    if (mode === 'preinstalled') caps['appium:usePreinstalledWDA'] = true;
    const value = await this.request('POST', '/session', {capabilities: {alwaysMatch: caps, firstMatch: [{}]}}, 240_000);
    if (!value?.sessionId) throw new Error('Appium 未回傳 session ID。');
    this.sessionId = value.sessionId; this.udid = config.udid;
    this.actualVersion = value.capabilities?.platformVersion || config.platformVersion || '';
    await this.request('POST', `/session/${this.sessionId}/timeouts`, {implicit: 0});
    this.detectionRect = null;
    await this.configureForegroundDetection(await this.request('GET', this.route('/window/rect')));
  }
  route(suffix) {
    if (!this.sessionId) throw new Error('請先連線 iPhone。');
    return `/session/${this.sessionId}${suffix}`;
  }
  execute(script, args = {}) { return this.request('POST', this.route('/execute/sync'), {script, args: [args]}); }
  async disconnect() {
    if (this.sessionId) {
      try { await this.request('DELETE', this.route('')); }
      finally { this.sessionId = null; }
    }
  }
  async installed() { return this.execute('mobile: isAppInstalled', {bundleId: this.bundleId}); }
  async screenshot() { return this.request('GET', this.route('/screenshot')); }
  async configureForegroundDetection(rect) {
    if (!Number.isFinite(rect?.width) || !Number.isFinite(rect?.height) || rect.width <= 0 || rect.height <= 0) {
      throw new Error('無法取得 iPhone 畫面尺寸。');
    }
    const key = `${rect.width},${rect.height}`;
    if (this.detectionRect === key) return;
    // WDA's default upper-screen point can hit transient system overlays while
    // LINE remains visible. Keep automatic app detection, but sample the center.
    await this.request('POST', this.route('/appium/settings'), {settings: {
      activeAppDetectionPoint: `${rect.width / 2},${rect.height / 2}`,
    }});
    this.detectionRect = key;
  }
  async snapshot({withOcr = true} = {}) {
    const rect = await this.request('GET', this.route('/window/rect'));
    await this.configureForegroundDetection(rect);
    const active = await this.execute('mobile: activeAppInfo');
    const xml = await this.request('GET', this.route('/source'));
    const native = parseSource(xml);
    const screen = {bundleId: active.bundleId, expectedBundle: this.bundleId,
      nodes: native, width: rect.width, height: rect.height, xml};
    // OCR is explicitly enabled for the prototype; only run inside the intended app.
    const hasNativeAction = classify(screen).kind === 'ended' || native.some(n => n.labels.some(l => [...ACTION_LABELS, '查看已領取的優惠券', '已結束'].some(known => normalize(l) === normalize(known))) && n.rect.y >= rect.height * .60);
    if (this.ocr && withOcr && !hasNativeAction && active.bundleId === this.bundleId) {
      const image = await this.screenshot();
      screen.nodes = [...native, ...(await this.ocr(image, rect)).filter(n => n.rect.y > 50)];
    }
    screen.fingerprint = fingerprint(screen.nodes);
    return screen;
  }
  async open(url, canAct = () => true) {
    couponUrl(url);
    let before = await this.snapshot();
    if (!canAct()) throw new NotDispatched('批次已暫停。');
    // Close only a recognized coupon's native top Close button. This provides a navigation
    // boundary for two visually identical coupons, without verifying their merchant/title.
    const close = before.bundleId === this.bundleId ? closeTarget(before) : null;
    if (close) {
      await this.tap(close, canAct);
      before = await this.snapshot();
    }
    if (!canAct()) throw new NotDispatched('批次已暫停。');
    const target = this.bundleId === LINE_BUNDLE ? url : `linedraw-fixture://coupon/${new URL(url).pathname.split('/').at(-1)}`;
    // Let iOS deliver the LIFF Universal Link. Opening an HTTPS URL explicitly in
    // LINE can merely foreground its existing chat on iOS 27 / LINE 26.15.
    // The following snapshots still require LINE before allowing any action.
    await this.execute('mobile: deepLink', this.bundleId === LINE_BUNDLE ? {url: target} : {url: target, bundleId: this.bundleId});
    return before.fingerprint;
  }
  async tap(target, canAct = () => true) {
    // Re-read before tapping. A stale element/ambiguous label must never become a coordinate guess.
    const active = await this.execute('mobile: activeAppInfo');
    if (active.bundleId !== this.bundleId) throw new NotDispatched('前景已離開 LINE，未點擊。');
    if (!canAct()) throw new NotDispatched('批次已暫停，未點擊。');
    if (target.source === 'ocr') {
      const current = await this.snapshot();
      if (classify(current).kind !== 'click') throw new NotDispatched('畫面已不允許自動抽選，未點擊。');
      const match = current.nodes.filter(n => n.source === 'ocr' && n.confidence >= .9 &&
        n.labels.some(l => target.labels.some(r => normalize(l) === normalize(r))) &&
        Math.abs(n.rect.x - target.rect.x) < 8 && Math.abs(n.rect.y - target.rect.y) < 8);
      if (match.length !== 1 || current.bundleId !== this.bundleId || !canAct()) throw new NotDispatched('OCR 目標已變動，未點擊。');
      const r = match[0].rect;
      await this.execute('mobile: tap', {x: r.x + r.width / 2, y: r.y + r.height / 2});
      return;
    }
    const xml = await this.request('GET', this.route('/source'));
    const nodes = parseSource(xml);
    if (nodes.some(n => n.type === 'XCUIElementTypeAlert')) throw new NotDispatched('出現對話框，未點擊。');
    if (target.labels.some(l => ACTION_LABELS.some(known => normalize(l) === normalize(known)))) {
      const rect = await this.request('GET', this.route('/window/rect'));
      const currentDecision = classify({nodes, height: rect.height, bundleId: active.bundleId, expectedBundle: this.bundleId});
      if (currentDecision.kind !== 'click' || !target.labels.some(l => normalize(l) === currentDecision.label)) {
        throw new NotDispatched('畫面動作已變更，未點擊。');
      }
    }
    const labels = target.labels.filter(l => l.length < 120);
    const quote = value => JSON.stringify(value);
    const terms = labels.flatMap(label => ['label', 'name', 'value'].map(attr => `${attr} == ${quote(label)}`));
    if (!terms.length) throw new NotDispatched('目標沒有可定位的標籤。');
    const predicate = `type == ${quote(target.type)} AND visible == 1 AND enabled == 1 AND (${terms.join(' OR ')})`;
    const elements = await this.request('POST', this.route('/elements'), {using: '-ios predicate string', value: predicate});
    const candidates = [];
    for (const item of elements) {
      const id = item['element-6066-11e4-a52e-4f735466cecf'] || item.ELEMENT;
      const rect = await this.request('GET', this.route(`/element/${encodeURIComponent(id)}/rect`));
      if (Math.abs(rect.x - target.rect.x) < 8 && Math.abs(rect.y - target.rect.y) < 8 &&
          Math.abs(rect.width - target.rect.width) < 8 && Math.abs(rect.height - target.rect.height) < 8) candidates.push(id);
    }
    if (candidates.length !== 1) throw new NotDispatched('目標已變動或不唯一，未點擊。', {retryable: true});
    const latest = await this.execute('mobile: activeAppInfo');
    if (latest.bundleId !== this.bundleId || !canAct()) throw new NotDispatched('已暫停或切換 App，未點擊。');
    await this.request('POST', this.route(`/element/${encodeURIComponent(candidates[0])}/click`), {});
  }
}
