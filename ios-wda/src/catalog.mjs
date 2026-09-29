export const LINE_BUNDLE = 'jp.naver.line';
export const LIFF_APP = '1654883387-DxN9w07M';
export const FIVE_LINKS = [
  ['WGMIH4U', '01M34QPHTDYX6TQ5F0M5TKP5J7'],
  ['niRxKxI', '01M34QQ7QZNTMR8M7ADSWXY7AW'],
  ['Q8gr93W', '01M34QQXZ27VBQPSY134CD6FG4'],
  ['x2IpNpc', '01M34QRHHTGYP0NZ594RCR9Z6T'],
  ['TCxN08P', '01M34QS2Y5Z75XA9E8ED6SWBD4'],
].map(([short, coupon], i) => ({
  id: `coupon:${LIFF_APP}:${coupon}`,
  title: `陀螺獵人抽選測試 · 第 ${i + 1} 筆`,
  shortUrl: `https://lin.ee/${short}`,
  url: `https://liff.line.me/${LIFF_APP}/c/${coupon}`,
  startsAt: '2026-09-22T00:00:00+08:00',
  endsAt: '2026-09-30T00:00:00+08:00',
}));

export function couponUrl(value) {
  const u = new URL(value);
  if (u.protocol !== 'https:' || u.hostname !== 'liff.line.me' || u.port || u.username || u.password ||
      u.search || u.hash || !/^\/[A-Za-z0-9_-]+\/c\/[A-Za-z0-9_-]+$/.test(u.pathname)) {
    throw new Error('只接受完整的 HTTPS LIFF 優惠券連結（/應用 ID/c/優惠券 ID），不接受其他網域或參數。');
  }
  return u.href;
}

export function validateCatalog(rows) {
  if (!Array.isArray(rows) || !rows.length || rows.length > 5000) throw new Error('清單必須有 1～5000 筆。');
  const seen = new Set();
  return rows.map((row, index) => {
    const url = couponUrl(row.url);
    const [, app, , coupon] = new URL(url).pathname.split('/');
    const id = `coupon:${app}:${coupon}`;
    if (seen.has(id)) throw new Error(`第 ${index + 1} 筆活動重複。`);
    seen.add(id);
    for (const field of ['startsAt', 'endsAt']) {
      if (typeof row[field] !== 'string' || !/(Z|[+-]\d\d:\d\d)$/.test(row[field]) || !Number.isFinite(Date.parse(row[field]))) {
        throw new Error(`第 ${index + 1} 筆 ${field} 必須是包含時區的 ISO 日期。`);
      }
    }
    if (Date.parse(row.endsAt) <= Date.parse(row.startsAt)) throw new Error('截止時間必須晚於開始時間。');
    return {id, url, title: String(row.title || `抽選 ${index + 1}`).slice(0, 200),
      startsAt: row.startsAt, endsAt: row.endsAt,
      ...(FIVE_LINKS.find(item => item.id === id)?.shortUrl ? {shortUrl: FIVE_LINKS.find(item => item.id === id).shortUrl} : {})};
  });
}

export function eligibility(item, now = Date.now()) {
  if (now < Date.parse(item.startsAt)) return 'NOT_STARTED';
  if (now >= Date.parse(item.endsAt)) return 'EXPIRED';
  return 'READY';
}
