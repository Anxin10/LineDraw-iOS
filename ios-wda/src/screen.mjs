import {createHash} from 'node:crypto';
import {XMLParser, XMLValidator} from 'fast-xml-parser';

export const normalize = text => String(text ?? '').normalize('NFKC').replace(/\s+/gu, '').replace(/[!！。.…]+$/u, '');
const SUBMIT = ['參加抽選', '立即抽選', '挑戰抽獎', '立即抽獎', '參加抽獎', '抽獎', '抽選'];
const COMBINED = ['加入好友並抽選', '加入好友並抽獎', '加入好友並參加抽獎'];
const ALREADY = ['查看已領取的優惠券', '您已參加過此抽選', '已參加過抽獎', '已抽過'];
const RESULTS = ['恭喜中獎', '恭喜您中獎了', '恭喜獲得優惠券', '很可惜，未中獎', '未中獎', '未抽中', '銘謝惠顧', '抽選完成', '抽獎完成'];
const BLOCKERS = ['驗證碼', '验证码', 'CAPTCHA', '登入', '登录', '解除封鎖', '授權存取', '同意條款', '付款'];
export const ACTION_LABELS = [...COMBINED, ...SUBMIT, '加入好友'];

export function parseSource(xml) {
  if (typeof xml !== 'string' || xml.length > 8_000_000 || /<!DOCTYPE|<!ENTITY/i.test(xml) || XMLValidator.validate(xml) !== true) {
    throw new Error('WDA 畫面資料無法解析。');
  }
  const root = new XMLParser({ignoreAttributes: false, attributeNamePrefix: '', parseAttributeValue: false,
    processEntities: true, allowBooleanAttributes: true}).parse(xml);
  const nodes = [];
  function walk(value, tag = '', parentVisible = true, webViewRect = null) {
    if (Array.isArray(value)) return value.forEach(child => walk(child, tag, parentVisible, webViewRect));
    if (!value || typeof value !== 'object') return;
    const visible = parentVisible && value.visible !== 'false' && tag !== 'XCUIElementTypeStatusBar';
    const rect = Object.fromEntries(['x', 'y', 'width', 'height'].map(k => [k, Number(value[k] || 0)]));
    const labels = [...new Set([value.label, value.name, value.value].filter(v => typeof v === 'string' && v.trim()))];
    if (tag.startsWith('XCUIElementType') && visible) {
      nodes.push({type: value.type || tag, labels, enabled: value.enabled !== 'false', visible,
        rect, source: 'native'});
    }
    const webRect = tag === 'XCUIElementTypeWebView' && visible ? rect : webViewRect;
    // Observed in LINE 26.15 on iOS 27: a full-WebView, non-accessible, unnamed
    // wrapper is marked invisible although its coupon children are visible.
    // Do not generalize this to hidden windows, named elements or native views.
    const webWrapper = parentVisible && webRect && webRect.width > 0 && webRect.height > 0 &&
      tag === 'XCUIElementTypeOther' && value.visible === 'false' && value.accessible === 'false' && !labels.length &&
      ['x', 'y', 'width', 'height'].every(k => Math.abs(rect[k] - webRect[k]) <= 1);
    for (const [key, child] of Object.entries(value)) if (child && typeof child === 'object') walk(child, key, visible || webWrapper, webRect);
  }
  walk(root);
  return nodes;
}

export function fingerprint(nodes) {
  // Ignore ephemeral XCTest IDs and parent aggregate strings. Do not identify the merchant/activity.
  const parts = nodes.filter(n => !['XCUIElementTypeApplication', 'XCUIElementTypeWindow'].includes(n.type))
    .map(n => [n.type, n.labels, n.enabled, n.rect]);
  return createHash('sha256').update(JSON.stringify(parts)).digest('hex');
}

function matching(nodes, labels, {bottom = false, height = 0, includeDisabled = false} = {}) {
  const names = labels.map(normalize);
  const matches = nodes.filter(n => n.visible && (n.enabled || includeDisabled) &&
    n.rect.width > 0 && n.rect.height > 0 && n.labels.some(l => names.includes(normalize(l))) &&
    (n.source !== 'ocr' || (n.confidence >= 0.9 && height > 0 && n.rect.y >= height * 0.60)) &&
    (!bottom || (height > 0 && n.rect.y >= height * 0.60)));
  // A button and its contained static label represent one target, not two actions.
  return matches.filter((node, i) => !matches.some((other, j) => j !== i &&
    other.type === 'XCUIElementTypeButton' && node.type !== 'XCUIElementTypeButton' &&
    node.rect.x >= other.rect.x && node.rect.y >= other.rect.y &&
    node.rect.x + node.rect.width <= other.rect.x + other.rect.width + 1 &&
    node.rect.y + node.rect.height <= other.rect.y + other.rect.height + 1))
    .filter((node, i, list) => list.findIndex(n => JSON.stringify(n.rect) === JSON.stringify(node.rect) &&
      n.labels.some(l => node.labels.some(r => normalize(l) === normalize(r)))) === i);
}

export function classify(screen, {autoFriend = true, friendAttempted = false} = {}) {
  const nodes = screen.nodes;
  const texts = nodes.flatMap(n => n.labels).map(normalize);
  const has = labels => labels.some(label => texts.includes(normalize(label)));
  const knownCoupon = has(['官方帳號優惠券', '查看我的優惠券']) ||
    matching(nodes, [...ACTION_LABELS, '查看已領取的優惠券', '已結束'], {bottom: true, height: screen.height, includeDisabled: true}).length > 0;
  if (screen.bundleId !== screen.expectedBundle) return {kind: 'pause', reason: '已離開 LINE 或出現系統畫面，請處理後恢復。'};
  if (nodes.some(n => n.type === 'XCUIElementTypeAlert')) return {kind: 'pause', reason: 'LINE 或系統顯示對話框，請先人工處理。'};
  if (knownCoupon && matching(nodes, ['已結束'], {bottom: true, height: screen.height, includeDisabled: true}).length) return {kind: 'ended'};
  // Reopening a won coupon shows its redemption button, not the result sheet.
  // Treat it as already received; this button must never become a click target.
  if (knownCoupon && matching(nodes, ['使用優惠券'], {bottom: true, height: screen.height, includeDisabled: true}).length) return {kind: 'already'};
  if (knownCoupon && matching(nodes, ['可惜...沒有抽中！'], {bottom: true, height: screen.height, includeDisabled: true}).length) return {kind: 'complete'};
  if (knownCoupon && has(ALREADY)) return {kind: 'already'};
  if (knownCoupon && has(RESULTS)) return {kind: 'complete'};
  if (texts.some(t => BLOCKERS.some(word => t.toLowerCase().includes(normalize(word).toLowerCase())))) {
    return {kind: 'pause', reason: '畫面需要登入、驗證或其他人工處理。'};
  }
  const candidates = matching(nodes, ACTION_LABELS, {bottom: true, height: screen.height});
  if (candidates.length > 1) return {kind: 'pause', reason: '底部存在多個可操作目標，已暫停以免點錯。'};
  if (candidates.length === 1) {
    const node = candidates[0];
    const label = node.labels.find(l => ACTION_LABELS.map(normalize).includes(normalize(l)));
    const action = COMBINED.map(normalize).includes(normalize(label)) ? 'ADD_FRIEND_AND_SUBMIT' :
      normalize(label) === normalize('加入好友') ? 'ADD_FRIEND' : 'SUBMIT';
    if (action.includes('FRIEND') && !autoFriend) return {kind: 'pause', reason: '本筆需要加入好友，請開啟自動加入好友。'};
    if (action === 'ADD_FRIEND' && friendAttempted) return {kind: 'wait'};
    return {kind: 'click', action, target: node, label: normalize(label)};
  }
  // Standalone official-account friend page can place its native Add button above the bottom bar.
  const friend = matching(nodes, ['加入好友']).filter(n => n.type === 'XCUIElementTypeButton');
  if (!friendAttempted && friend.length === 1 && has(['官方帳號', '官方帳號優惠券'])) {
    return autoFriend ? {kind: 'click', action: 'ADD_FRIEND', target: friend[0], label: normalize('加入好友')} :
      {kind: 'pause', reason: '需要加入好友。'};
  }
  if (friendAttempted && has(['已加入好友', '聊天'])) return {kind: 'reopen'};
  return {kind: 'wait'};
}

export function closeTarget(screen) {
  if (!screen.nodes.some(n => n.labels.some(l => ['官方帳號優惠券', '查看我的優惠券'].includes(normalize(l))))) return null;
  const items = matching(screen.nodes, ['關閉', 'Close', '关闭']).filter(n => n.type === 'XCUIElementTypeButton' && n.rect.y < screen.height * 0.22);
  return items.length === 1 ? items[0] : null;
}

export function targetKey(decision) {
  return JSON.stringify([decision.kind, decision.action, decision.label, decision.target?.rect]);
}
