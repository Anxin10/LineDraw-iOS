import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
const exec = promisify(execFile);

export function visionOcr(executable) {
  return async (base64, screen) => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'linedraw-ocr-'));
    try {
      const image = path.join(dir, 'screen.png');
      await fs.writeFile(image, Buffer.from(base64, 'base64'), {mode: 0o600});
      const {stdout} = await exec(executable, [image], {timeout: 20_000, maxBuffer: 1_000_000});
      return JSON.parse(stdout).map(item => ({type: 'OCRText', source: 'ocr', visible: true, enabled: true,
        confidence: item.confidence, labels: [item.text], rect: {
          x: item.x * screen.width, y: item.y * screen.height,
          width: item.width * screen.width, height: item.height * screen.height,
        }}));
    } finally { await fs.rm(dir, {recursive: true, force: true}); }
  };
}
