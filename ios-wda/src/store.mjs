import fs from 'node:fs';
import path from 'node:path';

export class Store {
  constructor(directory) {
    this.directory = directory;
    fs.mkdirSync(directory, {recursive: true, mode: 0o700});
    this.file = path.join(directory, 'state.json');
    this.data = {version: 1, catalog: null, records: {}, events: []};
    if (fs.existsSync(this.file)) {
      this.data = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (this.data.version !== 1 || !this.data.records || !Array.isArray(this.data.events)) throw new Error('紀錄格式錯誤；保留原檔，請先檢查 .data/state.json。');
      for (const record of Object.values(this.data.records)) {
        if (record.status.endsWith('_INTENT')) {
          record.status = 'REVIEW'; record.reason = '上次程序中斷，操作可能已送出；不自動重試。';
        }
      }
      this.save();
    }
  }
  save() {
    const temp = this.file + '.tmp';
    const fd = fs.openSync(temp, 'w', 0o600);
    try { fs.writeFileSync(fd, JSON.stringify(this.data, null, 2)); fs.fsyncSync(fd); }
    finally { fs.closeSync(fd); }
    fs.renameSync(temp, this.file);
    const dir = fs.openSync(this.directory, 'r');
    try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); }
  }
  key(scope, id) { return `${scope}\n${id}`; }
  record(scope, id) { return this.data.records[this.key(scope, id)]; }
  setRecord(scope, id, status, reason = '') {
    this.data.records[this.key(scope, id)] = {status, reason, at: new Date().toISOString()}; this.save();
  }
  clearRecord(scope, id) { delete this.data.records[this.key(scope, id)]; this.save(); }
  event(code, index = null, detail = '') {
    this.data.events.push({at: new Date().toISOString(), code, index, detail});
    this.data.events = this.data.events.slice(-200); this.save();
  }
}
