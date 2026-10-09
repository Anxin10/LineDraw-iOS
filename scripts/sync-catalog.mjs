#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const CATALOG_PATH = path.resolve(ROOT, 'catalog.json');

// Re-use mobile-catalog from ios-wda
const {fetchWebsite} = await import(path.resolve(ROOT, 'ios-wda/src/mobile-catalog.mjs'));

async function main() {
  console.log('=== LineDraw Catalog Sync ===');
  const t0 = Date.now();
  console.log('Fetching catalog from funbox-line & resolving short links with cache...');

  const rows = await fetchWebsite();
  console.log(`Successfully processed ${rows.length} draw items.`);

  const runnableCount = rows.filter(r => r.canonicalURL).length;
  console.log(`Fully resolved items with canonical URL: ${runnableCount}/${rows.length}`);

  await fs.writeFile(CATALOG_PATH, JSON.stringify(rows, null, 2), 'utf8');
  console.log(`Wrote catalog to: ${CATALOG_PATH} (${(Buffer.byteLength(JSON.stringify(rows)) / 1024).toFixed(1)} KB)`);

  const elapsed = ((Date.now() - t0) / 1000).toFixed(2);
  console.log(`Done in ${elapsed}s.`);
}

main().catch(err => {
  console.error('Sync failed:', err);
  process.exit(1);
});
